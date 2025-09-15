#!/bin/bash

echo "🚀 Starting DKG Ceremony for Wrapped Monero Bridge Validators"
echo "============================================================"

# Configuration
CONFIG_FILE="config.toml"
VALIDATOR_COUNT=4
THRESHOLD=3

# Create individual config files for each validator
echo "📋 Setting up validator configurations..."

for i in $(seq 1 $VALIDATOR_COUNT); do
    cp config.toml "configs/validator${i}.toml"
    # Update individual validator configs
    sed -i "s/validator_id = 1/validator_id = $i/" "configs/validator${i}.toml"
done

# Start key generation ceremony
echo "🔑 Starting distributed key generation (DKG) for $VALIDATOR_COUNT validators..."
echo "Threshold: $THRESHOLD signatures required out of $VALIDATOR_COUNT validators"

# Run key generation for each validator
for i in $(seq 1 $VALIDATOR_COUNT); do
    echo "Running DKG for validator $i..."
    timeout 30 ./target/release/validator-tss --generate-keys --index $i &
done

# Wait for all processes
echo "⏳ Waiting for DKG ceremony to complete..."
wait

echo "✅ DKG ceremony completed!"

# Show generated keys
echo "📊 Displaying generated joint keys..."
./target/release/validator-tss --show-bridge