use anyhow::Result;
use tracing::{info, error};
use std::sync::Arc;
use serde_json;
use hex;
use sha2::{Sha256, Digest};

use crate::config::Config;
use crate::validation::MoneroValidator;
use crate::signing::SigningCoordinator;
use crate::network::{NetworkClient, ConsensusMessage};
use crate::{validation::MoneroTransaction, signing::{SigningRequest, SigningResult}};

pub struct ValidatorNode {
    config: Config,
    validator_id: usize,
    monero_validator: MoneroValidator,
    signing_coordinator: Option<SigningCoordinator>,
    network_client: Arc<NetworkClient>,
    shutdown: tokio::sync::Notify,
}

impl ValidatorNode {
    pub fn new(
        config: Config,
        validator_id: usize,
        monero_validator: MoneroValidator,
        network_client: Arc<NetworkClient>,
    ) -> Self {
        Self {
            config,
            validator_id,
            monero_validator,
            signing_coordinator: None,
            network_client,
            shutdown: tokio::sync::Notify::new(),
        }
    }
    
    pub async fn run(config_path: String, port: u16, validator_id: usize) -> Result<()> {
        info!("Starting validator {} on port {}", validator_id, port);
        
        // Load configuration
        let config = Config::load(&config_path)?;
        
        // Initialize Monero validator
        let monero_validator = MoneroValidator::new(config.monero.clone());
        
        // Set up networking
        let network_client = Arc::new(NetworkClient::new(config.network.clone()));
        
        // Create validator node
        let validator = Self::new(
            config.clone(),
            validator_id,
            monero_validator,
            network_client.clone(),
        );
        
        // Start services
        let mut handles = vec![];
        
        // Start network server
        let network_client_clone = network_client.clone();
        let network_handle = tokio::spawn(async move {
            network_client_clone.start_server().await
        });
        handles.push(network_handle);
        
        // Start Monero monitoring
        let mut validator_clone = validator.clone_wrapped();
        let monero_handle = tokio::spawn(async move {
            validator_clone.run_monero_monitoring().await
        });
        handles.push(monero_handle);
        
        // Start heartbeat
        let mut heartbeat_validator = validator.clone_wrapped();
        let heartbeat_handle = tokio::spawn(async move {
            heartbeat_validator.run_heartbeat().await
        });
        handles.push(heartbeat_handle);
        
        // Wait for shutdown signal
        tokio::select! {
            _ = validator.shutdown.notified() => {
                info!("Shutting down validator {} gracefully", validator_id);
            }
            _ = tokio::signal::ctrl_c() => {
                info!("Received Ctrl+C, shutting down validator {}", validator_id);
                validator.shutdown.notify_one();
            }
        }
        
        // Wait for all services to stop
        for handle in handles {
            let _ = handle.await;
        }
        
        Ok(())
    }
    
    async fn run_monero_monitoring(&mut self) -> Result<()> {
        info!("Starting Monero transaction monitoring for validator {}", self.validator_id);
        
        loop {
            tokio::select! {
                _ = tokio::time::sleep(tokio::time::Duration::from_secs(self.config.monero.check_interval_secs)) => {
                    self.process_pending_transactions().await?;
                }
                _ = self.shutdown.notified() => {
                    break;
                }
            }
        }
        
        Ok(())
    }
    
    async fn process_pending_transactions(&mut self) -> Result<Vec<MoneroTransaction>> {
        let pending_tickets = self.fetch_pending_mint_requests().await?;
        
        let mut validated_transactions = vec![];
        
        for request in pending_tickets {
            if let Some(tx) = self.monero_validator
                .validate_mint_request(
                    &request.txid,
                    &request.tx_key,  
                    &request.destination,
                    request.amount,
                )
                .await?
            {
                validated_transactions.push(tx.clone());
                
                let signing_request = SigningRequest {
                    tx_secret: hex::decode(&request.tx_key)?,
                    amount: request.amount,
                    operation_hash: self.calculate_operation_hash(&request)?,
                    timestamp: tx.timestamp,
                    nonce: self.generate_nonce(&request)?,
                    monero_tx: tx,
                };
                
                self.initiate_threshold_signing(signing_request).await?;
            }
        }
        
        Ok(validated_transactions)
    }
    
    async fn fetch_pending_mint_requests(&self) -> Result<Vec<MintRequest>> {
        Ok(vec![])
    }
    
    fn calculate_operation_hash(&self, request: &MintRequest) -> Result<[u8; 32]> {
        let mut hasher = Sha256::new();
        hasher.update(request.txid.as_bytes());
        hasher.update(&request.amount.to_be_bytes());
        let result = hasher.finalize();
        Ok(result.into())
    }
    
    fn generate_nonce(&self, request: &MintRequest) -> Result<[u8; 32]> {
        let mut hasher = Sha256::new();
        hasher.update(request.txid.as_bytes());
        hasher.update(self.validator_id.to_be_bytes());
        let result = hasher.finalize();
        Ok(result.into())
    }
    
    pub async fn initiate_threshold_signing(&mut self, request: SigningRequest) -> Result<()> {
        info!("Initiating threshold signing for Tx: {}", hex::encode(&request.operation_hash));
        
        if let Some(ref coordinator) = self.signing_coordinator {
            let result = coordinator.sign_operation(request).await?;
            self.submit_signature(result).await?;
        }
        
        Ok(())
    }
    
    pub async fn submit_signature(&self, signature: SigningResult) -> Result<()> {
        info!("Submitting threshold signature to Ethereum for validator {}", self.validator_id);
        Ok(())
    }
    
    async fn run_heartbeat(&mut self) -> Result<()> {
        loop {
            tokio::select! {
                _ = tokio::time::sleep(tokio::time::Duration::from_secs(30)) => {
                    self.send_heartbeat_message().await?;
                }
                _ = self.shutdown.notified() => break,
            }
        }
        
        Ok(())
    }
    
    async fn send_heartbeat_message(&self) -> Result<()> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
            
        let message = ConsensusMessage {
            validator_id: self.validator_id,
            msg_type: "HEARTBEAT".to_string(),
            data: serde_json::json!({
                "status": "active",
                "address": self.config.ethereum.rpc_url
            }),
            signature: vec![],
            timestamp,
        };
        
        self.network_client.broadcast(message).await?;
        Ok(())
    }
    
    // Helper methods for cloning parameters
    pub fn clone_wrapped(&self) -> Self {
        Self::new(
            self.config.clone(),
            self.validator_id,
            MoneroValidator::new(self.config.monero.clone()),
            Arc::new(NetworkClient::new(self.config.network.clone())),
        )
    }
}

#[derive(Debug, Clone)]
struct MintRequest {
    txid: String,
    tx_key: String,
    amount: u64,
    destination: String,
    block_number: u64,
}

pub async fn start_validator(config_path: String, port: u16, validator_id: usize) -> Result<()> {
    ValidatorNode::run(config_path, port, validator_id).await
}