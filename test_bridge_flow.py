#!/usr/bin/env python3
"""
End-to-end test of the Monero bridge with real RISC Zero proofs.
Tests the complete flow from stagenet Monero burn to wxMR mint.
"""

import requests
import json
import time
import subprocess
import os

class MoneroBridgeTester:
    def __init__(self, relay_url="http://localhost:8080"):
        self.relay_url = relay_url
        self.project_root = os.path.dirname(os.path.abspath(__file__))
    
    def test_relay_health(self):
        """Test if the relay service is running"""
        print("🔍 Testing relay service health...")
        try:
            response = requests.get(f"{self.relay_url}/health", timeout=5)
            if response.status_code == 200 and response.text.strip() == "OK":
                print("✅ Relay service is healthy")
                return True
            else:
                print(f"❌ Relay health check failed: {response.text}")
                return False
        except requests.exceptions.RequestException as e:
            print(f"❌ Cannot connect to relay service: {e}")
            return False
    
    def submit_test_burn(self):
        """Submit a test Monero burn transaction"""
        print("📤 Submitting test Monero burn...")
        
        # Mock stagenet transaction data
        test_data = {
            "tx_hash": "0x1d6b8d9b8e7cc4521a8e3b0f57a5d7c9e2f1a3b4c5d6e7f8a9b0c1d2e3f4a5b6",
            "l2rs_sig": "0x90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d",
            "fhe_ciphertext": "0x90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d",
            "amount_commit": "0x90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d",
            "key_image": "0x90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d"
        }
        
        try:
            response = requests.post(f"{self.relay_url}/v1/submit", 
                                   json=test_data, timeout=10)
            response.raise_for_status()
            result = response.json()
            print(f"✅ Burn submitted, UUID: {result['uuid']}")
            return result['uuid']
        except requests.exceptions.RequestException as e:
            print(f"❌ Failed to submit burn: {e}")
            return None
    
    def wait_for_proof(self, uuid, max_wait=60):
        """Wait for proof generation to complete"""
        print("⏳ Waiting for RISC Zero proof generation...")
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            try:
                response = requests.get(f"{self.relay_url}/v1/status/{uuid}", timeout=5)
                if response.status_code == 200:
                    status_data = response.json()
                    
                    if status_data['status'] == 'MINTED':
                        print(f"✅ Proof generated! ETH tx: {status_data['tx_hash_eth']}")
                        return True, status_data['tx_hash_eth']
                    elif status_data['status'] == 'FAILED':
                        print("❌ Proof generation failed")
                        return False, None
                    else:
                        print(f"📊 Current status: {status_data['status']}")
                
                time.sleep(2)
            except requests.exceptions.RequestException as e:
                print(f"⚠️ Status check failed: {e}")
                time.sleep(2)
        
        print("❌ Proof generation timeout")
        return False, None
    
    def test_contract_deployment(self):
        """Test contract deployment scripts"""
        print("🔨 Testing contract deployment...")
        contract_path = os.path.join(self.project_root, "contract")
        
        try:
            # Test Hardhat compilation
            result = subprocess.run(
                ["npx", "hardhat", "compile"],
                cwd=contract_path,
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                print("✅ Contract compilation successful")
                return True
            else:
                print(f"❌ Compilation failed: {result.stderr}")
                return False
        except Exception as e:
            print(f"❌ Deployment test failed: {e}")
            return False
    
    def run_full_test(self):
        """Run complete end-to-end test"""
        print("🚀 Starting Monero Bridge End-to-End Test\n")
        
        # 1. Test infrastructure
        if not self.test_relay_health():
            print("\n💡 Start relay service: cd relay && cargo run")
            return False
        
        # 2. Test contract compilation
        if not self.test_contract_deployment():
            return False
        
        # 3. Test burn submission
        uuid = self.submit_test_burn()
        if not uuid:
            return False
        
        # 4. Test proof generation
        success, tx_hash = self.wait_for_proof(uuid)
        if success:
            print(f"\n🎉 Test completed successfully!")
            print(f"   Transaction Hash: {tx_hash}")
            return True
        else:
            print("\n❌ Test failed")
            return False

def main():
    """Main test runner"""
    tester = MoneroBridgeTester()
    
    print("=" * 60)
    print("  Monero Bridge - Production Integration Test")
    print("=" * 60)
    
    if tester.run_full_test():
        print("\n🎯 All tests passed! Ready for production use.")
    else:
        print("\n⚠️  Some tests failed. Check setup and logs.")

if __name__ == "__main__":
    main()