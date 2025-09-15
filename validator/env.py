"""
Environment configuration for TSS transaction capability
"""

# Sepolia RPC endpoints
SEPOLIA_RPC = "https://sepolia.gateway.tenderly.co"
SEPOLIA_ALTERNATE_RPC = "https://rpc.sepolia.org"

# TSS Authority Address (from DKG ceremony)
TSS_AUTHORITY = "0x0ab60f2164615B720C38c6656Eb0420D718dfef6"

# Contract address for the bridge
CONTRACT_ADDRESS = "0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23"

# Key management
TSS_PRIVATE_SHARE_PATH = os.environ.get('TSS_PRIVATE_SHARE_PATH', './keys')
PRIVATE_KEY_STORAGE_PATH = os.environ.get('PRIVATE_KEY_STORAGE_PATH', './keys')

# Network configuration
NETWORK_THRESHHOLD = 4
NETWORK_TOTAL_PARTIES = 7

# Gas configuration
DEFAULT_GAS_LIMIT = 90000
DEFAULT_GAS_PRICE_GWEI = 20

# Transaction configuration
CONFIRMATION_THRESHOLD = 6
MAX_INCLUSION_TIME = 300  # 5 minutes

# Validator configuration
VALIDATOR_PORTS = [8001, 8002, 8003, 8004, 8005, 8006, 8007]
INTERVAL_BETWEEN_VALIDATORS = 2  # seconds

# Monero configuration
MONERO_RPC_URL = "http://stagenet.xmr-tw.org:38081/json_rpc"
MONERO_ADDRESS_PREFIX = "monero_"

import os

def get_required_env_vars():
    """Get required environment variables"""
    required_vars = [
        'TSS_PRIVATE_SHARE_PATH',
        'SEPOLIA_RPC_URL'
    ]
    
    missing_vars = []
    for var in required_vars:
        if not os.environ.get(var):
            missing_vars.append(var)
    
    if missing_vars:
        raise ValueError(f"Missing required environment variables: {missing_vars}")

def validate_environment():
    """Validate the environment setup"""
    try:
        get_required_env_vars()
        print("✅ Environment variables validated")
        return True
    except ValueError as e:
        print(f"❌ Environment validation failed: {e}")
        return False

def print_network_config():
    """Print current network configuration"""
    print("🔧 TSS Network Configuration:")
    print(f"  TSS Authority: {TSS_AUTHORITY}")
    print(f"  Contract Address: {CONTRACT_ADDRESS}")
    print(f"  Threshold: {NETWORK_THRESHHOLD}/{NETWORK_TOTAL_PARTIES}")
    print(f"  Sepolia RPC: {SEPOLIA_RPC}")
    print(f"  Monero RPC: {MONERO_RPC_URL}")
    print(f"  Key Storage: {TSS_PRIVATE_SHARE_PATH}")

if __name__ == "__main__":
    print_network_config()
    validate_environment()