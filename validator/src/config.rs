use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use url::Url;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Config {
    pub network: NetworkConfig,
    pub mpc: MPCConfig,
    pub monero: MoneroConfig,
    pub ethereum: EthereumConfig,
    pub validators: ValidatorConfig,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct NetworkConfig {
    pub bind_address: SocketAddr,
    pub peers: Vec<PeerConfig>,
    pub timeout_ms: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PeerConfig {
    pub id: usize,
    pub address: SocketAddr,
    pub url: Url,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct MPCConfig {
    pub threshold: usize,
    pub total_parties: usize,
    pub keygen_timeout_secs: u64,
    pub signing_timeout_secs: u64,
    pub key_gen_output_path: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct MoneroConfig {
    pub rpc_url: String,
    pub address: String,
    pub required_confirmations: u64,
    pub check_interval_secs: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct EthereumConfig {
    pub rpc_url: String,
    pub contract_address: String,
    pub private_key: Option<String>, // For validators
    pub gas_limit: u64,
    pub max_gas_price: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ValidatorConfig {
    pub validator_id: usize,
    pub threshold: usize,
    pub enable_consensus: bool,
    pub reshare_period_days: u32,
}

impl Config {
    pub fn load(path: &str) -> anyhow::Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }
}