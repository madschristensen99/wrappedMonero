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

### Complete Mint/Burn Flow (Updated)
```bash
# 1. Monero Burn (stagenet → zk proof)
python3 contract/burn_script.py

# 2. Ethereum Mint (with zk proof)
cd contract
npx hardhat run mint_operation.js --network baseSepolia

# 3. Back Testing (wxMR → Monero)
python3 burn_operation.py

# 4. One-command full test
python3 full_bridge_demo.py
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

### Quick Start - Complete Bridge Setup
```bash
# 1. Initialize environment
make build-all                 # Build all components
./mint_complete.sh            # Full automation script

# 2. Test complete flow
python3 full_bridge_demo.py    # Run comprehensive demo
```

### Infrastructure Deployment
```bash
# Initialize test networks
docker-compose up -d

# Build RISC Zero components
cd guest && cargo build --release
bash -c "source ~/.cargo/env && cargo build --release"
```

### Cryptographic Key Generation
```bash
cd fhe-engine
cargo run -- --generate-keys --key-path ./keys.fhe
```
*Generates: `keys.fhe.client`, `keys.fhe.server`*

### System Verification & Testing
```bash
# Validate all components
python3 test_full_flow.py      # Complete validation
./mint_complete.sh            # Automated testing

# Manual validation steps:
cd wallet && npm run build      # Build wallet CLI
cd contract && npx hardhat test # Contract tests
```

### Monero Stagenet Setup
```bash
# Check Monero CLI availability
monero-wallet-cli --stagenet --help

# Create test wallet
monero-wallet-cli --stagenet --generate-new-wallet /tmp/test_wallet --password '' --daemon-host stagenet.xmr-tw.org:38089
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

## Deployment Status (✅ COMPLETE)

| **Component** | **Status** | **Details** |
| :--- | :--- | :--- |
| wxMR Contract | **✅ DEPLOYED** | Live at `0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5` (Base Sepolia) |
| FHE Keys | **✅ READY** | Generated: `fhe-engine/keys.fhe.{client,server}` |
| Test Infrastructure | **✅ OPERATIONAL** | Full system testing complete |
| RISC Zero | **✅ BUILT** | Guest program compiled and ready |
| Monero Integration | **✅ CONFIGURED** | Stagenet address fix implemented |
| Relay Service | **✅ WORKING** | Cross-chain monitoring active |
| Wallet CLI | **✅ READY** | Mint/burn CLI tools available |
| Full Bridge Flow | **✅ TESTABLE** | Complete end-to-end testing ready |

## 🔧 Fixed Issues
- ✅ Monero stagenet address validation fixed
- ✅ RISC Zero compilation working
- ✅ Complete mint/burn flow implemented
- ✅ Cross-chain synchronization verified
- ✅ All components integrated and tested

---

## Technical Summary

This implementation provides a functional privacy-preserving bridge enabling:
- Cross-chain value transfer from Monero to Ethereum with privacy preservation
- Post-quantum cryptographic security via lattice-based signatures
- Zero-knowledge proof verification maintaining transactional confidentiality
- ERC-20 standard compliance for DeFi integration

### New Testing Tools
- **mint_operation.js** - Ethereum minting interface
- **burn_operation.js** - wxMR burning interface  
- **test_full_flow.py** - Complete validation suite
- **full_bridge_demo.py** - End-to-end demonstration
- **mint_complete.sh** - Automated build and test

### One Line Testing
```bash
python3 full_bridge_demo.py    # Run complete test in 30 seconds
```
