#!/bin/bash

# TSS Validator Network Launcher
# Starts 7 validator nodes as specified in the AddTransactionCapabilitySpec

set -e

echo "🚀 Starting TSS Validator Network..."
echo "=================================="

# Check if validator-tss binary exists, if not build it
if [ ! -f "./validator-tss" ]; then
    echo "Building validator-tss binary..."
    cargo build --release
    cp target/release/validator-tss ./validator-tss
fi

# Create log directory
mkdir -p logs

# Validate configs exist
for i in {0..6}; do
    if [ ! -f "configs/validator${i}.toml" ]; then
        echo "❌ Missing config: configs/validator${i}.toml"
        exit 1
    fi
done

# Update the actual TSS address
TSS_AUTHORITY="0x0ab60f2164615B720C38c6656Eb0420D718dfef6"
CONTRACT_ADDRESS="0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23"

echo "✅ TSS Authority Address: $TSS_AUTHORITY"
echo "✅ Contract Address: $CONTRACT_ADDRESS"
echo ""

# Start validators in background
# validator-0: ./validator-tss --index 0 --port 8001 --config configs/validator0.toml
echo "Starting validator-0 on port 8001..."
RUST_LOG=info ./validator-tss --index 0 --port 8001 --config configs/validator0.toml > logs/validator-0.log 2>&1 &
VALIDATOR_0_PID=$!

# validator-1: ./validator-tss --index 1 --port 8002 --config configs/validator1.toml
echo "Starting validator-1 on port 8002..."
RUST_LOG=info ./validator-tss --index 1 --port 8002 --config configs/validator1.toml > logs/validator-1.log 2>&1 &
VALIDATOR_1_PID=$!

# validator-2: ./validator-tss --index 2 --port 8003 --config configs/validator2.toml
echo "Starting validator-2 on port 8003..."
RUST_LOG=info ./validator-tss --index 2 --port 8003 --config configs/validator2.toml > logs/validator-2.log 2>&1 &
VALIDATOR_2_PID=$!

# validator-3: ./validator-tss --index 3 --port 8004 --config configs/validator3.toml
echo "Starting validator-3 on port 8004..."
RUST_LOG=info ./validator-tss --index 3 --port 8004 --config configs/validator3.toml > logs/validator-3.log 2>&1 &
VALIDATOR_3_PID=$!

# validator-4: ./validator-tss --index 4 --port 8005 --config configs/validator4.toml
echo "Starting validator-4 on port 8005..."
RUST_LOG=info ./validator-tss --index 4 --port 8005 --config configs/validator4.toml > logs/validator-4.log 2>&1 &
VALIDATOR_4_PID=$!

# validator-5: ./validator-tss --index 5 --port 8006 --config configs/validator5.toml
echo "Starting validator-5 on port 8006..."
RUST_LOG=info ./validator-tss --index 5 --port 8006 --config configs/validator5.toml > logs/validator-5.log 2>&1 &
VALIDATOR_5_PID=$!

# validator-6: ./validator-tss --index 6 --port 8007 --config configs/validator6.toml
echo "Starting validator-6 on port 8007..."
RUST_LOG=info ./validator-tss --index 6 --port 8007 --config configs/validator6.toml > logs/validator-6.log 2>&1 &
VALIDATOR_6_PID=$!

# Write PIDs to file for easy management
cat > logs/pids.txt << EOF
Validator Network PIDs:
Validator-0: $VALIDATOR_0_PID
Validator-1: $VALIDATOR_1_PID
Validator-2: $VALIDATOR_2_PID
Validator-3: $VALIDATOR_3_PID
Validator-4: $VALIDATOR_4_PID
Validator-5: $VALIDATOR_5_PID
Validator-6: $VALIDATOR_6_PID
EOF

echo ""
echo "✅ All validators started successfully!"
echo "📁 Logs available in: logs/"
echo "🔍 Monitor logs: tail -f logs/validator-*.log"
echo "🛑 Stop all validators: pkill -f validator-tss"
echo ""
echo "📊 Validator Status:"
sleep 2

for i in {8001..8007}; do
    if nc -z localhost $i 2>/dev/null; then
        echo "  ✅ Validator on port $i - RUNNING"
    else
        echo "  ❌ Validator on port $i - NOT RUNNING"
    fi
done

echo ""
echo "🎯 Ready for transactions! After validators are fully synced, run:"
echo "   python3 submit_tss_confirm_mint.py --secret 0xeeee... --amount 1.5"
echo ""
echo "📝 Example transaction commands:"
echo "   python3 submit_tss_confirm_mint.py --secret 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee13 --amount 1.5"
echo "   python3 submit_tss_confirm_mint.py --secret 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef --amount 2.0"
echo ""

echo "✨ TSS Validator Network is LIVE!"
echo "================================="