use serde::{Deserialize, Serialize};
use anyhow::Result;
use std::path::Path;
use serde_json;
use tracing::{info, warn};

use crate::tss::{TSSKeyGenerator, TSSKeyShare, JointKeys};
use crate::config::Config;

#[derive(Debug, Serialize, Deserialize)]
pub struct BridgeKeys {
    pub eth_address: String,
    pub eth_public_key_hex: String,
    pub monero_address: String,
    pub monero_public_key_hex: String,
    pub validator_shares: Vec<String>,
    pub threshold: usize,
    pub total_validators: usize,
}

pub struct KeyCombiner;

impl KeyCombiner {
    pub async fn combine_validator_keys(config_path: &str) -> Result<BridgeKeys> {
        let config = Config::load(config_path)?;
        let keys_dir = config.mpc.key_gen_output_path.clone();
        
        info!("Loading validator TSS shares from keys_dir: {} (absolute: {})", keys_dir, std::env::current_dir()?.join(&keys_dir).display());
        
        let mut shares = Vec::new();
        let mut eth_addresses = Vec::new();
        let mut monero_addresses = Vec::new();
        
        for validator_id in 0..config.mpc.total_parties {
            let key_file = format!("{}/keys/keys_{}_{}.json", 
                keys_dir, validator_id, validator_id + 1);
            
            let content = match tokio::fs::read_to_string(&key_file).await {
                Ok(data) => data,
                Err(_) => {
                    warn!("Missing key file for validator {}, using fallback", validator_id);
                    continue;
                }
            };
            
            if let Ok(validator_keys) = serde_json::from_str::<super::keygen::ValidatorKeys>(&content) {
                eth_addresses.push(validator_keys.addresses.eth_address.clone());
                monero_addresses.push(validator_keys.addresses.monero_address.clone());
                shares.push(validator_keys);
            }
        }
        
        if shares.is_empty() {
            return Err(anyhow::anyhow!("No validator keys found"));
        }
        
        // Extract key shares
        let key_shares: Vec<TSSKeyShare> = shares.iter()
            .map(|vk| vk.key_share.clone())
            .collect();
        
        // Validate all validators have same addresses
        Self::validate_consistency(&eth_addresses, &monero_addresses)?;
        
        // Use first validator's addresses as the joint addresses
        let first_keys = &shares[0];
        
        let bridge_keys = BridgeKeys {
            eth_address: first_keys.addresses.eth_address.clone(),
            eth_public_key_hex: first_keys.addresses.eth_public_key.clone(),
            monero_address: first_keys.addresses.monero_address.clone(),
            monero_public_key_hex: first_keys.addresses.monero_public_key.clone(),
            validator_shares: shares.iter().map(|s| format!("validator_{}", s.validator_id)).collect(),
            threshold: config.mpc.threshold,
            total_validators: config.mpc.total_parties,
        };
        
        // Save combined keys
        Self::save_combined_keys(&config, &bridge_keys).await?;
        
        Ok(bridge_keys)
    }
    
    fn validate_consistency(eth_addresses: &[String], monero_addresses: &[String]) -> Result<()> {
        if eth_addresses.is_empty() || monero_addresses.is_empty() {
            return Err(anyhow::anyhow!("No addresses found"));
        }
        
        let eth_consistent = eth_addresses.iter().all(|addr| addr == &eth_addresses[0]);
        let monero_consistent = monero_addresses.iter().all(|addr| addr == &monero_addresses[0]);
        
        if !eth_consistent {
            return Err(anyhow::anyhow!("Ethereum addresses inconsistent across validators"));
        }
        
        if !monero_consistent {
            return Err(anyhow::anyhow!("Monero addresses inconsistent across validators"));
        }
        
        Ok(())
    }
    
    async fn save_combined_keys(config: &Config, bridge_keys: &BridgeKeys) -> Result<()> {
        let combined_keys_file = format!("{}/combined_bridge_keys.json", config.mpc.key_gen_output_path);
        let data = serde_json::to_string_pretty(bridge_keys)?;
        tokio::fs::write(&combined_keys_file, data).await?;
        info!("Saved combined bridge keys to {}", combined_keys_file);
        Ok(())
    }
    
    pub async fn print_bridge_info(config_path: &str) -> Result<()> {
        let bridge_keys = Self::combine_validator_keys(config_path).await?;
        
        println!("
🏦 **BRIDGE JOINT WALLET ADDRESSES**
");
        println!("====================================");
        println!("🔗 **Ethereum Address**: {}", bridge_keys.eth_address);
        println!("🔓 **Ethereum Public Key**: {}", bridge_keys.eth_public_key_hex);
        println!();
        println!("💰 **Monero Address**: {}", bridge_keys.monero_address);
        println!("🔓 **Monero Public Key**: {}", bridge_keys.monero_public_key_hex);
        println!();
        println!("📊 **Security Parameters");
        println!("Threshold: {} signatures needed", bridge_keys.threshold);
        println!("Total Validators: {}", bridge_keys.total_validators);
        println!();
        println!("🔑 **Validator Share Holders");
        for share in &bridge_keys.validator_shares {
            println!("- {}", share);
        }
        
        Ok(())
    }
}