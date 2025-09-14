#!/bin/bash
# Complete mint/burn flow test script

set -e

echo "🚀 COMPLETE MINT/BURN AUTOMATION"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[$(date '+%T')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%T')] WARNING: $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%T')] ERROR: $1${NC}"
}

# 1. Build RISC Zero components
print_status "Building RISC Zero guest..."
cd /home/remsee/wrappedMonero/guest
cargo build --release

# 2. Build relay service
print_status "Building relay service..."
cd /home/remsee/wrappedMonero/relay
cargo build --release

# 3. Build FHE engine
print_status "Building FHE engine..."
cd /home/remsee/wrappedMonero/fhe-engine
cargo build --release

# 4. Check Monero wallet setup
print_status "Checking Monero stagenet..."
if command -v monero-wallet-cli &> /dev/null; then
    print_status "Monero CLI found"
else
    print_warning "Monero CLI not found - will use mock data"
fi

# 5. Deploy/test smart contract
print_status "Testing smart contract..."
cd /home/remsee/wrappedMonero/contract

# Create keypair for testing
print_status "Setting up wallet..."
PRIVATE_KEY="2dd64126f227109dd915885461340b97ef302bf757ebabeda5d0c058624db4c7"

# Check current contract status
print_status "Testing contract access..."
npx hardhat console --network baseSepolia << EOF
const wxMRAbi = require("./artifacts/contracts/wxMR.sol/WxMR.json").abi;
const contract = new ethers.Contract("0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5", wxMRAbi, ethers.getDefaultProvider());
contract.name().then(name => console.log("Contract:", name));
contract.symbol().then(symbol => console.log("Symbol:", symbol));
contract.totalSupply().then(supply => console.log("Total supply:", supply.toString()));
EOF

print_status "All components built successfully!"
print_status "Ready for mint/burn testing."