#!/usr/bin/env -S uv run
import json
import secrets
from pathlib import Path
from web3 import Web3
import logging

from lib import ETH_PRIVATE_KEY, W_XMR_CONTRACT_ADDRESS, EVM_SEPOLIA_API

# Contract ABI
w_xmr_contract_abi = json.loads(Path("abi.json").read_text())

logger = logging.getLogger(__name__)


def request_mint():
    """Send a requestMint transaction to the wXMR contract."""
    # Connect to Ethereum
    w3 = Web3(Web3.HTTPProvider(EVM_SEPOLIA_API))
    assert w3.is_connected()
    logger.info("Connected to EVM API at %s", EVM_SEPOLIA_API)

    # Get account from private key
    account = w3.eth.account.from_key(ETH_PRIVATE_KEY)
    logger.info("Using Ethereum address: %s", account.address)

    # Create contract instance
    contract = w3.eth.contract(address=W_XMR_CONTRACT_ADDRESS, abi=w_xmr_contract_abi)

    # Generate random transaction ID and secret (32 bytes each)
    tx_id = secrets.token_bytes(32)
    tx_secret = secrets.token_bytes(32)

    logger.info("Generated txId: %s", tx_id.hex())
    logger.info("Generated txSecret: %s", tx_secret.hex())
    logger.info("Receiver address: %s", account.address)

    # Estimate gas first
    try:
        estimated_gas = contract.functions.requestMint(
            tx_id,  # bytes32 txId
            tx_secret,  # bytes32 txSecret
            account.address,  # address receiver
        ).estimate_gas({"from": account.address})
        gas_limit = int(estimated_gas * 1.2)  # Add 20% buffer
        logger.info("Estimated gas: %d, using limit: %d", estimated_gas, gas_limit)
    except Exception as e:
        logger.warning("Gas estimation failed: %s, using default limit", e)
        gas_limit = 200000

    # Calculate proper fee structure for London transaction
    base_fee = w3.eth.gas_price
    priority_fee = w3.to_wei(2, "gwei")
    max_fee = max(base_fee * 2, priority_fee + base_fee)

    # Build transaction
    tx = contract.functions.requestMint(
        tx_id,  # bytes32 txId
        tx_secret,  # bytes32 txSecret
        account.address,  # address receiver
    ).build_transaction(
        {
            "from": account.address,
            "nonce": w3.eth.get_transaction_count(account.address),
            "gas": gas_limit,
            "maxFeePerGas": max_fee,  # London transaction
            "maxPriorityFeePerGas": priority_fee,  # Priority fee
        }
    )

    # Sign and send transaction
    signed_tx = w3.eth.account.sign_transaction(tx, ETH_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

    logger.info("Sent requestMint transaction: %s", tx_hash.hex())

    # Wait for transaction confirmation
    try:
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        if receipt["status"] == 1:
            logger.info(
                "Transaction %s confirmed successfully in block %d",
                tx_hash.hex(),
                receipt["blockNumber"],
            )
        else:
            logger.error(
                "Transaction %s failed with status %d", tx_hash.hex(), receipt["status"]
            )
    except Exception as e:
        logger.error(
            "Error waiting for transaction %s confirmation: %s", tx_hash.hex(), e
        )


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    request_mint()
