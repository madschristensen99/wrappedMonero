import os

import dotenv

from eth_typing import HexAddress, HexStr
from eth_typing.evm import ChecksumAddress as EvmAddress
from typing import NewType

# Load environment variables
dotenv.load_dotenv()

# Monero types
XmrAddress = NewType("XmrAddress", str)

# Environment variables
ETH_PRIVATE_KEY = os.environ["ETH_PRIVATE_KEY"]
XMR_RECEIVE_ADDRESS = XmrAddress(os.environ["XMR_RECEIVE_ADDRESS"])
W_XMR_CONTRACT_ADDRESS = EvmAddress(
    HexAddress(HexStr(os.environ["W_XMR_CONTRACT_ADDRESS"]))
)

# EVM RPC API connection info
# https://chainlist.org/chain/11155111
EVM_SEPOLIA_API = "https://sepolia.gateway.tenderly.co"
# Completely arbitrary
EVM_REQUIRED_CONFIRMATIONS = 1

# monero cli RPC API connection info
# https://monero.fail/?chain=monero&network=stagenet
MONERO_STAGENET_API = "http://localhost:38081"
# Completely arbitrary
MONERO_REQUIRED_CONFIRMATIONS = 1

# Gas estimation buffer (20% extra)
GAS_BUFFER_MULTIPLIER = 1.2
