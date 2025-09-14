use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};
use anyhow::{Result, Context};

use gg20_multi_party_ecdsa::{
    keygen,
    network::{NetworkHandler, NetworkMessage},
    serde::{KeyGenBroadcastMessage1, Keys, Entry, PartySignup{
    protocols::multi_party_ecdsa::gg_2020::party_i::*,
};

use crate::config::Config;
use crate::network::{NetworkClient, PartySignupRequest, PartySignupResponse};

pub struct KeygenCoordinator {
    config: Config,
    network_client: Arc<NetworkClient>,
    keys_dir: String,
}

impl KeygenCoordinator {
    pub async fn new(config: Config, validator_id: usize) -> Result<Self> {
        let network_client = Arc::new(NetworkClient::new(config.network.clone()));
        let keys_dir = format!("{}/{}", config.mpc.key_gen_output_path, validator_id);
        
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
        
        // Run keygen protocol
        let params = keygen::Parameters {
            threshold: self.config.mpc.threshold,
            parties: self.config.mpc.total_parties,
            share_count: self.config.mpc.total_parties,
        };
        
        let party_keys = self.run_keygen_protocol(params, party_id).await?;
        
        // Save keys to file
        self.save_keys(&party_keys, validator_id, party_id).await?;
        
        info!("Successfully completed DKG for validator {}", validator_id);
        Ok(())
    }
    
    async fn signup_participant(&self, validator_id: usize) -> Result<PartySignupResponse> {
        let request = PartySignupRequest {
            validator_id,
            intent: "keygen".to_string(),
        };
        
        self.network_client.signup(request).await
    }
    
    async fn run_keygen_protocol(&self, params: keygen::Parameters, party_id: usize) 
        -> Result<Keys>
    {
        let mut party_keypair = KeyPair::create(party_id)?;
        
        // Run Phase 1: Round 1 - Key generation (create v, w)
        let (bc1, decom1) = (
            party_keypair.phase1_broadcast_phase1()?, 
            party_keypair.phase1_broadcast_phase2()?
        );
        
        // Broadcast Phase 1
        self.network_client.broadcast(
            NetworkMessage::BroadcastMessage1 {
                msg: bc1.clone(),
                sender: party_id,
            }
        ).await?;
        
        // Wait for broadcasts from other parties
        let bc1_vec = self.network_client.wait_for_broadcasts(
            NetworkMessage::BroadcastMessage1 { .. },
            params.parties - 1
        ).await?;
        
        let mut bc1_messages = vec![bc1];
        for msg in bc1_vec {
            bc1_messages.push(msg);
        }
        
        // Run Phase 2: Commitments and shares
        let result = party_keypair.phase_2(&bc1_messages)?;
        
        Ok(result)
    }
    
    async fn save_keys(&self, keys: &Keys, validator_id: usize, party_id: usize) -> Result<()> {
        let key_file = format!("{}/key_{}_{}.json", self.keys_dir, validator_id, party_id);
        let key_data = serde_json::to_string_pretty(keys)?;
        tokio::fs::write(&key_file, key_data).await?;
        
        info!("Saved keys for validator {} to {}", validator_id, key_file);
        Ok(())
    }
}

pub async fn start_keygen(config_path: String, validator_id: usize) -> Result<()> {
    let config = Config::load(&config_path)?;
    let coordinator = KeygenCoordinator::new(config, validator_id).await?;
    coordinator.run(validator_id).await
}