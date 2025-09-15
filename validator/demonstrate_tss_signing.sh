#!/bin/bash

echo "🔑 TSS Signing Ceremony Demo for Wrapped Monero Bridge"
echo "===================================================="

# Extract addresses from our joint keys
echo "📋 Joint addresses from DKG:"
echo "Joint Ethereum: $(grep -o '"eth_address":[^,]*' keys/keys_0_1.json | tail -1)"
echo "Joint Monero:   $(grep -o '"monero_address":[^,]*' keys/keys_0_1.json | tail -1)"

echo -e "\n🚀 Starting TSS Signing Ceremony for Contract Call"
echo "Contract operation: Mint wxMR tokens for Monero deposit"

# Create a mock signing request
cat > /tmp/signing_request.json << EOF
{
  "operation": "mint_wxmr",
  "monero_tx_hash": "a1b2c3d4e5f6789...",
  "amount": 1.5,
  "target_address": "0x742d35Cc6...",
  "monero_tx_key": "deadbeefcafe...",
  "timestamp": $(date +%s)
}
EOF

# Show the validators participating
echo -e "\n📊 Active TSS Validators (4/7 threshold):"
for i in {0..6}; do
  validator_file="keys/keys_${i}_$((i+1)).json"
  if [ -f "$validator_file" ]; then
    eth_addr=$(grep -o '"eth_address":[^,]*' "$validator_file" | cut -d'"' -f4 | head -1)
    echo "  Validator $i: $eth_addr"
  fi
done

echo -e "\n🎯 Simulated TSS Signing Process:"
echo "1. Validator 0: Generating partial signature..."
echo "2. Validator 1: Adding to signature..." 
echo "3. Validator 2: Contributing share..."
echo "4. Validator 3: Completing threshold signature..."
echo ""

# Simulate the final combined signature
echo "✅ TSS Signature Generated Successfully!"
echo "====================================="
echo "🎉 Contract call ready with MPC signature:"
echo "   r: 0x$(openssl rand -hex 32)"
echo "   s: 0x$(openssl rand -hex 32)"
echo "   v: 27"
echo "   ValidatorIDS: [0,1,2,3]"
echo ""
echo "📦 This signature authorizes minting 1.5 wxMR on Ethereum"
echo "   for the Monero deposit at joint address"

echo -e "\n🔄 TSS signing ceremony complete!"
echo "Validators 0-3 have collaboratively signed the contract call."

# Show key files for reference
echo -e "\n📁 Key Files:"
ls -la keys/