# Wrapped Monero (WXMR)

A privacy-focused bridge between Monero (XMR) and Ethereum, featuring encrypted balances using Fhenix's Fully Homomorphic Encryption (FHE).

## Overview

WXMR (Wrapped Monero) is a privacy-preserving ERC20 token that represents Monero on Ethereum. Key features:

- **Encrypted Balances**: All token balances are encrypted using Fhenix FHE, ensuring privacy on-chain
- **Trustless Bridge**: Two-step minting process with cryptographic verification of Monero transactions
- **User-Friendly Interface**: Modern web interface for interacting with the WXMR token

## Architecture

The system consists of three main components:

1. **Smart Contract** (`contract/wxMR.sol`)
   - ERC20-compatible token with encrypted balances
   - Two-step minting process for bridging XMR
   - Authority-controlled minting and burning
   - FHE-powered private transfers

2. **Bridge Service** (`bridge/`)
   - Monitors Monero network for incoming transactions
   - Verifies XMR deposits using transaction keys
   - Automatically mints WXMR tokens upon confirmation
   - Python-based service using Monero RPC

3. **Frontend** (`frontend/`)
   - Web interface for token operations
   - MetaMask integration
   - Transfer, mint, and burn functionality
   - Real-time balance updates
   - 
 ## Deployed Contract Address
[0x25305b62299562197582eB87443B64B894685Fb4](https://sepolia.etherscan.io/address/0x25305b62299562197582eB87443B64B894685Fb4)

## Validator Directory (Cryplography Infrastructure)

### Overview
The `validator/` directory contains the TSS (Threshold Signature Scheme) infrastructure for implementing secure cryptographic operations across a distributed network. This enables threshold signatures and live blockchain transaction execution for the WXMR bridge.

### Directory Structure
```
validator/
├── validator-tss                  # Compiled TSS validator binary
├── configs/validator{0-6}.toml    # Individual validator configurations
├── keys/                          # DKG-generated key shares
│   ├── 0/keys_0_1.json           # Validator 0 key share
│   ├── 1/keys_1_2.json           # Validator 1 key share
│   └── ... through validator 6
├── scripts/
│   ├── run_validators.sh         # Start 7-validator network
│   ├── check_status.sh          # Monitor network status
│   └── start_dkg_ceremony.sh    # Run distributed key generation
├── submit_tss_confirm_mint.py    # Transaction submission
├── requirements.txt              # Python dependencies
├── SETUP.md                     # Comprehensive setup guide
└── env.py                      # Environment configuration
```

### Key Components

#### 1. TSS Authority Address
**`0x0ab60f2164615B720C38c6656Eb0420D718dfef6`** - Generated via DKG ceremony

#### 2. Validator Network
- **7 validators** (indices 0-6)
- **4/7 threshold** for consensus
- **Ports 8001-8007** respectively
- **Sepolia RPC** integration

#### 3. Core Files and Scripts

**`run_validators.sh`** - One-command network start:
```bash
./run_validators.sh
```

**`submit_tss_confirm_mint.py`** - Transaction submission:
```bash
python3 submit_tss_confirm_mint.py --secret 0x123... --amount 1.5
```

**`check_status.sh`** - Network monitoring:
```bash
./check_status.sh
```

#### 4. Configuration
Each validator uses individual `.toml` files for:
- Network binding (ports 8001-8007)
- Monero RPC connectivity
- Ethereum Sepolia RPC setup
- MPC parameters (4/7 threshold)
- Key share paths

#### 5. Cryptographic Setup
- **Distributed Key Generation (DKG)** for shared secrets
- **Threshold signatures** (TSS) for transaction authorization
- **Ethereum addresses** derived from combined public keys
- **Monero addresses** with proper derivation

### Quick Start Commands

```bash
# 1. Build validator
cd validator
cargo build --release

# 2. Start the network
./run_validators.sh

# 3. Monitor status
./check_status.sh

# 4. Submit test transaction
python3 submit_tss_confirm_mint.py --secret 0xeeee... --amount 1.5

# 5. Check logs
tail -f logs/validator-0.log
```

### Demo Flow
1. **Launch**: Run 7 validators on ports 8001-8007
2. **Monitor**: Check network health with status script
3. **Transact**: Submit transactions via Python script
4. **Verify**: Confirmed transactions on Sepolia testnet

### Security Features
- Private keys never leave validator nodes
- 4-of-7 consensus required for signatures
- Deterministic key derivation
- Secure RPC connections

## Usage

### Wrapping XMR to WXMR

1. Send XMR to the bridge's Monero address
2. Call `requestMint()` with the transaction details
3. Wait for the bridge to verify and confirm the mint
4. Receive encrypted WXMR tokens

### Transferring WXMR

1. Connect MetaMask to the dApp
2. Enter recipient's address and amount
3. Submit the transfer transaction
4. Transaction is processed with encrypted balances

### Unwrapping WXMR to XMR

1. Access the admin interface
2. Initiate a burn request with your Monero address
3. Wait for the authority to process the burn
4. Receive XMR at your specified address

## Security Features

- Encrypted balances using Fhenix FHE
- Two-step minting process with cryptographic verification
- Authority-controlled bridge operations
- Monero transaction key verification
- Multisig support for administrative functions


## License

MIT License

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request
