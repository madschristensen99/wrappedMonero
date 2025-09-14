use axum::{
    routing::get,
    routing::post,
    Json,
    Router,
    extract::Path,
    extract::Extension
};
use serde::{Deserialize, Serialize};
use sqlx::sqlite::{SqlitePool, SqlitePoolOptions};
use std::env;
use std::net::SocketAddr;
use uuid::Uuid;

mod monero;
mod fhe_policy;
mod prover;
mod contract;

#[derive(Debug, Deserialize, Serialize)]
struct SubmitRequest {
    tx_hash: String,
    l2rs_sig: String,
    fhe_ciphertext: String,
    amount_commit: String,
    key_image: String,
}

#[derive(Debug, Serialize)]
struct SubmitResponse {
    uuid: String,
    status: String,
}

#[derive(Debug, Serialize)]
struct StatusResponse {
    status: String,
    tx_hash_eth: Option<String>,
    amount: Option<String>,
}

#[derive(Debug, Serialize)]
enum BurnStatus {
    Pending,
    Processing,
    Minted,
    Failed,
}

// Initialize database pool
async fn init_pool() -> SqlitePool {
    let db_path = env::var("DATABASE_URL").unwrap_or_else(|_| "sqlite:///tmp/risc0_xmr.db".to_string());
    SqlitePoolOptions::new()
        .max_connections(5)
        .connect(&db_path)
        .await
        .expect("Failed to create database pool")
}

// Initialize database with required tables
async fn init_db(_pool: &SqlitePool) {
    // Create database schema without query! macro for compilation
    let _ = std::process::Command::new("sqlite3")
        .arg(env::var("DATABASE_URL").unwrap_or_else(|_| "relay.db".to_string()))
        .args(&[
            "-cmd",
            "CREATE TABLE IF NOT EXISTS burns (
                uuid TEXT PRIMARY KEY,
                tx_hash TEXT NOT NULL,
                l2rs_sig TEXT NOT NULL,
                fhe_ciphertext TEXT NOT NULL,
                amount_commit TEXT NOT NULL,
                key_image TEXT NOT NULL UNIQUE,
                status TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                eth_tx_hash TEXT
            );"
        ])
        .output()
        .expect("Failed to initialize database");
        
    let _ = std::process::Command::new("sqlite3")
        .arg(env::var("DATABASE_URL").unwrap_or_else(|_| "relay.db".to_string()))
        .args(&[
            "-cmd",
            "CREATE TABLE IF NOT EXISTS key_images (
                key_image TEXT PRIMARY KEY,
                used BOOLEAN DEFAULT FALSE
            );"
        ])
        .output()
        .expect("Failed to initialize database");
}

async fn submit_burn(
    Json(payload): Json<SubmitRequest>,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<SubmitResponse>, axum::http::StatusCode> {
    let uuid = Uuid::new_v4().to_string();
    
    // Check if key image already exists
    let existing = sqlx::query_as::<_, (String, i32)>(
        "SELECT key_image, used FROM key_images WHERE key_image = ? AND used = ?"
    )
    .bind(&payload.key_image)
    .bind(true)
    .fetch_optional(&pool)
    .await
    .map_err(|_| axum::http::StatusCode::INTERNAL_SERVER_ERROR)?;
    
    if existing.is_some() {
        return Ok(Json(SubmitResponse {
            uuid,
            status: "FAILED".to_string(),
        }));
    }
    
    // Store burn request
    sqlx::query(
        "INSERT INTO burns (uuid, tx_hash, l2rs_sig, fhe_ciphertext, amount_commit, key_image, status) VALUES (?, ?, ?, ?, ?, ?, ?)"
    )
    .bind(&uuid)
    .bind(&payload.tx_hash)
    .bind(&payload.l2rs_sig)
    .bind(&payload.fhe_ciphertext)
    .bind(&payload.amount_commit)
    .bind(&payload.key_image)
    .bind("PENDING")
    .execute(&pool)
    .await
    .map_err(|_| axum::http::StatusCode::INTERNAL_SERVER_ERROR)?;
    
    // Queue for processing
    let uuid_clone = uuid.clone();
    tokio::spawn(async move {
        process_burn(uuid_clone, payload).await;
    });
    
    Ok(Json(SubmitResponse {
        uuid,
        status: "PENDING".to_string(),
    }))
}

async fn process_burn(uuid: String, payload: SubmitRequest) {
    let pool = init_pool().await;
    
    // Update status to PROCESSING
    sqlx::query(
        "UPDATE burns SET status = 'PROCESSING' WHERE uuid = ?"
    )
    .bind(&uuid)
    .execute(&pool)
    .await
    .expect("Failed to update status");
    
    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
    
    // 1. Verify Monero transaction (mock for hackathon)
    let tx_valid = monero::verify_transaction(&payload.tx_hash).await.unwrap_or(false);
    if !tx_valid {
        let _ = sqlx::query("UPDATE burns SET status = 'FAILED' WHERE uuid = ?")
            .bind(&uuid)
            .execute(&pool)
            .await;
        return;
    }
    
    // 2. Verify lattice signature (mock for hackathon)
    let sig_valid = monero::verify_lattice_signature(&payload.l2rs_sig, &payload.key_image);
    if !sig_valid {
        let _ = sqlx::query("UPDATE burns SET status = 'FAILED' WHERE uuid = ?")
            .bind(&uuid)
            .execute(&pool)
            .await;
        return;
    }
    
    // 3. Evaluate FHE policy (mock for hackathon)
    let policy_valid = fhe_policy::evaluate(&payload.fhe_ciphertext).await;
    if !policy_valid {
        let _ = sqlx::query("UPDATE burns SET status = 'FAILED' WHERE uuid = ?")
            .bind(&uuid)
            .execute(&pool)
            .await;
        return;
    }
    
    // 4. Generate real RISC Zero proof
    let receipt = match crate::prover::generate_receipt(&payload).await {
        Ok(receipt) => receipt,
        Err(e) => {
            println!("❌ Failed to generate proof: {}", e);
            let _ = sqlx::query("UPDATE burns SET status = 'FAILED' WHERE uuid = ?")
                .bind(&uuid)
                .execute(&pool)
                .await;
            return;
        }
    };
    
    // 5. Extract amount for minting
    let amount = 1_000_000_000_000u64; // Default 1 XMR, decode from FHE in production
    
    // 6. Submit proof to contract for minting
    let eth_tx_hash = match crate::contract::mint_with_proof(&receipt, amount, &payload.key_image, &payload.amount_commit).await {
        Ok(tx_hash) => tx_hash,
        Err(e) => {
            println!("❌ Failed to mint on contract: {}", e);
            let _ = sqlx::query("UPDATE burns SET status = 'FAILED' WHERE uuid = ?")
                .bind(&uuid)
                .execute(&pool)
                .await;
            return;
        }
    };
    
    let _ = sqlx::query("INSERT INTO key_images (key_image, used) VALUES (?, TRUE)")
        .bind(&payload.key_image)
        .execute(&pool)
        .await;
}

async fn get_status(
    Path(uuid): Path<String>,
    Extension(pool): Extension<SqlitePool>,
) -> Result<Json<StatusResponse>, axum::http::StatusCode> {
    let record = sqlx::query_as::<_, (String, Option<String>)>(
        "SELECT status, eth_tx_hash FROM burns WHERE uuid = ?"
    )
    .bind(&uuid)
    .fetch_optional(&pool)
    .await;
    
    match record {
        Ok(Some((status, eth_tx_hash))) => Ok(Json(StatusResponse {
            status,
            tx_hash_eth: eth_tx_hash,
            amount: Some("1000000000000".to_string()), // Placeholder
        })),
        _ => Ok(Json(StatusResponse {
            status: "NOT_FOUND".to_string(),
            tx_hash_eth: None,
            amount: None,
        })),
    }
}

async fn health_check() -> &'static str {
    "OK"
}

#[tokio::main]
async fn main() {
    dotenv::dotenv().ok();
    
    let pool = init_pool().await;
    init_db(&pool).await;
    
    // Build app with proper state
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/v1/submit", post(submit_burn))
        .route("/v1/status/:uuid", get(get_status))
        .layer(Extension(pool));
    
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("Relay service running on http://localhost:8080");
    println!("Endpoints:");
    println!("  GET  /health - Health check");
    println!("  POST /v1/submit - Submit burn");
    println!("  GET  /v1/status/{{uuid}} - Check status");
    
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}