# WXMR Bridge Decentralization Setup Guide

This guide provides comprehensive instructions to deploy the decentralized WXMR bridge as specified in `decentralize.md`.

## Architecture Overview

The decentralized bridge transforms from a single-authority system to a 4-of-7 threshold signature scheme with distributed validation nodes.

## Components

1. **Updated Smart Contract** (`contract/wxMR.sol`)
2. **Rust TSS Server** (`validator/` directory)
3. **Refactored Python Bridge** (`bridge/validator_client.py`)
4. **Docker Compose Orchestration**

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Rust toolchain (for building TSS server)
- Python 3.8+ with UV package manager
- Monero node access
- Ethereum Sepolia node

### Step 1: Initialize Validator Network

```bash
# Build validator nodes
docker-compose --profile setup up keygen-coordinator

# Run initial key generation ceremony
docker-compose run validator-tss --generate-keys --index 1
docker-compose run validator-tss --generate-keys --index 2
# ... for all 7 validators
```

### Step 2: Deploy Updated Contract

```bash
cd contract
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js --network sepolia
```

### Step 3: Configure Bridge

```bash
# Update environment variables
cp .env.example .env
# Edit .env with your values
```

### Step 4: Start Validator Network

```bash
# Start all validator nodes
docker-compose up -d validator-{1,2,3,4,5,6,7}

# Start bridge service
docker-compose up -d bridge
```

## Validator Configuration

Each validator needs a unique configuration file:

```toml
# validator/configs/validator<1-7>.toml
[validators]
validator_id = 1  # Change per validator
threshold = 4
enable_consensus = true
```

## Network Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Validator 1   │    │   Validator 2   │    │   Validator 3   │
│   Port: 8001    │    │   Port: 8002    │    │   Port: 8003    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └─────────────────┬───────────────────────┬─────┘
                           │                       │
                    ┌───────────────────────────────────┐
                    │     WXMR Bridge Service         │
                    │     Coordinates validators       │
                    └───────────────────────────────────┘
                           │
                    ┌───────────────────────────────────┐
                    │  Updated Smart Contract           │
                    │  confirmMintWithSig()             │
                    └───────────────────────────────────┘
```

## Testing

### Validator Health Checks

```bash
# Check all validators online
curl http://localhost:8001/health
curl http://localhost:8002/health
# ... check all 7
```

### Signature Aggregation

```python
from bridge.validator_client import DistributedBridgeClient

async def test_quorum():
    client = DistributedBridgeClient("validator_urls.json")
    health = await client.check_quorum_health()
    print("Network health:", health)
```

### Monero Integration

The bridge now validates Monero transactions through threshold consensus:

1. Bridge detects new mint request
2. Validator network validates Monero transaction
3. Validators sign operation hashes
4. Threshold signatures submitted to contract

## Migration Strategy

During transition, both systems can run concurrently:

1. Legacy: Single authority `0x37fD7F8e2865EF6F214D21C261833d6831D8205e`
2. New: Distributed validators
3. Gradual migration via config toggle

## Security Features

- **Byzantine Fault Tolerance**: Up to 2 validators can be malicious
- **Threshold Cryptography**: 4-of-7 signatures required
- **Replay Protection**: Nonce and timestamp validation
- **Emergency Pause**: Admin can pause all operations

## Monitoring

```bash
# Check validator consensus
curl http://localhost:8001/consensus/status

# Monitor threshold signatures
http://localhost:8001/signatures/metrics
```

## Troubleshooting

### Common Issues

1. **Validator Connection Failures**
   - Check Docker networking
   - Verify port configurations

2. **Insufficient Signatures**
   - Ensure >= 4 validators online
   - Check Monero transaction validity

3. **Gas Estimation Errors**
   - Update gas limits in configs
   - Check Ethereum node connectivity

### Logs and Debugging

```bash
# View validator logs
docker logs wxmr-validator-1

# Monitor bridge operations
docker logs wxmr-bridge
```

## API Endpoints

### Validator Nodes
- `GET /health` - Node status
- `POST /sign` - Request threshold signature
- `GET /consensus/status` - Consensus state

### Bridge Service
- Legacy: `POST /legacy/mint` - Old authority method
- New: `POST /threshold/mint` - Distributed method

This setup provides full decentralization following the WXMR specification with 4-of-7 threshold ECDSA signatures and distributed validation.