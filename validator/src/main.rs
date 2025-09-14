use clap::Parser;
use std::path::PathBuf;

mod config;
mod keygen;

use anyhow::Result;
use tracing::{info, error};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(long, env, default_value = "config.toml")]
    config: PathBuf,
    
    #[arg(long)]
    generate_keys: bool,
    
    #[arg(long)]
    index: Option<usize>,
    
    #[arg(long)]
    port: Option<u16>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    
    let args = Args::parse();
    
    if args.generate_keys {
        info!("Starting distributed key generation...");
        keygen::start_keygen(args.config.to_string_lossy().into_owned(), args.index.unwrap_or(0)).await?;
    } else if args.index.is_some() {
        info!("Starting validator node {} on port {}", 
              args.index.unwrap(), args.port.unwrap_or(8000));
        
        // Handle simple validator case
        let _ = args.index.unwrap(); // Just mark as used for now
    } else {
        error!("Must provide --generate-keys or --index <validator_id>");
    }
    
    Ok(())
}