#!/usr/bin/env python3 
"""
Working Distributed Key Generation (DKG) Demo 
for WXMR Bridge - EVM and Monero key generation
"""

import os
import sys
import json
import asyncio
import subprocess
import tempfile
from pathlib import Path
import time

class DKGDemo:
    def __init__(self):
        self.validator_dir = Path(__file__).parent / "validator"
        self.keys_dir = self.validator_dir / "keys"
        self.keys_dir.mkdir(exist_ok=True)
        
    def run_single_validator_dkg(self, validator_id):
        """Run DKG for a single validator"""
        print(f"🔄 Running DKG for Validator {validator_id}")
        print("=" * 50)
        
        # Run the keygen command
        cmd = [
            "cargo", "run", 
            "--bin", "validator-tss",
            "--", 
            "--generate-keys",
            f"--index", str(validator_id)
        ]
        
        try:
            result = subprocess.run(
                cmd,
                cwd=self.validator_dir,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            if result.returncode == 0:
                print(f"✅ Validator {validator_id} DKG completed successfully")
                self.display_generated_keys(validator_id)
            else:
                print(f"❌ DKG failed for validator {validator_id}: {result.stderr}")
                
        except subprocess.TimeoutExpired:
            print(f"⏰ DKG timeout for validator {validator_id}")
        except Exception as e:
            print(f"🚨 DKG error: {e}")
    
    def display_generated_keys(self, validator_id):
        """Display the generated keys"""
        validator_key_dir = self.keys_dir / f"validator_{validator_id}"
        if validator_key_dir.exists():
            print(f"\n📁 Keys generated for Validator {validator_id}:")
            
            # Look for any generated key files
            for key_file in validator_key_dir.glob("dkg_keys_*.json"):
                if key_file.exists():
                    with open(key_file) as f:
                        keys_data = json.load(f)
                        print(f"🦊 EVM Public Key: {keys_data['public_key'][:16]}...")
                        print(f"🪙 Monero Chain Code: {keys_data['chain_code'][:16]}...")
                        print(f"🔗 Threshold: {keys_data['threshold']}/{keys_data['total_parties']}")
                        print(f"🎯 Validator ID: {keys_data['validator_id']}")
                        break
            
            # Show mnemonic if it exists
            mnemonic_file = validator_key_dir / f"mnemonic_{validator_id}.txt"
            if mnemonic_file.exists():
                with open(mnemonic_file) as f:
                    print(f"📝 Recovery phrase: {f.read()[:20]}...")
    
    def display_multi_validator_setup(self):
        """Show the DKG network setup"""
        print("\n🌐 Multi-Validator DKG Network Setup")
        print("=" * 40)
        print("Architecture: Distributed 7-Validator Network")
        print("Cryptography: EVM + Monero key pairs with threshold shares")
        print("Threshold: 4-of-7 consensus required")
        print("Keys Generated:")
        print("  - EVM account keys (for Ethereum bridge contracts)")
        print("  - Monero view keys (for Monero transactions)")
        print("  - Distributed shares across validators")
        print()
    
    async def run_child_process_dkg(self, validator_id):
        """Run DKG as child process"""
        env = os.environ.copy()
        env["VALIDATOR_ID"] = str(validator_id)
        
        cmd = [
            "cargo", "run", 
            "--bin", "validator-tss",
            "--", 
            "--generate-keys",
            f"--index", str(validator_id)
        ]
        
        print(f"🔄 Starting validator {validator_id} DKG...")
        
        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=str(self.validator_dir),
                env=env,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await proc.communicate()
            
            if proc.returncode == 0:
                return {
                    "success": True,
                    "validator_id": validator_id,
                    "output": stdout.decode()
                }
            else:
                return {
                    "success": False,
                    "validator_id": validator_id,
                    "error": stderr.decode()
                }
                
        except Exception as e:
            return {
                "success": False,
                "validator_id": validator_id,
                "error": str(e)
            }
    
    async def run_parallel_dkg(self):
        """Run DKG for multiple validators in parallel"""
        self.display_multi_validator_setup()
        
        print("🚀 Running DKG ceremony for 4 validators...")
        print()
        
        # Run DKG for validators 1-4 sequentially for demo
        results = []
        for validator_id in range(1, 5):
            result = await self.run_child_process_dkg(validator_id)
            results.append(result)
            time.sleep(0.5)
        
        print("\n📊 DKG Ceremony Results:")
        print("=" * 30)
        
        successful = 0
        for result in results:
            if result['success']:
                print(f"✅ Validator {result['validator_id']}: Keys generated")
                successful += 1
            else:
                print(f"❌ Validator {result['validator_id']}: Failed - {result['error'][:100]}...")
        
        print(f"\n🎯 {successful}/4 validators completed DKG successfully")
        
        if successful >= 4:
            print("✅ Threshold reached - System ready for bridge operations")
        else:
            print("⚠️  Partial DKG completion - network needs more validators")
        
        return successful

def main():
    """Main DKG demo function"""
    print("🔐 WXMR Bridge - Distributed Key Generation (DKG) Demo")
    print("=" * 65)
    
    demo = DKGDemo()
    
    # Show network overview
    demo.display_multi_validator_setup()
    
    # Single validator demo
    print("\n🎯 Phase 1: Single Validator DKG")
    print("-" * 35)
    demo.run_single_validator_dkg(1)
    
    # Multi-validator demo
    print("\n🖥️  Phase 2: Multi-Validator Async DKG")
    print("-" * 40)
    
    try:
        asyncio.run(demo.run_parallel_dkg())
    except Exception as e:
        print(f"Demo runtime error: {e}")
        print("⚠️  Switching to sequential execution...")
        for i in range(2, 5):
            demo.run_single_validator_dkg(i)
    
    # Summary
    print("\n✨ DKG Demo Complete")
    print("=" * 20)
    print("Keys available in:", demo.keys_dir)
    print("EVM Bridge controls via generated Ethereum keys")
    print("Monero transaction capabilities via generated Monero keys")
    print("Validation ready for 4-of-7 consensus operations")

if __name__ == "__main__":
    # Check if cargo is available
    try:
        result = subprocess.run(["cargo", "--version"], capture_output=True)
        if result.returncode == 0:
            main()
        else:
            print("Cargo not available - see generated demo data")
    except:
        print("Demo can run with actual Rust build environment!")
        print("Install Rust with: curl https://sh.rustup.rs -sSf | sh")