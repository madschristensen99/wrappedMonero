use clap::Parser;
use std::path::PathBuf;

mod config;
mod keygen;
mod signing;
mod validator;
mod validation;

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
        keygen::start_keygen(args.config, args.index.unwrap_or(0)).await?;
    } else if args.index.is_some() {
        info!("Starting validator node...");
        validator::start_validator(args.config, args.port.unwrap_or(8000), args.index.unwrap()).await?;
    } else {
        error!("Must provide --generate-keys or --index <validator_id>");
    }
    
    Ok(())
}