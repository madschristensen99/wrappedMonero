use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
tracing::{debug, error, info};
use anyhow::Result;

use axum::{
    extract::{State, Query, Json},
    response::Response,
    routing::{get, post},
    Router,
};

#[derive(Debug, Serialize, Deserialize)]
pub struct PartySignupRequest {
    pub validator_id: usize,
    pub intent: String, // "keygen" or "signing"
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PartySignupResponse {
    pub number: usize,
    pub ready: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ConsensusMessage {
    pub validator_id: usize,
    pub msg_type: String,
    pub data: serde_json::Value,
    pub signature: Vec<u8>,
    pub timestamp: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SignatureRequest {
    pub tx_hash: String,
    pub amount: u64,
    pub tx_key: String,
    pub target_address: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SignatureResponse {
    pub r: [u8; 32],
    pub s: [u8; 32],
    pub v: u8,
    pub validator_id: usize,
}

#[derive(Clone)]
pub struct NetworkState {
    pub peers: Arc<RwLock<HashMap<usize, String>>>,
    pub messages: Arc<RwLock<Vec<ConsensusMessage>>>,
    pub validator_id: usize,
    pub port: u16,
}

impl NetworkState {
    pub fn new(validator_id: usize, port: u16) -> Self {
        Self {
            peers: Arc::new(RwLock::new(HashMap::new())),
            messages: Arc::new(RwLock::new(Vec::new())),
            validator_id,
            port,
        }
    }
    
    pub async fn add_peer(&self, id: usize, address: String) {
        let mut peers = self.peers.write().await;
        peers.insert(id, address);
    }
    
    pub async fn broadcast_message(&self, msg: ConsensusMessage) -> Result<()> {
        let peers = self.peers.read().await;
        
        let mut handles = vec![];
        for (_, peer_url) in peers.iter() {
            let msg_clone = msg.clone();
            let peer_url = peer_url.clone();
            
            handles.push(tokio::spawn(async move {
                if let Err(e) = send_message_to_peer(&peer_url, &msg_clone).await {
                    error!("Failed to send to peer {}: {}", peer_url, e);
                }
            }));
        }
        
        futures::future::join_all(handles).await;
        
        Ok(())
    }
}

async fn send_message_to_peer(peer_url: &str, msg: &ConsensusMessage) -> Result<()> {
    let client = reqwest::Client::new();
    let url = format!("{}/message", peer_url);
    
    client
        .post(&url)
        .json(msg)
        .send()
        .await?
        .error_for_status()?;
    
    Ok(())
}

#[derive(Clone)]
pub struct NetworkClient {
    state: NetworkState,
    storage: Arc<String>,
}

impl NetworkClient {
    pub fn new(network_config: crate::config::NetworkConfig) -> Self {
        let state = NetworkState::new(
            // Validator ID will be set later
            0, // placeholder
            network_config.bind_address.port(),
        );
        
        Self::with_state(state)
    }
    
    pub fn with_state(state: NetworkState) -> Self {
        Self {
            state,
            storage: Arc::new("validator_keys".to_string()),
        }
    }
    
    pub async fn signup(&self, request: PartySignupRequest) -> Result<PartySignupResponse> {
        // Assign party number based on validator ID mapping
        let response = PartySignupResponse {
            number: request.validator_id + 1, // 1-based indexing
            ready: true,
        };
        
        info!("Assigned party number {} to validator {}", response.number, request.validator_id);
        Ok(response)
    }
    
    pub async fn start_server(&self) -> Result<()> {
        let state = self.state.clone();
        
        let app = Router::new()
            .route("/health", get(handler_health))
            .route("/party", post(handler_party_signup))
            .route("/sign", post(handler_signature_request))
            .route("/message", post(handler_message))
            .with_state(state);
        
        let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", self.state.port))
            .await
            .context("Failed to bind server")?;
            
        info!("Starting validator server on port {}", self.state.port);
        axum::serve(listener, app).await.context("Server error")?;
        
        Ok(())
    }
    
    pub async fn broadcast(&self, message: ConsensusMessage) -> Result<()> {
        self.state.broadcast_message(message).await
    }
    
    pub async fn wait_for_quorum(&self, msg_type: &str, required_quorum: usize) -> Result<Vec<ConsensusMessage>> {
        let messages = self.state.messages.read().await;
        let relevant_messages: Vec<_> = messages
            .iter()
            .filter(|m| m.msg_type == msg_type)
            .cloned()
            .collect();
            
        if relevant_messages.len() >= required_quorum {
            Ok(relevant_messages)
        } else {
            Err(anyhow::anyhow!(
                "Insufficient messages. Need {}, have {}", 
                required_quorum, 
                relevant_messages.len()
            ))
        }
    }
}

async fn handler_health(State(state): State<NetworkState>) -> Response {
    axum::response::Json(serde_json::json!({
        "status": "healthy",
        "validator_id": state.validator_id,
        "port": state.port,
    }))
}

async fn handler_party_signup(
    State(state): State<NetworkState>,
    Json(request): Json<PartySignupRequest>,
) -> Result<axum::Json<PartySignupResponse>> {
    // Validate validator is authorized
    // TODO: Add validator registry check
    
    let response = PartySignupResponse {
        number: request.validator_id + 1, // Simple mapping
        ready: true,
    };
    
    Ok(axum::Json(response))
}

async fn handler_signature_request(
    State(state): State<NetworkState>,
    Json(request): Json<SignatureRequest>,
) -> Result<axum::Json<SignatureResponse>> {
    // Validate and process signature request
    // This would integrate with the signing coordinator
    
    let response = SignatureResponse {
        r: [0u8; 32], // Placeholder
        s: [0u8; 32], // Placeholder
        v: 27,        // Placeholder
        validator_id: state.validator_id,
    };
    
    Ok(axum::Json(response))
}

async fn handler_message(
    State(state): State<NetworkState>,
    Json(message): Json<ConsensusMessage>,
) -> Result<axum::Json<serde_json::Value>> {
    let mut messages = state.messages.write().await;
    messages.push(message);
    
    debug!("Received message from validator {}", message.validator_id);
    
    Ok(axum::Json(serde_json::json!({"status": "received"})))
}