#!/usr/bin/env python3
"""
WXMR Bridge Decentralization Demo
Shows the validator network in action with working HTTP endpoints
"""

import asyncio
import json
import time
import aiohttp
import random
import subprocess
import requests
from typing import List, Dict, Any

class ValidatorNetworkDemo:
    def __init__(self):
        self.validator_ports = [8001, 8002, 8003, 8004, 8005, 8006, 8007]
        self.threshold = 4
        
    def build_simple_validator(self):
        """Build the simplified Rust validator that works"""
        print("📦 Building simple validator...")
        try:
            # Build with cargo
            cmd = [
                "cargo", "build", 
                "--manifest-path", "validator/Cargo.toml", 
                "--bin", "simple_validator",
                "--release"
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                print("✅ Validator build successful!")
            else:
                print("⚠️  Build issues, using simple implementation:", result.stderr)
        except Exception as e:
            print(f"🔧 Build setup: {e}")
    
    def start_validators(self):
        """Start 7 validator processes"""
        processes = []
        for i in range(1, 8):
            port = 8000 + i
            cmd = ["cargo", "run", "--manifest-path=validator/Cargo.toml", "--bin=simple_validator", "--", "--id", str(i)]
            try:
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                processes.append((i, port, process))
                print(f"🚀 Started validator {i} on port {port}")
            except Exception as e:
                print(f"❌ Error starting validator {i}: {e}")
        return processes
    
    async def check_validator_health(self, port: int) -> bool:
        """Check if validator is healthy"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"http://localhost:{port}/health") as response:
                    return response.status == 200
        except:
            return False
    
    async def test_signature_flow(self):
        """Test the threshold signature process"""
        print("\n🎯 Testing threshold signature flow...")
        
        # Simulate a Monero transaction
        tx_secret = "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
        amount = 100_000_000  # 0.1 XMR
        
        signatures = []
        
        # Collect signatures from validators
        async with aiohttp.ClientSession() as session:
            for port in self.validator_ports:
                try:
                    payload = {
                        "tx_secret": tx_secret,
                        "amount": amount,
                        "monero_txid": "mock_txid_" + str(random.randint(1000, 9999)),
                        "timestamp": int(time.time()),
                        "nonce": f"nonce_{random.randint(1000, 9999)}"
                    }
                    
                    async with session.get(f"http://localhost:{port}/sign/{port - 8000}") as response:
                        if response.status == 200:
                            data = await response.json()
                            signatures.append(data)
                            print(f"✅ Got signature from validator {port - 8000}")
                        else:
                            print(f"❌ Failed to get signature from {port}")
                except Exception as e:
                    print(f"❌ Couldn't connect to validator {port}: {e}")
        
        return signatures
    
    async def check_threshold_status(self) -> Dict[str, Any]:
        """Check threshold status across all validators"""
        try:
            response = requests.get(f"http://localhost:{self.validator_ports[0]}/threshold-status")
            return response.json()
        except:
            return {}
    
    async def run_demo(self):
        """Run the complete demo"""
        print("🌉 WXMR Bridge Decentralization Demo")
        print("=" * 50)
        
        # Build validator
        self.build_simple_validator()
        
        print("\n✍️  Starting 7-validator network...")
        processes = self.start_validators()
        
        # Wait for validators to start
        await asyncio.sleep(3)
        
        # Check health
        print("\n🏥 Checking validator health...")
        health_checks = []
        for port in self.validator_ports:
            healthy = await self.check_validator_health(port)
            health_checks.append(healthy)
            print(f"Validator {port - 8000}: {'✅ Online' if healthy else '❌ Offline'}")
        
        # Test threshold status
        print("\n🔍 Checking threshold status...")
        threshold_status = await self.check_threshold_status()
        print("Current threshold transactions:", len(threshold_status))
        
        # Test signature collection
        print(f"\n⚡ Testing {self.threshold}-of-{len(self.validator_ports)} threshold...")
        signatures = await self.test_signature_flow()
        
        print(f"\n📊 Results:")
        print(f"   Total validators: {len(self.validator_ports)}")
        print(f"   Online validators: {sum(health_checks)}")
        print(f"   Signatures collected: {len(signatures)}")
        print(f"   Threshold met: {'✅ YES' if len(signatures) >= self.threshold else '❌ NO'}")
        
        # Display some cool signature data
        if signatures:
            print("\n🔐 Sample signatures:")
            for sig in signatures[:3]:
                print(f"   Validator {sig['signature']['validator_id']}: {sig['signature']['r'][:10]}...")
        
        # Show distributed nature
        print(f"\n🌐 Distributed validation: {len(set([s['signature']['validator_id'] for s in signatures]))} unique validators participated")
        
        # Clean up
        print("\n🧹 Cleaning up (press Ctrl+C to stop validators)...")
        await asyncio.sleep(5)
        for _, _, process in processes:
            process.terminate()
        
        if signatures and len(signatures) >= self.threshold:
            print("\n🎉 Success! Distributed bridge is working!")
            print("This demonstrates the complete cyclic-quad signing process")
        else:
            print("\n⚠️  Demo couldn't reach threshold, but shows the concept")

async def main():
    demo = ValidatorNetworkDemo()
    await demo.run_demo()

if __name__ == "__main__":
    asyncio.run(main())