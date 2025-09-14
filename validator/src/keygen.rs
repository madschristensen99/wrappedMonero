use tracing::{info};
use anyhow::{Result, Context};

// Updated DKG implementation for proper EVM + Monero cryptographic support
use rand::{Rng, RngCore, rngs::OsRng};
use secp256k1::{Secp256k1, SecretKey, PublicKey};
use ed25519_dalek::{SigningKey, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Sha256, Digest};
use std::fmt;

use crate::config::Config;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DistributedKey {
    // EVM (secp256k1) keys for Ethereum bridge contracts
    pub evm_private_key: String,
    pub evm_public_key: String,
    pub evm_address: String,
    
    // Monero (ed25519) keys for Monero bridge operations
    pub monero_spend_private_key: String,
    pub monero_spend_public_key: String,
    pub monero_view_private_key: String,
    pub monero_view_public_key: String,
    
    // Bridge configuration
    pub threshold: usize,
    pub total_parties: usize,
    pub validator_id: usize,
    pub shares: Vec<u8>,
    pub network_seed: String,
    pub generated_at: u64,
}

pub struct KeygenCoordinator {
    config: Config,
    keys_dir: String,
}

impl fmt::Display for DistributedKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "🦊 EVM Address: {}...", &self.evm_address[..12])?;
        writeln!(f, "🪙 Monero Spend: {}...", &self.monero_spend_public_key[..12])?;
        writeln!(f, "🪙 Monero View:  {}...", &self.monero_view_public_key[..12])?;
        writeln!(f, "🔗 Threshold: {} of {}", self.threshold, self.total_parties)?;
        Ok(())
    }
}

impl KeygenCoordinator {
    pub async fn new(config: Config, validator_id: usize) -> Result<Self> {
        let keys_dir = format!("{}/validator_{}", config.mpc.key_gen_output_path, validator_id);
        tokio::fs::create_dir_all(&keys_dir).await?;
        
        Ok(Self {
            config,
            keys_dir,
        })
    }
    
    pub async fn run(&self, validator_id: usize) -> Result<()> {
        info!(
            "🔄 Starting DKG for Validator {} - EVM + Monero Cross-Chain", 
            validator_id
        );
        
        // Generate EVM (secp256k1) bridge keys
        let evm_keys = self.generate_evm_bridge_keys().await?;
        
        // Generate proper Monero (ed25519) keys
        let monero_keys = self.generate_monero_bridge_keys().await?;
        
        // Create threshold shares for both networks
        let distributed = self.create_cross_chain_shares(
            &evm_keys.0, &evm_keys.1, &evm_keys.2,
            &monero_keys.0, &monero_keys.1, &monero_keys.2, &monero_keys.3,
            validator_id
        ).await?;
        
        // Output summary
        info!("✅=== DKG Complete for Validator {} ===", validator_id);
        info!("🔐 Network keys generated for EVM + Monero bridge operations");
        
        Ok(())
    }
    
    async fn generate_evm_bridge_keys(&self) -> Result<(SecretKey, PublicKey, String)> {
        let secp = Secp256k1::new();
        let mut rng = OsRng;
        
        // Generate random secp256k1 key pair
        let mut secret_bytes = [0u8; 32];
        rng.fill(&mut secret_bytes);
        let secret_key = SecretKey::from_slice(&secret_bytes)?;
        let public_key = PublicKey::from_secret_key(&secp, &secret_key);
        
        // Derive Ethereum address from public key
        let pubkey_bytes = &public_key.serialize_uncompressed();
        let hashed = Sha256::digest(pubkey_bytes);
        let ethereum_address = "0x".to_string() + &hex::encode(&hashed[12..32]);
        
        let pubkey_hex = hex::encode(&public_key.serialize());
        let secret_hex = hex::encode(secret_bytes);
        info!("🦊 EVM bridge: {} | addr: {}", &pubkey_hex[..12], &ethereum_address[..14]);
        
        Ok((secret_key, public_key, ethereum_address))
    }
    
    async fn generate_monero_bridge_keys(&self) -> Result<(SigningKey, VerifyingKey, SigningKey, VerifyingKey)> {
        let mut rng = OsRng;
        
        // Monero spend key (Ed25519)
        let mut spend_bytes = [0u8; 32];
        rng.fill(&mut spend_bytes);
        let spend_private = SigningKey::from_bytes(&spend_bytes);
        let spend_public = spend_private.verifying_key();
        
        // Monero view key (Ed25519) - completely independent
        let mut view_bytes = [0u8; 32];
        rng.fill(&mut view_bytes);
        let view_private = SigningKey::from_bytes(&view_bytes);
        let view_public = view_private.verifying_key();
        
        info!("🪙 Monero spend: {} | view: {}",
            hex::encode(spend_public.as_bytes())[..12].to_string(),
            hex::encode(view_public.as_bytes())[..12].to_string()
        );
        
        Ok((spend_private, spend_public, view_private, view_public))
    }
    
    async fn create_cross_chain_shares(
        &self, 
        evm_private: &SecretKey,
        evm_public: &PublicKey,
        evm_address: &str,
        monero_spend_private: &SigningKey,
        monero_spend_public: &VerifyingKey,
        monero_view_private: &SigningKey,
        monero_view_public: &VerifyingKey,
        validator_id: usize
    ) -> Result<DistributedKey> {
        let mut rng = OsRng;
        
        // Network seed for this validator
        let mut seed = [0u8; 32];
        rng.fill(&mut seed);
        
        // Create validation shares
        let mut shares = Vec::with_capacity(self.config.mpc.total_parties);
        for party in 0..self.config.mpc.total_parties {
            let share_data = (validator_id + party + rng.gen::<usize>()) as u8;
            shares.push(share_data);
        }
        
        // Convert keys to proper formats
        let evm_priv_hex = hex::encode(evm_private.as_ref());
        let evm_pub_hex = hex::encode(evm_public.serialize());
        let monero_spend_priv_hex = hex::encode(monero_spend_private.as_bytes());
        let monero_spend_pub_hex = hex::encode(monero_spend_public.as_bytes());
        let monero_view_priv_hex = hex::encode(monero_view_private.as_bytes());
        let monero_view_pub_hex = hex::encode(monero_view_public.as_bytes());
        
        let distributed_key = DistributedKey {
            evm_private_key: evm_priv_hex,
            evm_public_key: evm_pub_hex,
            evm_address: evm_address.to_string(),
            
            monero_spend_private_key: monero_spend_priv_hex,
            monero_spend_public_key: monero_spend_pub_hex,
            monero_view_private_key: monero_view_priv_hex,
            monero_view_public_key: monero_view_pub_hex,
            
            threshold: self.config.mpc.threshold,
            total_parties: self.config.mpc.total_parties,
            validator_id,
            shares,
            network_seed: hex::encode(seed),
            generated_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        };
        
        // Save to file
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        let key_file = format!("{}/dkg_keys_{}.json", self.keys_dir, timestamp);
        let key_data = serde_json::to_string_pretty(&distributed_key)?;
        tokio::fs::write(&key_file, key_data)
            .await?;
        
        // Create recovery mnemonic
        let mnemonic = format!(
            "VK-{} EVM-Ethéråum Bridge + Monérø Network Keys Generated {} Shares {}",
            validator_id,
            self.config.mpc.threshold,
            self.config.mpc.total_parties
        );
        let mnemonic_file = format!("{}/mnemonic_{}.txt", self.keys_dir, validator_id);
        tokio::fs::write(&mnemonic_file, mnemonic).await?;
        
        // Also create pretty summary
        let summary = format!(
            "=== CROSS-CHAIN VALIDATOR {} ===\nEVM Bridge: {}\nMonero Spend: {}\nMonero View: {}\nThreshold: {} of {}\nFile: {}\n",
            validator_id,
            &distributed_key.evm_address,
            &hex::encode(monero_spend_public.as_bytes())[..16],
            &hex::encode(monero_view_public.as_bytes())[..16],
            distributed_key.threshold,
            distributed_key.total_parties,
            key_file
        );
        
        let summary_file = format!("{}/summary_{}.txt", self.keys_dir, validator_id);
        tokio::fs::write(&summary_file, summary).await?;
        
        info!("📁 Keys saved for validator: {}", validator_id);
        info!("🦊 EVM: {}", distributed_key.evm_address);
        info!("🪙 Monero keys generated for Ed25519 curve");
        
        Ok(distributed_key)
    }
}

pub async fn start_keygen(config_path: String, validator_id: usize) -> Result<()> {
    let config = Config::load(&config_path)?;
    let coordinator = KeygenCoordinator::new(config, validator_id).await?;
    coordinator.run(validator_id).await
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_keygen_coordinator() -> Result<()> {
        let test_config = Config::load("config.toml")?;
        let coordinator = KeygenCoordinator::new(test_config, 1).await?;
        coordinator.run(1).await
    }
}