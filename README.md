# wxMR Bridge: Monero ↔ Ethereum Privacy Bridge

A zero-knowledge privacy-preserving bridge enabling Monero (XMR) to be wrapped as ERC-20 tokens (wxMR) while maintaining transactional privacy.

## Contract Deployment

**wxMR Token Contract:**  
[0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5](https://sepolia-explorer.base.org/address/0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5)  
**Network:** Base Sepolia Testnet

---

## Project Overview

This bridge enables cross-chain value transfer from Monero to Ethereum while preserving Monero's privacy properties through zero-knowledge proofs and post-quantum cryptography.

### Core Challenge: Privacy Preservation in Cross-Chain Transfers

| **Source Asset** | **Target Asset** | **Privacy Concern** | **Solution** |
| :--- | :--- | :--- | :--- |
| XMR (Monero) | wxMR (ERC-20) | Public balance exposure | Zero-knowledge privacy preservation |
| Standard cryptocurrency | Post-quantum security | Quantum computing threats | Lattice-based cryptography |
| Privacy coins | DeFi integration | Identity and amount disclosure | Encrypted verification policies |

---

## Architecture Components

### Monero Stagenet
Test environment for Monero transactions enabling safe development and testing with realistic Monero functionality.
- **Purpose**: Secure testing environment for XMR burns
- **Features**: Full Monero privacy functionality with testnet coins
- **Safety**: Isolated from mainnet Monero

### FHE Engine (Fully Homomorphic Encryption)
Computes on encrypted data without decryption, ensuring private transaction validation.
- **Function**: Validates transaction constraints on encrypted inputs
- **Capability**: Proves burn amount ≤ 10 XMR without revealing actual amount
- **Key Files**: `keys.fhe.client`, `keys.fhe.server` (cryptographic key pairs)

### wxMR Smart Contract
ERC-20 contract on Base Sepolia that mints wrapped tokens upon valid Monero burns.
- **Features**: Zero-knowledge proof verification, double-spend prevention, non-custodial design
- **Status**: Deployed and operational at address listed above

### Relay Service
Orchestrates the cross-chain communication between Monero and Ethereum networks.
- **Endpoints**: 
  - `POST /v1/submit` - Submit burn transactions
  - `GET /v1/status/{uuid}` - Transaction status queries
- **Storage**: SQLite database for transaction tracking

### Wallet CLI
Command-line interface for user interactions with the bridge.
```bash
# Generate new wallet
npm run generate

# Execute burn transaction
npm run burn -a 1000000000000 -d 0xYourWallet

# Query transaction status
npm run status -u your-transaction-id
```

---

## Transaction Flow: Cross-Chain Token Bridge

### User Initiation
- **Source**: XMR holdings on Monero network
- **Target**: Equivalent wxMR tokens on Ethereum/BASE
- **Privacy**: Original transaction source remains confidential

### Execution Process
```bash
# Execute bridge transaction
./dist/cli.js burn \
  -a 500000000000 \
  -d 0xEthereumAddress \
  -k private-monero-key \
  -r http://localhost:8080
```

### Technical Process Flow
1. **FHE Validation**: Verifies burn amount ≤ 10 XMR threshold on encrypted data
2. **Post-Quantum Signing**: Generates lattice-based cryptographic signatures
3. **Smart Contract Verification**: Validates zero-knowledge proof and mints tokens
4. **Completion**: User receives wxMR tokens via Ethereum transaction

### Final State
- **Privacy Preserved**: Transaction origin obscured
- **Quantum Resistant**: Post-quantum cryptography applied
- **DeFi Compatible**: ERC-20 standard compliance achieved

---

## Installation and Setup

### Infrastructure Deployment
```bash
# Initialize test networks
docker-compose up -d
```

### Cryptographic Key Generation
```bash
cd fhe-engine
cargo run -- --generate-keys --key-path ./keys.fhe
```
*Generates: `keys.fhe.client`, `keys.fhe.server`*

### System Verification
```bash
# Validate FHE engine functionality
cd guest && cargo test
cd fhe-engine && cargo test
```

---

## API Reference

### Submit Transaction (POST)
```bash
curl -X POST http://localhost:8080/v1/submit \
  -H "Content-Type: application/json" \
  -d '{
    "tx_hash": "76e8d0...b3a9",
    "l2rs_sig": "post-quantum-signature",
    "fhe_ciphertext": "encrypted-data",
    "amount_commit": "amount-proof",
    "key_image": "double-spend-protection"
  }'
```

### Transaction Status (GET)
```bash
curl http://localhost:8080/v1/status/{transaction-uuid}
```

---

## Security Architecture

| **Threat Model** | **Defense Mechanism** | **Security Property** |
| :--- | :--- | :--- |
| Quantum Computing | Lattice-based cryptography | Future computational resistance |
| Smart Contract Exploits | Non-custodial architecture | User fund sovereignty |
| Privacy Compromise | FHE + Zero-knowledge proofs | Transactional confidentiality |
| Double Spending | Monero key images + on-chain tracking | Transaction integrity |
| Key Exposure | Client-side signature generation | Private key confidentiality |

---

## Deployment Status

| **Component** | **Status** | **Details** |
| :--- | :--- | :--- |
| wxMR Contract | **Live** | Deployed at `0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5` (Base Sepolia) |
| FHE Keys | **Ready** | Generated: `fhe-engine/keys.fhe.{client,server}` |
| Test Infrastructure | **Operational** | Docker containers active |
| Relay Service | **Development** | Core architecture complete |
| Wallet CLI | **Built** | Available at `wallet/dist/cli.js` |

---

## Technical Summary

This implementation provides a functional privacy-preserving bridge enabling:
- Cross-chain value transfer from Monero to Ethereum with privacy preservation
- Post-quantum cryptographic security via lattice-based signatures
- Zero-knowledge proof verification maintaining transactional confidentiality
- ERC-20 standard compliance for DeFi integration
