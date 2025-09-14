use clap::Parser;
use std::path::PathBuf;

mod config;
mod keygen;
mod signing;
mod validator;
mod validation;
mod network;
mod tss;
mod combiner;

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
    combine_keys: bool,
    
    #[arg(long)]
    show_bridge: bool,
    
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
    } else if args.combine_keys {
        info!("Combining validator TSS keys...");
        combiner::KeyCombiner::combine_validator_keys(&args.config.to_string_lossy().into_owned()).await?;
    } else if args.show_bridge {
        info!("Displaying bridge wallet information...");
        combiner::KeyCombiner::print_bridge_info(&args.config.to_string_lossy().into_owned()).await?;
    } else if args.index.is_some() {
        info!("Starting validator node...");
        validator::start_validator(args.config.to_string_lossy().into_owned(), args.port.unwrap_or(8000), args.index.unwrap()).await?;
    } else {
        error!("Must provide --generate-keys, --combine-keys, --show-bridge, or --index <validator_id>");
    }
    
    Ok(())
}