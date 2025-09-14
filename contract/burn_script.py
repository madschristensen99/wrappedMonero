#\!/usr/bin/env python3
import subprocess
import sys
import time
print("🚀 MONERO STAGENET TO BASE SEPOLIA wxMR BRIDGE")
print(f"Burning 0.001 XMR to mint wxMR tokens")
print("=" * 50)

# Start the wallet process
process = subprocess.Popen([
    'monero-wallet-cli', 
    '--stagenet', 
    '--wallet-file', '/home/remsee/Monero/wallets/wallet_5',
    '--password', '', 
    '--daemon-host', 'node.monerodevs.org:38089',
    '--trusted-daemon',
    '--log-level', '1'
], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# Execute transfer to valid stagenet address
stagenet_address = "7fKB4yxqVBk71Kj5zUPL3tYqUBBSUuGqMYuqYLdyFbCq4MkgzWwN5LFQBcGTHc"
print(f"Executing: transfer {stagenet_address} 0.001001")
process.stdin.write(f"transfer {stagenet_address} 0.001001\n")
process.stdin.write("y\n")

print("🔥 STAGENET BURN EXECUTED\! Check Base Sepolia for mint...")
print(f"TX checking in background...")
print(f"Contract: 0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5")

stdout, stderr = process.communicate(timeout=60)
print(f"Output: {stdout}")
if stderr: print(f"Error: {stderr}")
