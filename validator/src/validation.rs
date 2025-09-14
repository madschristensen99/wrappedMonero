use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};
use anyhow::{Result, Context};
use tracing::{info, debug, error};
use reqwest::Client;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MoneroTransaction {
    pub txid: String,
    pub tx_key: String,
    pub amount: u64,
    pub expected_amount: u64,
    pub destination_address: String,
    pub confirmations: u64,
    pub in_pool: bool,
    pub timestamp: u64,
    pub receiver_address: String,
}

impl MoneroTransaction {
    pub fn mock() -> Self {
        Self {
            txid: "mock_txid".to_string(),
            tx_key: "mock_key".to_string(),
            amount: 100000000,
            expected_amount: 100000000,
            destination_address: "mock_addr".to_string(),
            confirmations: 10,
            in_pool: false,
            timestamp: 1234567890,
            receiver_address: "mock_addr".to_string(),
        }
    }
}

pub struct MoneroValidator {
    client: Client,
    config: crate::config::MoneroConfig,
}

impl MoneroValidator {
    pub fn new(config: crate::config::MoneroConfig) -> Self {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .expect("Failed to build HTTP client");
            
        Self { client, config }
    }
    
    pub async fn check_transaction(
        &self,
        txid: &str,
        tx_key: &str,
        destination_address: &str,
    ) -> Result<Option<MoneroTransaction>> {
        let request = serde_json::json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "check_tx_key",
            "params": {
                "txid": txid,
                "tx_key": tx_key,
                "address": destination_address,
            }
        });
        
        let response = self.client
            .post(&self.config.rpc_url)
            .json(&request)
            .send()
            .await
            .context("Failed to send Monero RPC request")?;
            
        let response_data: serde_json::Value = response
            .json()
            .await
            .context("Failed to parse Monero RPC response")?;
            
        if let Some(error) = response_data.get("error") {
            error!("Monero RPC error: {}", error);
            return Ok(None);
        }
        
        let result = &response_data["result"];
        
        let confirmations = result["confirmations"]
            .as_u64()
            .unwrap_or(0);
            
        let in_pool = result["in_pool"]
            .as_bool()
            .unwrap_or(false);
            
        let received = result["received"]
            .as_u64()
            .unwrap_or(0);
            
        // Calculate epoch timestamp from current system time
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
            
        let tx = MoneroTransaction {
            txid: txid.to_string(),
            tx_key: tx_key.to_string(),
            amount: received,
            expected_amount: received, // This should be provided separately
            destination_address: destination_address.to_string(),
            confirmations,
            in_pool,
            timestamp,
            receiver_address: destination_address.to_string(),
        };
        
        debug!("Monero transaction: {:#?}", tx);
        
        Ok(Some(tx))
    }
    
    pub async fn validate_mint_request(
        &self,
        txid: &str,
        tx_key: &str,
        destination_address: &str,
        expected_amount: u64,
    ) -> Result<Option<MoneroTransaction>> {
        let mut tx = match self.check_transaction(txid, tx_key, destination_address).await? {
            Some(tx) => tx,
            None => return Ok(None),
        };
        
        tx.expected_amount = expected_amount;
        
        // Validate according to bridge rules
        let is_valid = 
            // Has enough confirmations
            tx.confirmations >= self.config.required_confirmations &&
            // Not in mempool
            !tx.in_pool &&
            // Amount matches what was requested
            tx.amount == expected_amount &&
            // Destination matches our monitored address
            tx.destination_address == self.config.address;
            
        if is_valid {
            info!("Valid Monero transaction found: {} with {} XMR", tx.txid, tx.amount as f64 / 1e12);
            Ok(Some(tx))
        } else {
            debug!("Invalid Monero transaction: {:#?}", tx);
            Ok(None)
        }
    }
    
    pub async fn wait_for_confirmations(
        &self,
        txid: &str,
        tx_key: &str,
        destination_address: &str,
        expected_amount: u64,
    ) -> Result<MoneroTransaction> {
        loop {
            match self.validate_mint_request(txid, tx_key, destination_address, expected_amount).await? {
                Some(tx) if tx.confirmations >= self.config.required_confirmations => return Ok(tx),
                _ => {
                    info!("Waiting for Monero confirmations...");
                    tokio::time::sleep(std::time::Duration::from_secs(self.config.check_interval_secs)).await;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_monero_validator() {
        let config = crate::config::MoneroConfig {
            rpc_url: "http://localhost:38081/json_rpc".to_string(),
            address: "9wuZdcgYHVnNz68iXnjhf1xXr4CN6Q9C5wgd98TiBYMXq5oUqRcwEyVK5GHH6mhMM8xj4qibLzB9QNyVvGzE5cQS6QLh9vW".to_string(),
            required_confirmations: 6,
            check_interval_secs: 1,
        };
        
        // Note: This would require a live Monero node for proper testing
        let validator = MoneroValidator::new(config.clone());
        assert_eq!(validator.config.address, config.address);
    }
}