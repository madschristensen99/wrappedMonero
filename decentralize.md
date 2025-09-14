# WXMR Bridge Decentralization Specification

## Overview
This specification describes how to transform the current centralized WXMR bridge into a trustless, decentralized bridge using threshold signature schemes (TSS) and distributed key generation (DKG).

## Current Trust Assumptions
- **Single Authority Address**: All mint/burn operations require `0x37fD7F8e2865EF6F214D21C261833d6831D8205e`
- **Trusted Bridge Service**: Single Python service verifying Monero transactions
- **Centralized Infrastructure**: All validation & execution runs on single server

## Target Architecture
Transform to a decentralized validator network with threshold signatures:
- **N validator nodes** (recommended: 5-9 validators)
- **T+1 threshold** for signatures (recommended: 67% threshold)
- **Distributed authority** replaces single EOA
- **Byzantine fault tolerance** up to (floor(n/2) - 1) malicious validators

## Protocol Stack

### 1. Threshold Signature Scheme (TSS)
**Selected Protocol**: GG20-based threshold ECDSA
- **Implementation**: Using [ZenGo-X/multi-party-ecdsa](https://github.com/ZenGo-X/multi-party-ecdsa) v3.0
- **Security**: 256-bit secp256k1 + SSS (Shamir's Secret Sharing)
- **Performance**: ~200ms for keygen, ~500ms for signing (LAN)

**Key Configuration**:
- n_validators = 7
- threshold = 5 (t+1 where t=4)
- Supports up to 2 malicious validators

### 2. Key Management
**DKG Process**:
```rust
# Key generation command (each validator runs)
./gg20_keygen -t 4 -n 7 -i <validator_index> \
              --address <validator_addr>:8001 \
              --output share.json \
              --part <session_participants>
```
- **Lifecycle**: Keygen (offline) → Share Distribution → Verification
- **Resharing**: Support for validator set changes (resharing ceremony)
- **Recovery**: Shamir reconstruction + threshold signature for emergency recovery

### 3. Smart Contract Architecture Changes

#### Replace Authority Model
**Current**: Single address signing  
**New**: MPC-derived address controlled by threshold signatures

```solidity
// New contract sections
struct ValidatorConfig {
    uint256 originalThreshold;    // 5 for 7 validators
    mapping(address => bool) validators;
    uint256 totalValidators;
}

struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
}

mapping(address => bool) public authorizedMPCResults;
```

#### Signature Verification
```solidity
// Verification payload
struct Operation {
    bytes32 operationHash;    // mint/burn specific hash
    bytes32 signature;        // threshold signature
    uint256 timestamp;        // prevent replay
    bytes32 nonce;           // additional protection
}

function verifyThresholdSignature(
    Operation calldata op,
    Signature calldata sig
) internal returns (bool) {
    address mpcAddress = address(this); // Contract's MPC-derived address
    bytes32 message = keccak256(
        abi.encodePacked(op.operationHash, op.timestamp, op.nonce)
    );
    bytes32 signedHash = keccak256(
        abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
    );
    return ecrecover(signedHash, sig.v, sig.r, sig.s) == mpcAddress;
}
```

#### Modified Minting Process
1. **Step 1**: User calls `requestMint()` (unchanged)
2. **Step 2**: Validators run MPC to verify XMR transaction
3. **Step 3**: Validators generate threshold signature
4. **Step 4**: Any validator can submit `confirmMint()` with signature

```solidity
function confirmMintWithSig(
    bytes32 txSecret,
    uint64 amount,
    Operation calldata op,
    Signature calldata sig
) external {
    require(verifyThresholdSignature(op, sig), "Invalid threshold signature");
    require(op.operationHash == keccak256(abi.encode(txSecret, amount)), "Invalid op");
    
    // Continue existing mint logic
    address receiver = mintRequestReceiver[txSecret];
    require(receiver != address(0), "Request not found");
    require(!mintSecretUsed[txSecret], "Secret used");
    
    mintSecretUsed[txSecret] = true;
    delete mintRequestReceiver[txSecret];
    
    // FHE minting continues unchanged
    euint64 amtEnc = FHE.asEuint64(amount);
    _totalSupplyEnc = FHE.add(_totalSupplyEnc, amtEnc);
    _balancesEnc[receiver] = FHE.add(_balancesEnc[receiver], amtEnc);
    
    emit MintConfirmed(txSecret, receiver, amount);
}
```

## Validator Network Architecture

### Validator Node Components
1. **XMR Verification Service** (Python)
   - Monitors Monero blockchain
   - Validates transactions using `check_tx_key`
   - Broadcasts consensus messages to other validators

2. **TSS Server** (Rust)
   - MPC protocol implementation
   - Local share management
   - Signature generation

3. **Consensus Layer**
   - **BFT consensus**: Tendermint-style voting for mint claims
   - **Gosssip broadcast**: Validators share XMR verification results
   - **Signature aggregation**: BLS-style signature aggregation support

### Network Communication
```python
# Validator coordination protocol
class ValidatorMessage:
    message_type: str  # "XMR_VERIFIED" | "SIGNATURE_REQUEST" | "SIGNATURE_RESPONSE"
    txid: str
    amount: int
    timestamp: int
    signature: Optional[bytes]
    validator_id: int

# Example communication flow
1. Validation → Gas cost: ~100k units/signature
2. Signature generation → Network: ~1-2 seconds/testnet
3. Submission to contract → Gas cost: ~150k units/tx
```

## Implementation Changes

### Phase 1: Smart Contract Updates (Week 1-2)
- [ ] Add signature verification logic
- [ ] Implement validator registry system
- [ ] Create threshold signature storage
- [ ] Update mint/burn interfaces

### Phase 2: Validator Infrastructure (Week 3-4)
- [ ] Deploy 7-validator testnet on Docker
- [ ] Integration between Python XMR service and Rust TSS
- [ ] Network communication between validators
- [ ] Signature aggregation protocol

### Phase 3: Security & Testing (Week 5-6)
- [ ] Byzantine fault tolerance testing
- [ ] Performance benchmarking (latency, throughput)
- [ ] Security audits on smart contracts
- [ ] Economic modeling for validator incentives

### Phase 4: Mainnet Deployment (Week 7-8)
- [ ] Validator onboarding process
- [ ] Monitoring and alerting system
- [ ] Emergency recovery procedures
- [ ] Documentation and operational guides

## Gas Cost Analysis
- **Traditional Authority**: ~40k gas/mint
- **Threshold Signature**: ~220k gas/mint (includes signature verification)
- **Cost increase**: ~5.5x per mint operation
- **Optimization**: BLS signature aggregation reduces to ~120k gas after EIP-2537

## Security Considerations

### Cryptographic Security
- ECDSA security remains dependent on original 256-bit key space
- SSS provides computational security, not information-theoretic
- Rekeying period: 30 days (recommended)

### Byzantine Fault Tolerance
- **Network partitions**: Validators continue operating after quorum loss
- **Single validator compromise**: Cannot exceed threshold
- **Validator collusion**: Requires super-threshold collusion (5/7)

### Economic Incentives
- **Slashing mechanisms**: Automatically detect threshold violations
- **Validator staking**: 100 ETH per validator (recommended)
- **Reward distribution**: 0.1% of all mint/burn value, split among active validators

## Deployment Configuration

### Testnet Setup (Sepolia)
- Validators: 5 nodes (mainnet: 7 nodes)
- Threshold: 4 signatures (2/3 ratio)
- Network: IRC/Discord coordination for now
- Monitoring: Prometheus + Grafana dashboards

### Mainnet Configuration
- Validators: 7 professional nodes (AWS EC2 t3.large)
- Geographic distribution: US-East, US-West, EU-Central, EU-West, Asia-Pacific
- Security: Hardware security modules (HSM) for key storage
- Redundancy: 3-node backend cluster per validator

## Migration Strategy
1. **Dual Authority**: Run both old and new systems parallel for 30 days
2. **Gradual Validator Onboarding**: Add validators incrementally
3. **Emergency Switch**: `pauseMPC()` function for incidents
4. **Legacy Cleanup**: Phase out old authority after 90 days

This specification transforms WXMR from centralized authority to decentralized threshold signature model while maintaining all existing privacy features through FHE integration.