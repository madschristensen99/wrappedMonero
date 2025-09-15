#!/usr/bin/env python3

import argparse
import json
import os
import sys
from typing import Dict, Any
import web3
from eth_account import Account
from web3.middleware import geth_poa_middleware

# Add validator module to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Contract ABI for confirmMint function
CONTRACT_ABI = [
    {
        "inputs": [
            {
                "internalType": "bytes32",
                "name": "txHash",
                "type": "bytes32"
            },
            {
                "internalType": "uint256",
                "name": "amount",
                "type": "uint256"
            }
        ],
        "name": "confirmMint",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [
            {
                "internalType": "address",
                "name": "",
                "type": "address"
            }
        ],
        "name": "balances",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    }
]

class TSSSigner:
    """Simulates TSS signing for transaction capability"""
    
    def __init__(self, validator_id: int, key_share_path: str):
        self.validator_id = validator_id
        self.key_share_path = key_share_path
        self.load_key_share()
    
    def load_key_share(self):
        """Load the TSS key share"""
        try:
            key_file = os.path.join(self.key_share_path, f"keys_{self.validator_id}_{self.validator_id + 1}.json")
            with open(key_file, 'r') as f:
                self.key_share = json.load(f)
            
            # For demonstrative purposes, we'll use a deterministic private key
            # In real TSS, this would be a proper threshold signature
            self.deterministic_key = self._generate_deterministic_key()
            
        except FileNotFoundError as e:
            print(f"Key share not found: {key_file}")
            print("Make sure you ran the DKG ceremony first")
            sys.exit(1)
    
    def _generate_deterministic_key(self) -> bytes:
        """Generate deterministic key from share for demonstration"""
        import hashlib
        data = json.dumps(self.key_share, sort_keys=True).encode()
        return hashlib.sha256(data).digest()
    
    def sign_message(self, message_hash: bytes) -> bytes:
        """Sign message hash with TSS"""
        # In practice, this would be the actual TSS signature generation
        # For now, we'll simulate with a deterministic signature
        account = Account.from_key(self.deterministic_key)
        signed = account.signHash(message_hash)
        return signed.signature

class TSSContractSigner:
    """Handles TSS signing for contract transactions"""
    
    def __init__(self, rpc_url: str, contract_address: str, authority_address: str):
        self.w3 = web3.Web3(web3.HTTPProvider(rpc_url))
        self.w3.middleware_onion.inject(geth_poa_middleware, layer=0)
        
        self.contract = self.w3.eth.contract(
            address=web3.Web3.to_checksum_address(contract_address),
            abi=CONTRACT_ABI
        )
        
        self.authority_address = authority_address
        print(f"Connected to Web3: {self.w3.isConnected()}")
        print(f"Account balance: {self.w3.eth.get_balance(authority_address)}")
    
    def confirm_mint_tx(self, tx_secret_hex: str, amount_eth: float) -> str:
        """Build and sign a confirmMint transaction with TSS"""
        
        # Convert hex secret to bytes32
        tx_secret = bytes.fromhex(tx_secret_hex[2:]) if tx_secret_hex.startswith('0x') else bytes.fromhex(tx_secret_hex)
        
        # Convert amount to wei
        amount_wei = web3.Web3.to_wei(amount_eth, 'ether')
        
        print(f"Building transaction for secret: {tx_secret_hex}")
        print(f"Amount: {amount_eth} ETH ({amount_wei} wei)")
        
        # Build transaction
        nonce = self.w3.eth.get_transaction_count(self.authority_address)
        
        transaction = self.contract.functions.confirmMint(
            tx_secret,
            amount_wei
        ).buildTransaction({
            'from': self.authority_address,
            'gas': 90000,
            'gasPrice': self.w3.toWei('20', 'gwei'),
            'nonce': nonce,
            'chainId': 11155111  # Sepolia chain ID
        })
        
        print("Transaction built successfully")
        
        # In real implementation, this would use proper TSS signing
        # For demo, we'll use a simulated signature
        # Generate transaction hash for signing
        tx_hash = self.w3.solidityKeccak(
            ['bytes'],
            [self.w3.codec.encode_abi(
                ['bytes32', 'uint256'],
                [tx_secret, amount_wei]
            )]
        )
        
        # Sign transaction hash (simplified)
        dummy_private_key = '0x0ab60f2164615B720C38c6656Eb0420D718dfef6000000000000000000000000'[:66]
        account = Account.from_key(dummy_private_key)
        signed_tx = account.sign_transaction(transaction)
        
        print("Transaction signed successfully")
        
        # Send transaction
        tx_hash = self.w3.eth.send_raw_transaction(signed_tx.rawTransaction)
        
        return tx_hash.hex()
    
    def get_balance(self, address: str) -> int:
        """Get balance for address"""
        return self.contract.functions.balances(address).call()

def main():
    parser = argparse.ArgumentParser(description='Submit confirmMint transaction via TSS')
    parser.add_argument('--secret', required=True, help='Transaction secret as hex string')
    parser.add_argument('--amount', type=float, required=True, help='Amount in ETH')
    parser.add_argument('--rpc', default='https://sepolia.gateway.tenderly.co', help='Ethereum RPC URL')
    parser.add_argument('--contract', default='0x34c209a799b47A4ba5753E17A1Dbf2F5a612fd23', help='Contract address')
    parser.add_argument('--authority', default='0x0ab60f2164615B720C38c6656Eb0420D718dfef6', help='Authority address')
    parser.add_argument('--key-dir', default='./keys', help='Key shares directory')
    parser.add_argument('--validator-id', type=int, default=0, help='Validator ID (0-6)')
    
    args = parser.parse_args()
    
    try:
        # Initialize TSS signer and contract interface
        signer = TSSContractSigner(args.rpc, args.contract, args.authority)
        
        # Submit transaction
        tx_hash = signer.confirm_mint_tx(args.secret, args.amount)
        
        print(f"\n✅ Transaction submitted successfully!")
        print(f"Transaction Hash: {tx_hash}")
        print(f"Explorer URL: https://sepolia.etherscan.io/tx/{tx_hash}")
        
    except Exception as e:
        print(f"❌ Error submitting transaction: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()