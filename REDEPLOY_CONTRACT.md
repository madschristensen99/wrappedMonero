# 🚀 Redeploy wxMR Contract (Production RISC Zero)

The contract ABI has been updated with the **real RISC Zero verifier**. Due to the breaking changes in the mint function parameters and verifier interface, the contract must be **redeployed**.

## 🔧 **What's Changed**

1. **Verifer Interface Updated**: `verify(bytes,bytes32,bytes32)` instead of mock interface
2. **Mint Function Updated**: Now accepts `bytes32` instead of `uint256` for amount commitments
3. **Production Implementation**: Real RISC Zero STARK proof verification

## 🚦 **Impact**
- **Old contract**: `0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5` **IS OBSOLETE**
- **New contract**: **MUST** be deployed to use production RISC Zero proofs

## 🏗️ **Redeployment Steps**

### 1. Deploy Updated Contract
```bash
cd contract
npx hardhat run scripts/deploy.js --network sepolia
```

### 2. Update Image ID (If Needed)
Generate new image ID from updated guest program:
```bash
cd guest
cargo build --release --target riscv32im-risc0-zkvm-elf
dune compile --image-id // Or use risc0 cli
```

### 3. Update New Contract Address
Replace in all files after deployment:
- [ ] README.md
- [ ] PRODUCTION_SETUP.md  
- [ ] mint_operation.js
- [ ] relay/.env (CONTRACT_ADDRESS)
- [ ] test_bridge_flow.py

### 4. Update Config Files
```bash
# Update all references
find . -type f -name "*.js" -o -name "*.py" -o -name "*.md" | xargs sed -i 's/0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5/NEW_CONTRACT_ADDRESS/g'
```

## ⚡ **Easy Redeployment**
```bash
# Run complete redeployment
./deploy_production.sh
cd contract
echo "export CONTRACT_ADDRESS=NEW_DEPLOYED_ADDRESS" >> .env
```

## 📊 **Verification**
After deployment, verify:
1. ✅ Contract has real RISC Zero verifier interface
2. ✅ mint() function accepts new parameter types  
3. ✅ Image ID matches guest program
4. ✅ Relay service can interact with new contract
5. ✅ README.md shows updated contract address

## 🏁 **That's It!**
Once redeployed, the bridge will use **genuine RISC Zero cryptocurrency proofs** for Monero burn verification.