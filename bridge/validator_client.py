"""
Validator Client for Decentralized WXMR Bridge
Interacts with the validator network for distributed threshold signature operations
"""

import json
import asyncio
import time
import aiohttp
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path
import hashlib
import base64

@dataclass
class ValidatorNode:
    """Representation of a validator node in the network"""
    id: int
    url: str
    address: str
    is_active: bool = True
    last_seen: float = 0.0
    signature_count: int = 0

@dataclass
class ThresholdSignature:
    """Threshold signature data structure"""
    r: bytes
    s: bytes
    v: int
    validator_id: int
    timestamp: int

@dataclass
class SignatureRequest:
    """Signature request for Monero validation"""
    operation_hash: bytes
    amount: int
    tx_secret: bytes
    nonce: bytes
    timestamp: int

class ValidatorNetworkClient:
    """Client for interacting with the validator network"""
    
    def __init__(self, validator_urls: List[str], threshold: int = 4, total_validators: int = 7):
        self.validator_urls = validator_urls
        self.threshold = threshold
        self.total_validators = total_validators
        self.session = None
        
    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    def calculate_operation_hash(self, tx_secret: bytes, amount: int) -> bytes:
        """Calculate the operation hash for threshold signing"""
        data = tx_secret + amount.to_bytes(8, 'big')
        return hashlib.sha256(data).digest()
    
    def generate_nonce(self, tx_secret: bytes, validator_id: int) -> bytes:
        """Generate deterministic nonce for signature operations"""
        data = tx_secret + validator_id.to_bytes(4, 'big')
        return hashlib.sha256(data).digest()[:32]
    
    async def ping_validator(self, validator_url: str) -> bool:
        """Check if a validator node is online"""
        try:
            async with self.session.get(f"{validator_url}/health") as response:
                return response.status == 200
        except:
            return False
    
    async def collect_quorum_signatures(self, 
                                      tx_secret: bytes, 
                                      amount: int,
                                      timeout: float = 30.0) -> List[ThresholdSignature]:
        """Collect threshold signatures from validator network"""
        
        operation_hash = self.calculate_operation_hash(tx_secret, amount)
        nonce = self.generate_nonce(tx_secret, 0)  # Global nonce for all validators
        timestamp = int(time.time())
        
        signature_data = base64.b64encode(operation_hash + nonce + timestamp.to_bytes(8, 'big')).decode()
        
        # Create signing request payload
        payload = {
            "tx_hash": tx_secret.hex(),
            "amount": amount,
            "signature_data": signature_data,
            "timestamp": timestamp,
            "nonce": nonce.hex()
        }
        
        # Collect signatures asynchronously
        signatures = []
        tasks = []
        
        for url in self.validator_urls:
            task = asyncio.create_task(self._get_validator_signature(url, payload))
            tasks.append(task)
        
        # Wait for threshold number of signatures
        completed = 0
        for task in asyncio.as_completed(tasks, timeout=timeout):
            try:
                result = await task
                if result:
                    signatures.append(result)
                    completed += 1
                    
                    if completed >= self.threshold:
                        break
            except Exception as e:
                print(f"Validator error: {e}")
        
        return signatures
    
    async def _get_validator_signature(self, validator_url: str, payload: dict) -> Optional[ThresholdSignature]:
        """Get signature from individual validator"""
        try:
            async with self.session.post(f"{validator_url}/sign", json=payload):
                response = aiohttp.ClientResponse
            
            if response.status != 200:
                return None
                
            data = await response.json()
            
            return ThresholdSignature(
                r=bytes.fromhex(data['r']),
                s=bytes.fromhex(data['s']),
                v=data['v'],
                validator_id=data['validator_id'],
                timestamp=data['timestamp']
            )
            
        except Exception as e:
            print(f"Failed to connect to validator {validator_url}: {e}")
            return None
    
    def aggregate_signatures(self, signatures: List[ThresholdSignature]) -> Optional[Dict]:
        """Aggregate threshold signatures (simplified for demo)"""
        if len(signatures) < self.threshold:
            return None
            
        # In real implementation, this would perform signature aggregation
        # For now, just return the signatures from validators
        return {
            'signatures': [
                {
                    'r': sig.r.hex(),
                    's': sig.s.hex(),
                    'v': sig.v,
                    'validator_id': sig.validator_id
                }
                for sig in signatures
            ],
            'threshold_met': len(signatures) >= self.threshold,
            'signature_count': len(signatures)
        }


class DistributedBridgeClient:
    """Client for managing the decentralized bridge operations"""
    
    def __init__(self, config_path: Optional[str] = None):
        self.validator_urls = []
        self.threshold = 4
        self.validator_client = None
        
        if config_path:
            self.load_config(config_path)
    
    def load_config(self, path: str):
        """Load validator configuration"""
        try:
            config = json.loads(Path(path).read_text())
            self.validator_urls = config.get('validator_urls', [])
            self.threshold = config.get('threshold', 4)
        except Exception as e:
            print(f"Failed to load config: {e}")
            # Default validator URLs for testing
            self.validator_urls = [
                "http://localhost:8001",
                "http://localhost:8002",
                "http://localhost:8003",
                "http://localhost:8004",
                "http://localhost:8005",
                "http://localhost:8006",
                "http://localhost:8007"
            ]
    
    async def check_quorum_health(self) -> List[Dict]:
        """Check health of validator network"""
        async with ValidatorNetworkClient(self.validator_urls, self.threshold) as client:
            health_results = []
            
            health_tasks = [client.ping_validator(url) for url in client.validator_urls]
            results = await asyncio.gather(*health_tasks, return_exceptions=True)
            
            for url, result in zip(client.validator_urls, results):
                is_healthy = result is True
                health_results.append({
                    'url': url,
                    'online': is_healthy,
                    'status': 'healthy' if is_healthy else 'unreachable'
                })
            
            return health_results
    
    async def submit_threshold_mint_request(
        self, 
        tx_secret: bytes, 
        amount: int,
        sender_address: str
    ) -> Optional[Dict]:
        """Submit threshold-based mint confirmation request"""
        
        async with ValidatorNetworkClient(self.validator_urls, self.threshold) as client:
            # Request signatures from validator network
            signatures = await client.collect_quorum_signatures(tx_secret, amount)
            
            if len(signatures) < self.threshold:
                print(f"Insufficient signatures: {len(signatures)}/{self.threshold}")
                return None
            
            # Aggregate signatures for Ethereum contract submission
            aggregated = client.aggregate_signatures(signatures)
            
            if not aggregated:
                return None
                
            return {
                'tx_secret': tx_secret.hex(),
                'amount': amount,
                'sender': sender_address,
                'signatures': aggregated,
                'threshold_met': True
            }


# Example usage
async def main():
    """Example usage of the validator client"""
    
    bridge_client = DistributedBridgeClient()
    
    # Check network health
    health = await bridge_client.check_quorum_health()
    print("Validator network health:", health)
    
    # Simulate mint request
    tx_secret = bytes.fromhex("a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456")
    amount = 100000000  # 0.1 XMR in atomic units
    sender = "0x1234567890123456789012345678901234567890"
    
    result = await bridge_client.submit_threshold_mint_request(tx_secret, amount, sender)
    print("Mint request result:", result)


if __name__ == "__main__":
    asyncio.run(main())