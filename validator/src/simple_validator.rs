// Simplified validator demo that actually runs
use axum::{
    routing::{get, post},
    Router,
    response::Json,
    extract::Path,
};
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ValidatorState {
    id: usize,
    total_validators: usize,
    threshold: usize,
    is_online: bool,
    signature_count: usize,
    last_signature_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SignatureRequest {
    tx_secret: String,
    amount: u64,
    monero_txid: String,
    timestamp: u64,
    nonce: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ThresholdSignature {
    r: String,
    s: String,
    v: u8,
    validator_id: usize,
    timestamp: u64,
}

#[derive(Debug, Clone, Serialize)]
struct DemoSignResponse {
    signature: ThresholdSignature,
    validator_health: Vec<(usize, bool)>,
}

type SharedState = Arc<Mutex<HashMap<usize, ValidatorState>>>;
type SharedSignatures = Arc<Mutex<HashMap<String, Vec<ThresholdSignature>>>>;

async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "healthy",
        "timestamp": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        "service": "wxmr-validator"
    }))
}

async fn validator_health(
    state: axum::extract::State<SharedState>
) -> Json<serde_json::Value> {
    let state_lock = state.lock().unwrap();
    let validators: Vec<_> = state_lock.values().collect();
    
    Json(serde_json::json!({
        "validators": validators,
        "threshold_met": validators.iter().filter(|v| v.is_online).count() >= 4
    }))
}

async fn request_signature(
    Path(validator_id): Path<usize>,
    state: axum::extract::State<SharedState>,
    axum::extract::Json(_request): axum::extract::Json<SignatureRequest>
) -> Json<ThresholdSignature> {
    info!("Processing signature request for validator {}", validator_id);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    
    // Generate mock signature for demo
    let mut rng = rand::thread_rng();
    let r: String = (0..64).map(|_| rng.sample(rand::distributions::Alphanumeric) as char).collect();
    let s: String = (0..64).map(|_| rng.sample(rand::distributions::Alphanumeric) as char).collect();
    
    let signature = ThresholdSignature {
        r,
        s,
        v: rng.gen_range(27..=28),
        validator_id,
        timestamp: ts,
    };
    
    // Update validator state
    let mut state_lock = state.lock().unwrap();
    if let Some(v) = state_lock.get_mut(&validator_id) {
        v.signature_count += 1;
        v.last_signature_at = ts;
    }
    
    Json(signature)
}

async fn check_threshold_status(
    state: axum::extract::State<SharedState>,
) -> Json<serde_json::Value> {
    let state_lock = state.lock().unwrap();
    
    Json(serde_json::json!({
        "message": "This is a demo endpoint",
        "threshold": 4,
        "total_validators": state_lock.len()
    }))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    
    let args: Vec<String> = std::env::args().collect();
    let validator_id = args
        .iter()
        .position(|a| a == "--id")
        .and_then(|i| args.get(i + 1))
        .and_then(|s| s.parse().ok())
        .unwrap_or(1);
    
    let base_port = 8000 + validator_id;
    
    // Initialize demo validators
    let mut validators = HashMap::new();
    for i in 1..=7 {
        validators.insert(i, ValidatorState {
            id: i,
            total_validators: 7,
            threshold: 4,
            is_online: true,
            signature_count: 0,
            last_signature_at: 0,
        });
    }
    
    let state = Arc::new(Mutex::new(validators));
    let _signatures = Arc::new(Mutex::new(HashMap::<String, Vec<ThresholdSignature>>::new()));
    
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/validators", get(validator_health))
        .route("/sign/:validator_id", post(request_signature))
        .route("/threshold-status", get(check_threshold_status))
        .with_state(state.clone());
    
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", base_port))
        .await
        .expect("Failed to bind");
    
    println!("🚀 Validator {} started on port {}", validator_id, base_port);
    println!("📡 Health check: http://localhost:{}/health", base_port);
    println!("📊 Status: http://localhost:{}/validators", base_port);
    println!("✍️  Sign demo: http://localhost:{}/sign/{}?data=test", base_port, validator_id);
    
    axum::serve(listener, app).await.unwrap();
}