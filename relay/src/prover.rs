use serde::{Deserialize, Serialize};
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts};

#[derive(Debug, Serialize, Deserialize)]
struct GuestInput {
    tx_data: Vec<u8>,
    tx_hash: [u8; 32],
    tx_pub_key: [u8; 32],
    amount: u64,
    key_image: [u8; 32],
    recipient_addr: [u8; 65],
    amount_commit: [u8; 32],
    ki_hash: [u8; 32],
}

pub async fn generate_receipt(payload: &crate::SubmitRequest) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    println!("Generating RISC Zero proof for Monero burn...");
    
    // Parse stagenet Monero transaction data
    let monero_data = hex::decode(&payload.tx_hash.trim_start_matches("0x"))
        .map_err(|_| "Invalid hex in transaction hash")?;
    
    if monero_data.len() != 32 {
        return Err("Invalid transaction hash length".into());
    }
    
    let tx_hash: [u8; 32] = monero_data.try_into().unwrap();
    
    // Generate transaction data (from stagenet)
    let tx_data = generate_monero_tx_data(&payload).await?;
    
    // Parse fields
    let key_image = hex::decode(&payload.key_image.trim_start_matches("0x"))
        .map_err(|_| "Invalid key image hex")?
        .try_into()
        .map_err(|_| "Invalid key image length")?;
    
    let amount_commit = hex::decode(&payload.amount_commit.trim_start_matches("0x"))
        .map_err(|_| "Invalid amount commitment hex")?
        .try_into()
        .map_err(|_| "Invalid amount commitment length")?;
    
    // Extract amount from FHE ciphertext (mock for stagenet)
    let amount = extract_amount_from_payload(payload)?;
    
    // Generate recipient address (mock for stagenet)
    let recipient_addr = generate_recipient_address(&payload)?;
    
    // Compute ki_hash
    let mut ki_hash = [0u8; 32];
    let computed_hash = risc0_zkvm::sha::Sha256::hash(&key_image);
    ki_hash.copy_from_slice(&computed_hash);
    
    // Setup guest input
    let guest_input = GuestInput {
        tx_data,
        tx_hash,
        tx_pub_key: [0u8; 32], // Mock for stagenet
        amount,
        key_image,
        recipient_addr,
        amount_commit,
        ki_hash,
    };
    
    let env = ExecutorEnv::builder()
        .write(&guest_input)
        .unwrap()
        .build()
        .unwrap();
    
    // Load the RISC Zero ELF built from guest
    let elf = include_bytes!("../../guest/target/riscv-guest/riscv32im-risc0-zkvm-elf/release/risc0-xmr-guest").as_slice();
    
    // Use default prover for simplicity
    let prover = default_prover();
    
    // Generate the proof
    let receipt = prover.prove_elf(env, &elf).unwrap();
    
    // Serialize the receipt
    let receipt_bytes = bincode::serialize(&receipt).unwrap();
    
    println!("✅ Generated RISC Zero proof with {} bytes", receipt_bytes.len());
    
    Ok(receipt_bytes)
}

/// Extract amount from FHE policy payload (mock for stagenet)
fn extract_amount_from_payload(payload: &crate::SubmitRequest) -> Result<u64, Box<dyn std::error::Error>> {
    // In production: Decrypt FHE ciphertext to get actual amount
    // For stagenet: extract from commit string or use fixed amount
    
    let amount_str = &payload.amount_commit.trim_start_matches("0x");
    if amount_str.len() >= 16 {
        let bytes = hex::decode(amount_str).unwrap();
        let mut arr = [0u8; 8];
        arr.copy_from_slice(&bytes[..8]);
        Ok(u64::from_le_bytes(arr))
    } else {
        Ok(1_000_000_000_000) // Default 1 XMR in piconero
    }
}

/// Generate recipient address for bridge (mock for stagenet)
fn generate_recipient_address(payload: &crate::SubmitRequest) -> Result<[u8; 65], Box<dyn std::error::Error>> {
    // In production: Encode recipient from bridge metadata
    // For stagenet: generate mock address
    
    let mut addr = [0u8; 65];
    // Simple pattern to generate mock address
    for i in 0..65 {
        addr[i] = (i as u8).wrapping_add(0x42);
    }
    Ok(addr)
}

/// Generate Monero transaction data from stagenet
async fn generate_monero_tx_data(payload: &crate::SubmitRequest) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    // In production: Fetch actual transaction data from Monero daemon
    // For stagenet: generate mock transaction data
    
    let mut tx_data = vec![0u8; 128];
    for i in 0..128 {
        tx_data[i] = (i as u8).wrapping_add(0xAA);
    }
    
    // Add key image and transaction hash as context
    let key_image_bytes = hex::decode(&payload.key_image.trim_start_matches("0x")).unwrap();
    tx_data.extend_from_slice(&key_image_bytes);
    
    let tx_hash_bytes = hex::decode(&payload.tx_hash.trim_start_matches("0x")).unwrap();
    tx_data.extend_from_slice(&tx_hash_bytes);
    
    Ok(tx_data)
}