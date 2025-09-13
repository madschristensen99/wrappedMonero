# SPEC: RISC-0-STARK-XMR Bridge  
**Post-quantum, non-custodial, privacy-preserving gateway between Monero and EVM-wrapped XMR (wxMR) powered by RISC Zero STARK proofs**

*Version 1.0 – hackathon edition – 13 Sep 2025*

---

## 0. Elevator Pitch
Users burn XMR on Monero and mint wxMR 1:1 on any EVM L2.  
- **Privacy**: lattice-based linkable ring signature (L2RS-CS) preserves Monero-level anonymity.  
- **No custody**: relay only handles encrypted policy blobs and RISC Zero receipts—never touches spend keys.  
- **Cheap EVM**: on-chain footprint = 224 B STARK receipt + 32 B key-image.  
- **Transparent setup**: RISC Zero STARK needs no trusted ceremony.

---

## 1. Terminology
- **SK** – lattice secret key (user)  
- **PK** – lattice public key / ring  
- **KI** – key-image (linkability tag)  
- **C** – FHE ciphertext containing policy inputs  
- **receipt** – RISC Zero STARK receipt (Seal + journal)  
- **Relay** – untrusted server that runs FHE & guest prover  
- **wxMR** – ERC-20 on L2, 18 decimals, mintable only through this bridge

---

## 2. Functional Requirements
| ID | Requirement | MoS |
|----|-------------|-----|
| F1 | User can create Monero tx whose ring signature is replaced by L2RS-CS | MUST |
| F2 | Amount hidden with native Bulletproofs | MUST |
| F3 | Relay verifies lattice sig against stagenet daemon RPC | MUST |
| F4 | Relay evaluates FHE policy on encrypted inputs; output = 1 bit | MUST |
| F5 | Relay produces RISC Zero receipt proving: valid lattice sig, fresh KI, policy ok | MUST |
| F6 | Smart-contract mints wxMR only if receipt verifies and KI not used | MUST |
| F7 | User can burn wxMR; contract emits event; server watches & releases XMR (manual v0) | SHOULD |
| F8 | Double-mint prevented by on-chain KI registry | MUST |

---

## 3. Non-Functional Requirements
- **Post-quantum privacy** – anonymity & unlinkability rely on Module-SIS / Module-LWE (≥ 128-bit NIST-5).  
- **Hackathon scope** – demo on Monero stagenet & Polygon Mumbai; ring size N = 16; daily-limit hard-coded 10 XMR.  
- **Latency** – end-to-end ≤ 45 s on 8-core cloud VM (includes STARK proving).  
- **Code footprint** – ≤ 2.5 k lines Rust / TS / Solidity.  
- **No trusted setup** – RISC Zero STARK is transparent.

---

## 4. System Components

### 4.1 Wallet CLI / Web-UI (TypeScript + WASM)
- Generate lattice key-pair (seed → SHA-512 → lattice SK).  
- Build Monero tx: pick 15 decoys + own input, output to burn-address.  
- Create MLSAG challenge `e`.  
- Produce L2RS-CS signature `σ` (105 kB).  
- Encrypt `(amount, dest_addr, timestamp)` under FHE public key → `C`.  
- POST `{tx_hash, σ, C, amount_commit, KI}` to Relay REST `/submit`.

### 4.2 Relay Service (Rust)
**Endpoints**  
`POST /v1/submit` – accept burn request  
`GET /v1/status/{uuid}` – polling for mint status  

**Internal pipeline**  
1. Fetch tx from monerod RPC – confirm ≥ 1 conf.  
2. Call `l2rs_verify(σ, ring, KI, e)` – reject if invalid.  
3. Lookup KI in local SQLite – reject if spent.  
4. Run FHE circuit on `C`:  
   `ok = (amount ≤ 10_000_000_000_000 && timestamp ≤ now + 3600)`  
5. If `ok = 1` → run RISC Zero guest prover (see §5).  
6. Obtain STARK receipt → extract journal containing `KI_hash, amount_commit, policy_ok`.  
7. Call `wxMR.mint(receipt, amount)` via ethers-rs.  
8. Store `{tx_hash, KI, status = "minted"}`.

### 4.3 FHE Policy Engine
- Scheme: TFHE-rs, parameters `PARAM_MESSAGE_2_CARRY_2`.  
- Circuit: 2× 64-bit integers comparator (≤) → 1-bit output.  
- Server key loaded at start-up; client key distributed at deploy.

### 4.4 RISC Zero Guest Program (Rust)
**Inputs (private)**  
- `sig_r[2][256]` – lattice sig component  
- `e[256]` – challenge  
- `KI[256]` – key-image  
- `amount64` – plaintext amount  

**Inputs (public)**  
- `KI_hash` – Poseidon(KI)  
- `amount_commit` – Pedersen(amount)  
- `policy_ok` – 1 bit  

**Guest logic**  
1. Verify lattice signature (bigint arithmetic).  
2. Compute Poseidon(KI) and assert equals `KI_hash`.  
3. Compute Pedersen(amount) and assert equals `amount_commit`.  
4. Assert `policy_ok == 1`.  
5. Commit public outputs to journal.

**Host**  
- Loads inputs, drives guest, obtains receipt.  
- Serialises receipt as `0x...` hex for EVM calldata.

### 4.5 Smart Contract (Solidity 0.8.x)
```solidity
contract WxMR is ERC20, IRiscZeroVerifier {
    mapping(bytes32 => bool) public spent;
    address public verifier; // RISC Zero verifier contract
    event Mint(bytes32 indexed KI, address indexed to, uint amount);
    function mint(bytes calldata seal, uint256 amount, bytes32 KI_hash, uint256 amount_commit) external {
        bytes memory journal = abi.encode(KI_hash, amount_commit, uint8(1));
        require(verifier.verify(seal, imageId, journal), "invalid receipt");
        require(!spent[KI_hash], "KI spent");
        spent[KI_hash] = true;
        _mint(msg.sender, amount);
        emit Mint(KI_hash, msg.sender, amount);
    }
}
```
`imageId` is the SHA-256 hash of the ELF file compiled from guest Rust code.

### 4.6 Stagenet Daemon
- Stock `monerod --stagenet --prune-blockchain`  
- RPC ports 38081/38082 exposed to relay only.

---

## 5. Data Formats & Key-sizes
| Object | Encoding | Size |
|--------|----------|------|
| L2RS signature | big-endian u32 array | 105 kB |
| FHE ciphertext C | bincode-serialised | 48 kB |
| STARK receipt (seal) | bincode | 224 B |
| KI | bytes32 | 32 B |

---

## 6. Threat Model
**Assumptions**  
- User client is honest; relay can be malicious but **passive**.  
- FHE keys are generated by DAO; relay does **not** get private key.  
- Smart-contract storage is public.  

**Security Goals**  
- **Anonymity**: given two receipts, adversary wins with prob ≤ ½ + negl.  
- **Unforgeability**: without lattice SK, adversary cannot produce valid receipt.  
- **No double-mint**: on-chain KI map prevents.  
- **Post-quantum**: reduce to Module-SIS / Module-LWE.

---

## 7. API Reference
**Submit Burn**  
`POST /v1/submit`  
Body (JSON):  
```json
{
  "tx_hash": "7d3af...",
  "l2rs_sig": "0x1a2b3c...",   // hex, 105 kB
  "fhe_ciphertext": "0x9f8e...", // hex, 48 kB
  "amount_commit": "0x4e5d...",
  "key_image": "0x3c2b..."
}
```
Response:  
```json
{ "uuid": "550e...", "status": "PENDING" }
```

**Poll Status**  
`GET /v1/status/{uuid}`  
Response:  
```json
{ "status": "MINTED", "tx_hash_eth": "0xab12...", "amount": "420000000000" }
```

---

## 8. Testing & CI
- Unit: `cargo test` (lattice verify, FHE circuit, guest code).  
- Integration:  
  – `pytest` spins up local monerod, Anvil, relay, submits 5 burns.  
  – Assert wxMR balance ↑ and KI map ↑.  
- Load: 100 concurrent burns < 5 min, memory < 2 GB.

---

## 9. Repository Layout
```
├── circuits/          (empty – STARK replaces Circom)
├── contract/          hardhat project, wxmr.sol, deploy scripts
├── fhe-engine/        tfhe-rs service
├── guest/             RISC Zero guest Rust code + build.rs
├── relay/             axum REST server + host prover
├── wallet/            TypeScript CLI + WASM lattice signer
├── tests/             integration + e2e
└── docs/              this spec, sequence diagram
```

---

## 10. Road-map beyond hackathon
| Milestone | ETA | Feature |
|-----------|-----|---------|
| v0.2 | 4 w | Permissionless relay network (libp2p gossip, any relay can submit) |
| v0.3 | 8 w | Burn wxMR → release real XMR (atomic swap via hash-time-locked lattice sig) |
| v1.0 | 6 m | Main-net, ring size N = 64, receipt aggregation, seal size < 180 B |

---

## 11. Glossary & References
[1] EPRINT 2020/1121 – *Lattice-Based One-Time Linkable Ring Signatures*  
[2] monero-serai – github.com/serai-dex/serai  
[3] tfhe-rs – github.com/zama-ai/tfhe-rs  
[4] RISC Zero – github.com/risc0/risc0  

---

**End of Spec – ready to code.**
