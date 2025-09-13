use clap::Parser;
use serde::{Deserialize, Serialize};
use std::env;
use tfhe::prelude::*;
use tfhe::{generate_keys, set_server_key, ConfigBuilder, FheUint64};

#[derive(Debug, Serialize, Deserialize)]
struct PolicyInput {
    amount: u64,
    timestamp: u64,
    current_timestamp: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct PolicyResult {
    ok: bool,
    amount: u64,
    fhe_result: Vec<u8>,
}

#[derive(Parser)]
#[command(name = "fhe-policy-engine")]
#[command(about = "TFHE Policy Engine for wxMR bridge", long_about = None)]
struct Args {
    #[arg(short, long, help = "Server key file path")]
    key_path: Option<String>,
    
    #[arg(short, long, help = "Run key generation")]
    generate_keys: bool,
    
    #[arg(short, long, help = "Evaluate policy on input")]
    evaluate: Option<String>,
}

fn generate_and_save_keys(key_path: &str) {
    println!("Generating FHE keys...");
    
    let config = ConfigBuilder::default().build();
    let (client_key, server_key) = generate_keys(config);
    
    let serialized_client = bincode::serialize(&client_key).unwrap();
    let serialized_server = bincode::serialize(&server_key).unwrap();
    
    std::fs::write(format!("{}.client", key_path), serialized_client).unwrap();
    std::fs::write(format!("{}.server", key_path), serialized_server).unwrap();
    
    println!("Keys saved to {}.client and {}.server", key_path, key_path);
}

fn evaluate_policy(input_json: &str) -> PolicyResult {
    let input: PolicyInput = serde_json::from_str(input_json).unwrap();
    
    // Load server key
    let key_path = env::var("FHE_SERVER_KEY_PATH")
        .unwrap_or_else(|_| "keys.fhe.server".to_string());
    
    let server_key_serialized = std::fs::read(key_path).unwrap();
    let server_key = bincode::deserialize(&server_key_serialized).unwrap();
    set_server_key(server_key);
    
    // FHE evaluation
    let amount = FheUint64::encrypt(input.amount);
    let max_amount = FheUint64::encrypt(10_000_000_000_000); // 10 XMR in atomic units
    
    let timestamp = FheUint64::encrypt(input.timestamp);
    let max_timestamp = FheUint64::encrypt(input.current_timestamp + 3600);
    
    // Policy: amount ≤ 10 XMR AND timestamp ≤ now + 1 hour
    let amount_ok = amount.le(&max_amount);
    let timestamp_ok = timestamp.le(&max_timestamp);
    let policy_ok = amount_ok & timestamp_ok;
    
    let policy_bit = policy_ok;
    let ok = policy_bit.decrypt(true) == 1;
    
    let serialized_policy = bincode::serialize(&policy_bit).unwrap();
    
    PolicyResult {
        ok,
        amount: input.amount,
        fhe_result: serialized_policy,
    }
}

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();
    let args = Args::parse();
    
    if args.generate_keys {
        let key_path = args.key_path.unwrap_or_else(|| "keys.fhe".to_string());
        generate_and_save_keys(&key_path);
        return;
    }
    
    if let Some(input_json) = args.evaluate {
        let result = evaluate_policy(&input_json);
        println!("{}", serde_json::to_string(&result).unwrap());
    } else {
        println!("No action specified. Use --generate-keys or --evaluate");
    }
}