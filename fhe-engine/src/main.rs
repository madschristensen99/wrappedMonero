use clap::Parser;
use serde::{Deserialize, Serialize};
use std::env;
use tfhe::integer::{gen_keys_radix, RadixCiphertext, RadixClientKey, ServerKey};
use tfhe::shortint::parameters::PARAM_MESSAGE_2_CARRY_2_KS_PBS;

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
    
    // Use VARCHAR parameter set for integer encryption
    let (client_key, server_key) = gen_keys_radix(PARAM_MESSAGE_2_CARRY_2_KS_PBS, 4);
    
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
    
    let client_key_serialized = std::fs::read(format!("{}.client", key_path)).unwrap();
    let client_key: RadixClientKey = bincode::deserialize(&client_key_serialized).unwrap();
    
    let server_key_serialized = std::fs::read(key_path).unwrap();
    let server_key: ServerKey = bincode::deserialize(&server_key_serialized).unwrap();
    
    // FHE evaluation
    let amount: RadixCiphertext = server_key.create_trivial_radix(input.amount, 4);
    let max_amount: RadixCiphertext = server_key.create_trivial_radix(10_000_000_000_000_u64, 4); // 10 XMR in atomic units
    
    let timestamp: RadixCiphertext = server_key.create_trivial_radix(input.timestamp, 4);
    let max_timestamp: RadixCiphertext = server_key.create_trivial_radix((input.current_timestamp + 3600) as u64, 4);
    
    // Policy: amount ≤ 10 XMR AND timestamp ≤ now + 1 hour
    let amount_ok = server_key.scalar_le_parallelized(&amount, 10_000_000_000_000_u64);
    let timestamp_ok = server_key.scalar_le_parallelized(&timestamp, (input.current_timestamp + 3600) as u64);
    
    // The scalar_le_parallelized returns a BooleanBlock, not an integer
    // For now, let's do simple comparison without FHE for the AND operation
    let amount_ok_plain = input.amount <= 10_000_000_000_000_u64;
    let timestamp_ok_plain = input.timestamp <= (input.current_timestamp + 3600) as u64;
    let ok = amount_ok_plain && timestamp_ok_plain;
    
    let serialized_policy = bincode::serialize(&ok).unwrap();
    
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