use ethers::prelude::*;
use std::sync::Arc;
use std::str::FromStr;

pub async fn mint_with_proof(
    receipt: &[u8],
    amount: u64,
    key_image: &str,
    amount_commit: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    println!("Submitting RISC Zero proof to WxMR contract for mint...");
    
    // Load configuration from environment
    let rpc_url = std::env::var("ETHEREUM_RPC_URL")
        .unwrap_or_else(|_| "https://rpc.sepolia.org".to_string());
    
    let private_key = std::env::var("PRIVATE_KEY")
        .map_err(|_| "PRIVATE_KEY environment variable required")?;
    
    let contract_address = Address::from_str("0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5")
        .map_err(|_| "Invalid contract address")?;
    
    // Connect to Ethereum provider
    let provider = Provider::<Http>::try_from(rpc_url)?;
    let wallet = private_key.parse::<LocalWallet>()?;
    let client = SignerMiddleware::new(provider, wallet);
    let client = Arc::new(client);
    
    // ABI for wxMR contract (minimal interface)
    #[derive(Debug)]
    struct WXMRCONTRACT;
    
    // The ABI - essential functions only
    impl WXMRCONTRACT {
        const ABI: &'static str = r#"[
            {
                "inputs": [
                    {"internalType": "address", "name": "_verifier", "type": "address"},
                    {"internalType": "bytes32", "name": "_imageId", "type": "bytes32"},
                    {"internalType": "string", "name": "_name", "type": "string"},
                    {"internalType": "string", "name": "_symbol", "type": "string"}
                ], "stateMutability": "nonpayable", "type": "constructor"
            },
            {
                "inputs": [
                    {"internalType": "bytes", "name": "seal", "type": "bytes"},
                    {"internalType": "uint256", "name": "amount", "type": "uint256"},
                    {"internalType": "bytes32", "name": "KI_hash", "type": "bytes32"},
                    {"internalType": "bytes32", "name": "amount_commit", "type": "bytes32"}
                ],
                "name": "mint",
                "outputs": [],
                "stateMutability": "nonpayable",
                "type": "function"
            }
        ]"#;
    }
    
    let contract = Contract::new(contract_address, WXMRCONTRACT::ABI.as_bytes(), client);
    
    // Parse inputs
    let ki_hash_b32 = hex_to_bytes32(key_image)?;
    let amount_commit_b32 = hex_to_bytes32(amount_commit)?;
    let amount_u256 = U256::from(amount);
    
    // Function call data
    let mint_call = contract.method::<_, ()>(
        "mint",
        (
            Bytes::from(receipt.to_vec()),
            amount_u256,
            ki_hash_b32,
            amount_commit_b32,
        )
    )?;
    
    println!("Calling contract.mint()...");
    let tx = mint_call.send().await?;
    
    // Wait for transaction confirmation
    let receipt = tx.await?;
    let tx_hash = receipt
        .and_then(|r| Some(format!("{:?}", r.transaction_hash)))
        .unwrap_or_else(|| "Unknown".to_string());
    
    println!("✅ Mint confirmed on blockchain! Tx: {}", tx_hash);
    
    Ok(tx_hash)
}

fn hex_to_bytes32(hex_str: &str) -> Result<[u8; 32], Box<dyn std::error::Error>> {
    let bytes = hex::decode(hex_str.trim_start_matches("0x"))?;
    if bytes.len() != 32 {
        return Err("Expected 32 byte hex string".into());
    }
    let mut result = [0u8; 32];
    result.copy_from_slice(&bytes);
    Ok(result)
}