# TSS Transaction Capability Setup Guide

## Overview
This implementation adds live blockchain transaction execution capability from the TSS-generated authority address.
Based on the specification in AddTransactionCapabilitySpec.md.

## Files Created

### Phase 1: Infrastructure ✅
- `/home/remsee/wrappedMonero/validator/configs/validator{0-6}.toml` - 7 configuration files for validators
- `/home/remsee/wrappedMonero/validator/run_validators.sh` - Automated validator launcher script

### Phase 2: Key Management ✅
- Key distribution structure already exists in `./keys/{validator_id}/`
- `./keys/0/keys_0_1.json` through `./keys/6/keys_6_7.json`

### Phase 3: Transaction Execution ✅
- `/home/remsee/wrappedMonero/validator/submit_tss_confirm_mint.py` - Python transaction submitter
- `/home/remsee/wrappedMonero/validator/requirements.txt` - Python dependencies
- `/home/remsee/wrappedMonero/validator/env.py` - Environment configuration

### Phase 4: Monitoring ✅
- `/home/remsee/wrappedMonero/validator/check_status.sh` - Status monitoring script

## Configured Parameters

### TSS Authority Address
`0x0ab60f2164615B720C38c6656Eb0420D718dfef6`

### Contract Address
`0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23`

### Network Configuration
- 7 validators (indices 0-6)
- Port range: 8001-8007
- Threshold: 4/7 consensus

## Quick Start Instructions

### 1. Install Dependencies
```bash
pip install -r requirements.txt
```

### 2. Start the Validator Network
```bash
./run_validators.sh
```

### 3. Monitor Network Status
```bash
./check_status.sh
```

### 4. Submit a Transaction
```bash
python3 submit_tss_confirm_mint.py \
  --secret 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee13 \
  --amount 1.5
```

### 5. Advanced Commands
```bash
# Check logs
./check_status.sh

# Stop all validators
pkill -f validator-tss

# View validator logs
tail -f logs/validator-0.log
```

## Environment Variables

- `TSS_PRIVATE_SHARE_PATH`: Path to key shares directory (default: ./keys)
- `SEPOLIA_RPC_URL`: Ethereum RPC endpoint (default: https://sepolia.gateway.tenderly.co)

## Success Criteria Status
- ✅ DKG ceremony complete
- ✅ Authority address generated: `0x0ab60f2164615B720C38c6656Eb0420D718dfef6`
- ✅ Contract address defined: `0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23`
- ✅ Validator configuration files (7 total)
- ✅ Transaction submission capability
- ✅ Monitoring and status tools

## Required Tools
- Rust compiler (for validator-tss)
- Python 3.6+ (for transaction scripts)
- Required Python packages: web3, eth-account, requests

## Network Architecture
```
Validators: 0-6 (ports 8001-8007)
├── Each with individual configuration
├── Shared TSS authority address
├── Ethereum mainnet connection (Sepolia)
└── Monero stagenet connection
```

## Security Considerations
- Private keys should be stored securely
- Validator indices and keys must match
- RPC endpoints use HTTPS for secure communication