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

    # Interactive input for transaction ID and secret
    print("\nPlease provide the Monero transaction details:")

    while True:
        try:
            tx_id_input = input("Enter transaction ID (64 hex characters): ").strip()
            if len(tx_id_input) != 64:
                print("Error: Transaction ID must be exactly 64 hex characters")
                continue
            tx_id = bytes.fromhex(tx_id_input)
            break
        except ValueError:
            print(
                "Error: Invalid hex format. Please enter only hex characters (0-9, a-f)"
            )

    while True:
        try:
            tx_secret_input = input(
                "Enter transaction secret/key (64 hex characters): "
            ).strip()
            if len(tx_secret_input) != 64:
                print("Error: Transaction secret must be exactly 64 hex characters")
                continue
            tx_secret = bytes.fromhex(tx_secret_input)
            break
        except ValueError:
            print(
                "Error: Invalid hex format. Please enter only hex characters (0-9, a-f)"
            )

    # Optional: ask for receiver address (default to current account)
    receiver_input = input(
        f"Enter receiver address (default: {account.address}): "
    ).strip()
    if receiver_input:
        try:
            receiver = w3.to_checksum_address(receiver_input)
        except ValueError:
            print(f"Invalid address format, using default: {account.address}")
            receiver = account.address
    else:
        receiver = account.address

    logger.info("Using txId: %s", tx_id.hex())
    logger.info("Using txSecret: %s", tx_secret.hex())
    logger.info("Receiver address: %s", receiver)

    # Check if this request already exists
    try:
        existing_receiver = contract.functions.mintRequestReceiver(tx_secret).call()
        if existing_receiver != "0x0000000000000000000000000000000000000000":
            logger.error("Error: A mint request with this secret already exists!")
            logger.error("Existing receiver: %s", existing_receiver)
            return
    except Exception as e:
        logger.warning("Could not check existing request: %s", e)

    # Estimate gas first
    try:
        estimated_gas = contract.functions.requestMint(
            tx_id,  # bytes32 txId
            tx_secret,  # bytes32 txSecret
            receiver,  # address receiver
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
        receiver,  # address receiver
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
            print(f"\n✅ Mint request submitted successfully!")
            print(f"Transaction hash: {tx_hash.hex()}")
            print(f"Block number: {receipt['blockNumber']}")
        else:
            logger.error(
                "Transaction %s failed with status %d", tx_hash.hex(), receipt["status"]
            )
            print(f"\n❌ Transaction failed!")
    except Exception as e:
        logger.error(
            "Error waiting for transaction %s confirmation: %s", tx_hash.hex(), e
        )
        print(f"\n⚠️  Transaction sent but confirmation failed: {e}")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    request_mint()
