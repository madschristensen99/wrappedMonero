#!/bin/bash

# Production Monero Bridge Deployment Script
echo "🚀 Starting Production Monero Bridge Deployment..."

# Kill any existing processes
pkill -f "cargo run" || true
pkill -f "node" || true

# Environment setup
echo "🛠️ Setting up environment..."
export ETHEREUM_RPC_URL="https://rpc.sepolia.org"
export PRIVATE_KEY="your_private_key_here"  # Set securely
export RELAY_API_URL="http://localhost:8080"

# Build RISC Zero guest
pushd guest
echo "🔨 Building RISC Zero guest program..."
cargo build --release --target riscv32im-risc0-zkvm-elf
popd

# Install dependencies
echo "📦 Installing dependencies..."
pushd contract
npm install axios --save
popd

# Deploy contract
echo "🚀 Deploying wxMR contract..."
pushd contract
npx hardhat run scripts/deploy.js --network sepolia
popd

# Build relay service
echo "⚙️ Building RISC Zero relay service..."
pushd relay
cargo build --release
popd

# Start services
echo "🌟 Starting services in development mode..."

# Terminal 1: Start RISC Zero relay service
gnome-terminal --working-directory=/home/remsee/wrappedMonero/relay --title="RISC Zero Relay" -- bash -c "cargo run --release"

# Terminal 2: Contract testing
gnome-terminal --working-directory=/home/remsee/wrappedMonero/contract --title="Contract Mint" -- bash -c "npx hardhat run mint_operation.js --network sepolia"

echo "✅ Production deployment complete!"
echo ""
echo "Services started:"
echo "  • RISC Zero relay: http://localhost:8080"
echo "  • Contract address: 0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5"
echo ""
echo "Next steps:"
echo "  1. Send Monero burn to stagenet address"
echo "  2. Use relay service to get RISC Zero proof"
echo "  3. Execute mint via Ethreum wallet"
echo ""