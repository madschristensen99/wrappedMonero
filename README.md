# RISC-0-STARK-XMR Bridge

Post-quantum, non-custodial, privacy-preserving gateway between Monero and EVM-wrapped XMR.

## Quick Start

### Prerequisites
- Rust 1.70+
- Node.js 18+
- Python 3.8+
- Docker & Docker Compose

### 1. Start infrastructure
```bash
docker-compose up -d
```

### 2. FHE Setup
```bash
cd fhe-engine
cargo run -- --generate-keys --key-path ./keys.fhe
```

### 3. Deploy contract
```bash
cd contract
npm install
npx hardhat node
npx hardhat run --network localhost scripts/deploy.js
```

### 4. Start relay
```bash
cd relay
cargo run
```

### 5. Use wallet
```bash
cd wallet
npm install
npm run build

# Generate wallet
./dist/cli.js generate

# Burn XMR for wxMR
./dist/cli.js burn -a 1000000000000 -d 0xYourAddress \
  -k your_private_key -r http://localhost:8080

# Check status
./dist/cli.js status -u your_uuid -r http://localhost:8080
```

## Architecture

```
Monero Chain ↔ Relay Service ↔ Ethereum L2
     ↕            ↕              ↕
  User TX     RISC ZKP       wxMR Token
   (Burn)    TFHE Policy     Contract
```

## Testing

```bash
# Unit tests
cd guest && cargo test  
cd fhe-engine && cargo test
cd contract && npm test

# Integration tests
python tests/__init__.py
python tests/test_zkvm.py
```

## API Reference

### Submit Burn
`POST /v1/submit`
```json
{
  "tx_hash": "monero_transaction_hash",
  "l2rs_sig": "lattice_signature_hex",
  "fhe_ciphertext": "encrypted_policy_data",
  "amount_commit": "pedersen_commitment",
  "key_image": "linkability_tag"
}
```

### Check Status
`GET /v1/status/{uuid}`
```json
{
  "status": "MINTED | FAILED | PENDING",
  "tx_hash_eth": "ethereum_transaction_hash",
  "amount": "minted_amount"
}
```

## Security Considerations

- Post-quantum lattice-based cryptography
- Zero-knowledge STARK proofs
- Confidential FHE policy evaluation
- Key-image based double-mint prevention

## Hackathon Scope

- Monero stagenet only
- Base Sepolia testnet
- Manual XMR release on burn
- Configurable for mainnet expansion

## Roadmap
- See specification.md for v0.2-1.0 milestones