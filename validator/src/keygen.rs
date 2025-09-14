use std::sync::Arc;
use tracing::{info};
use anyhow::{Result};
use serde::{Deserialize, Serialize};

use crate::config::Config;
use crate::network::{NetworkClient, PartySignupRequest, PartySignupResponse};
use crate::tss::{TSSKeyGenerator, TSSKeyShare, JointKeys};

pub struct KeygenCoordinator {
    config: Config,
    network_client: Arc<NetworkClient>,
    keys_dir: String,
}

impl KeygenCoordinator {
    pub async fn new(config: Config, validator_id: usize) -> Result<Self> {
        let network_client = Arc::new(NetworkClient::new(config.network.clone()));
        let keys_dir = format!("{}/{}" , config.mpc.key_gen_output_path, validator_id);
        
        tokio::fs::create_dir_all(&keys_dir).await?;
        
        Ok(Self {
            config,
            network_client,
            keys_dir,
        })
    }
    
    pub async fn run(&self, validator_id: usize) -> Result<()> {
        info!("Starting DKG for validator {}", validator_id);
        
        let signup_response = self.signup_participant(validator_id).await?;
        let party_id = signup_response.number;
        
        info!("Participating as party {} in DKG", party_id);
        
        // Create TSS key generator
        let generator = TSSKeyGenerator::new(
            self.config.mpc.threshold,
            self.config.mpc.total_parties,
        );
        
        // Generate keys
        let (key_share, joint_keys) = generator.generate_keys(validator_id)?;
        
        // Create comprehensive key structure
        let validator_keys = ValidatorKeys {
            validator_id,
            party_id,
            key_share: key_share.clone(),
            joint_keys: joint_keys.clone(),
            config_snapshot: self.config.clone(),
            addresses: Self::extract_addresses(&joint_keys),
        };
        
        // Save keys to file
        self.save_keys(&validator_keys, validator_id, party_id).await?;
        
        info!("Successfully completed DKG for validator {}:", validator_id);
        info!("  Joint Ethereum Address: {}", validator_keys.addresses.eth_address);
        info!("  Joint Monero Address: {}", validator_keys.addresses.monero_address);
        
        Ok(())
    }
    
    async fn signup_participant(&self, validator_id: usize) -> Result<PartySignupResponse> {
        let request = PartySignupRequest {
            validator_id,
            intent: "keygen".to_string(),
        };
        
        self.network_client.signup(request).await
    }
    
    async fn save_keys(&self, keys: &ValidatorKeys, validator_id: usize, party_id: usize) -> Result<()> {
        let key_file = format!("{}/keys_{}_{}.json", self.keys_dir, validator_id, party_id);
        let key_data = serde_json::to_string_pretty(keys)?;
        tokio::fs::write(&key_file, key_data).await?;
        
        info!("Saved TSS keys for validator {} to {}", validator_id, key_file);
        Ok(())
    }

    fn extract_addresses(joint_keys: &JointKeys) -> DerivedAddresses {
        DerivedAddresses {
            eth_address: joint_keys.eth_address.clone(),
            eth_public_key: hex::encode(&joint_keys.eth_public_key),
            monero_address: joint_keys.monero_address.clone(),
            monero_public_key: hex::encode(&joint_keys.monero_public_key),
        }
    }
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct ValidatorKeys {
    pub validator_id: usize,
    pub party_id: usize,
    pub key_share: TSSKeyShare,
    pub joint_keys: JointKeys,
    pub config_snapshot: Config,
    pub addresses: DerivedAddresses,
}

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct DerivedAddresses {
    pub eth_address: String,
    pub eth_public_key: String,
    pub monero_address: String,
    pub monero_public_key: String,
}

pub async fn start_keygen(config_path: String, validator_id: usize) -> Result<()> {
    let config = Config::load(&config_path)?;
    let coordinator = KeygenCoordinator::new(config, validator_id).await?;
    coordinator.run(validator_id).await
}