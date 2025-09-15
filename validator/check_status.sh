#!/bin/bash

# TSS Validator Status Check Script
# Monitors validator network and contract status

set -e

# Configuration
TSS_AUTHORITY="0x0ab60f2164615B720C38c6656Eb0420D718dfef6"
CONTRACT_ADDRESS="0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23"
SEPOLIA_RPC="https://sepolia.gateway.tenderly.co"

echo "🔍 TSS Validator Status Check"
echo "============================="

# 1. Check validator processes
echo "📊 Validator Process Status:"
for i in {0..6}; do
    pid=$(pgrep -f "validator-tss.*index.*$i" || echo "NOT_RUNNING")
    port=$((8001 + i))
    if curl -s http://localhost:$port/health > /dev/null 2>&1; then
        echo "  ✅ Validator-$i: Running on port $port (PID: ${pid})"
    else
        echo "  ❌ Validator-$i: ${pid}"
    fi
done

# 2. Check account balance
echo ""
echo "💰 Authority Account: $TSS_AUTHORITY"
balance_response=$(curl -s -X POST \
  $SEPOLIA_RPC \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"eth_getBalance",
    "params":["'$TSS_AUTHORITY'", "latest"],
    "id":1
  }')

if [[ $balance_response == *"jsonrpc"* ]]; then
    balance_hex=$(echo $balance_response | jq -r '.result')
    balance_wei=$(echo $balance_hex | sed 's/0x//')
    if [[ $balance_wei == "0" || $balance_wei == "" ]]; then
        balance_eth="0.0"
    else
        balance_eth=$(echo "ibase=16; $balance_wei" | bc | awk '{print $1/1000000000000000000}')
    fi
    echo "  ETH Balance: $balance_eth »"
else
    echo "  ⚠️  Unable to fetch balance from RPC"
fi

# 3. Check recent transactions
echo ""
echo "📋 Recent Transactions:"
recent_tx=$(curl -s \
  "https://api-sepolia.etherscan.io/api?module=account&action=txlist&address=$TSS_AUTHORITY&startblock=latest&endblock=99999999&sort=desc&apikey=demo" \
  | jq -r '.result[:5][] | { hash: .hash, method: .methodId, timestamp: .timeStamp, value: .value }' 2>/dev/null || echo "❌ Unable to fetch transactions")

if [[ -n "$recent_tx" && $recent_tx != *"error"* ]]; then
    echo "$recent_tx" | jq -r '"  - ", .hash, .method, (.value | tonumber / 1000000000000000000 | tostring)'
else
    echo "  No recent transactions or API unavailable"
fi

# 4. Check contract interaction
echo ""
echo "📄 Contract Interaction Check:"
rpc_status=$(curl -s -X POST \
  $SEPOLIA_RPC \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"eth_getCode",
    "params":["'$CONTRACT_ADDRESS'", "latest"],
    "id":1
  }')

contract_code=$(echo $rpc_status | jq -r '.result')
if [[ $contract_code != "0x" && ${#contract_code} -gt 2 ]]; then
    echo "  ✅ Contract deployed at: $CONTRACT_ADDRESS"
    echo "  ✅ Bytecode length: $((${#contract_code} - 2)) chars"
else
    echo "  ❌ Contract not found or RPC unavailable"
fi

# 5. Check validator log files
echo ""
echo "📝 Log File Status:"
for i in {0..6}; do
    if [[ -f "logs/validator-${i}.log" ]]; then
        last_line=$(tail -1 logs/validator-${i}.log 2>/dev/null || echo "empty")
        status="$(find logs/validator-${i}.log -mmin -1 2>/dev/null | wc -l)"
        if [[ $status -eq 1 ]]; then
            echo "  ✅ Validator-$i logs: Active ("$last_line"...)"
        else
            echo "  ⚠️  Validator-$i logs: Stale"
        fi
    else
        echo "  ❌ Validator-$i logs: Missing"
    fi
done

# 6. Network connectivity test
echo ""
echo "🌐 Network Connectivity:"
timeout 5 bash -c "cat < /dev/null > /dev/tcp/localhost/8001" 2>/dev/null && echo "  ✅ Port 8001: Available" || echo "  ❌ Port 8001: Unavailable"
timeout 5 bash -c "cat < /dev/null > /dev/tcp/localhost/8002" 2>/dev/null && echo "  ✅ Port 8002: Available" || echo "  ❌ Port 8002: Unavailable"
timeout 5 bash -c "cat < /dev/null > /dev/tcp/localhost/8003" 2>/dev/null && echo "  ✅ Port 8003: Available" || echo "  ❌ Port 8003: Unavailable"

# Summary
echo ""
echo "📈 Status Summary:"
running_count=$(pgrep -f validator-tss | wc -l)
current_network_height=$(curl -s -X POST $SEPOLIA_RPC -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | sed 's/0x//')
if [[ $current_network_height =~ ^[0-9]+$ ]]; then
    block_num=$(echo "ibase=16; $current_network_height" | bc)
    echo "  Network Block: $block_num"
fi
echo "  Validators: $running_count/7"
echo ""

# Transaction test prompt
echo "🔍 Ready to test transactions?"
echo "   Run: ./submit_tss_confirm_mint.py --secret 0xeeee... --amount 1.5"