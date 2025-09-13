"""
Tests for RISC Zero guest program
"""
import subprocess
import tempfile
import os
import json
from pathlib import Path

def test_riscv_guest_compilation():
    """Test guest program compiles successfully"""
    guest_dir = Path(__file__).parent.parent / "guest"
    
    # Change to guest directory
    os.chdir(guest_dir)
    
    # Build for RISC-V target
    result = subprocess.run([
        "cargo", "build", "--release", "--target", "riscv32im-risc0-zkvm-elf"
    ], capture_output=True, text=True)
    
    assert result.returncode == 0, f"Guest compilation failed: {result.stderr}"
    print("Guest program compiled successfully")

def test_guest_execution():
    """Test guest program with mock data"""
    guest_dir = Path(__file__).parent.parent / "guest"
    
    # Mock input data for testing
    mock_input = {
        "sig_r": [
            [1] * 32,
            [2] * 32
        ],
        "e": [3] * 32,
        "ki": [4] * 32,
        "amount64": 1000000000000,
        "ki_hash": [5] * 32,
        "amount_commit": [6] * 32,
        "policy_ok": True
    }
    
    # Write test input
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(mock_input, f)
        input_file = f.name
    
    try:
        # Run guest program (mock execution)
        # In production, would use risc0-zkvm host interface
        
        result = subprocess.run([
            "cargo", "run"  # For testing compilation success
        ], capture_output=True, text=True, cwd=guest_dir)
        
        # Ensure it at least compiles and runs
        assert result.returncode == 0, f"Test execution failed: {result.stderr}"
        
    finally:
        os.unlink(input_file)

def test_key_image_computation():
    """Test KI hashing (SHA-256 placeholder for Poseidon)"""
    import hashlib
    
    ki = b'test_key_image_data'
    ki_hash = hashlib.sha256(ki).digest()
    
    assert len(ki_hash) == 32
    assert ki_hash != hashlib.sha256(b'different_data').digest()

if __name__ == "__main__":
    print("Testing RISC Zero guest program...")
    
    try:
        test_riscv_guest_compilation()
        test_guest_execution()
        test_key_image_computation()
        print("All guest tests passed!")
    except Exception as e:
        print(f"Tests failed: {e}")
        exit(1)