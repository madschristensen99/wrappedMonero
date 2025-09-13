use axum::{
    routing::get,
    routing::post,
    Json,
    Router,
    extract::Path,
    extract::Query
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
async fn init_db(pool: &SqlitePool) {
    sqlx::query!(
        r#"
        CREATE TABLE IF NOT EXISTS burns (
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
        )
        "#)
        .execute(pool)
        .await
        .expect("Failed to create burns table");
        
    sqlx::query!(
        r#"
        CREATE TABLE IF NOT EXISTS key_images (
            key_image TEXT PRIMARY KEY,
            used BOOLEAN DEFAULT FALSE
        )
        "#)
        .execute(pool)
        .await
        .expect("Failed to create key_images table");
}

async fn submit_burn(
    Json(payload): Json<SubmitRequest>,
    axum::Extension(pool): axum::Extension<SqlitePool>,
) -> Json<SubmitResponse> {
    let uuid = Uuid::new_v4().to_string();
    
    // Check if key image already exists
    let existing = sqlx::query!(
        "SELECT key_image FROM key_images WHERE key_image = ? AND used = TRUE",
        payload.key_image
    )
    .fetch_optional(&pool)
    .await;
    
    if let Ok(Some(_)) = existing {
        return Json(SubmitResponse {
            uuid,
            status: "FAILED".to_string(),
        });
    }
    
    // Store burn request
    sqlx::query!(
        "INSERT INTO burns (uuid, tx_hash, l2rs_sig, fhe_ciphertext, amount_commit, key_image, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
        uuid,
        payload.tx_hash,
        payload.l2rs_sig,
        payload.fhe_ciphertext,
        payload.amount_commit,
        payload.key_image,
        "PENDING"
    )
    .execute(&pool)
    .await
    .expect("Failed to insert burn");
    
    // Queue for processing
    tokio::spawn(async move {
        process_burn(uuid, payload).await;
    });
    
    Json(SubmitResponse {
        uuid,
        status: "PENDING".to_string(),
    })
}

async fn process_burn(uuid: String, payload: SubmitRequest) {
    let pool = init_pool().await;
    
    // Update status to PROCESSING
    sqlx::query!(
        "UPDATE burns SET status = 'PROCESSING' WHERE uuid = ?",
        uuid
    )
    .execute(&pool)
    .await
    .expect("Failed to update status");
    
    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
    
    // 1. Verify Monero transaction
    if let Err(_) = monero::verify_transaction(&payload.tx_hash).await {
        sqlx::query!(
            "UPDATE burns SET status = 'FAILED' WHERE uuid = ?",
            uuid
        )
        .execute(&pool)
        .await
        .unwrap();
        return;
    }
    
    // 2. Verify lattice signature
    if !monero::verify_lattice_signature(&payload.l2rs_sig, &payload.key_image) {
        sqlx::query!(
            "UPDATE burns SET status = 'FAILED' WHERE uuid = ?",
            uuid
        )
        .execute(&pool)
        .await
        .unwrap();
        return;
    }
    
    // 3. Evaluate FHE policy
    if !fhe_policy::evaluate(&payload.fhe_ciphertext).await {
        sqlx::query!(
            "UPDATE burns SET status = 'FAILED' WHERE uuid = ?",
            uuid
        )
        .execute(&pool)
        .await
        .unwrap();
        return;
    }
    
    // 4. Generate RISC Zero proof
    let receipt = match prover::generate_receipt(&payload).await {
        Ok(receipt) => receipt,
        Err(_) => {
            sqlx::query!(
                "UPDATE burns SET status = 'FAILED' WHERE uuid = ?",
                uuid
            )
            .execute(&pool)
            .await
            .unwrap();
            return;
        }
    };
    
    // 5. Mint on contract
    let amount = 1000_000_000_000; // Placeholder amount parsing
    match contract::mint_with_proof(&receipt, amount, &payload.key_image, &payload.amount_commit).await {
        Ok(eth_tx_hash) => {
            sqlx::query!(
                "UPDATE burns SET status = 'MINTED', eth_tx_hash = ? WHERE uuid = ?",
                eth_tx_hash,
                uuid
            )
            .execute(&pool)
            .await
            .unwrap();
            
            sqlx::query!(
                "INSERT INTO key_images (key_image, used) VALUES (?, TRUE)",
                payload.key_image
            )
            .execute(&pool)
            .await
            .unwrap();
        }
        Err(_) => {
            sqlx::query!(
                "UPDATE burns SET status = 'FAILED' WHERE uuid = ?",
                uuid
            )
            .execute(&pool)
            .await
            .unwrap();
        }
    }
}

async fn get_status(
    Path(uuid): Path<String>,
    axum::Extension(pool): axum::Extension<SqlitePool>,
) -> Json<StatusResponse> {
    let record = sqlx::query!(
        "SELECT status, eth_tx_hash FROM burns WHERE uuid = ?",
        uuid
    )
    .fetch_optional(&pool)
    .await;
    
    match record {
        Ok(Some(record)) => Json(StatusResponse {
            status: record.status,
            tx_hash_eth: record.eth_tx_hash,
            amount: Some("1000000000000".to_string()), // Placeholder
        }),
        _ => Json(StatusResponse {
            status: "NOT_FOUND".to_string(),
            tx_hash_eth: None,
            amount: None,
        }),
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
    
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/v1/submit", post(submit_burn))
        .route("/v1/status/:uuid", get(get_status))
        .layer(axum::Extension(pool));
    
    let addr = SocketAddr::from(([0, 0, 0, 0], 8080));
    println!("Server running on {}", addr);
    
    axum::Server::bind(&addr)
        .serve(app.into_make_service())
        .await
        .unwrap();
}