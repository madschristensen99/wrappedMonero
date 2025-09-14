#!/usr/bin/env -S uv run
import json
from dataclasses import dataclass
import os
import asyncio
from typing import Optional, Union, NewType, TypedDict, List, Dict
from pathlib import Path
import requests
import aiohttp
import dotenv

from eth_typing import HexAddress, HexStr
from eth_typing.evm import ChecksumAddress as EvmAddress
from web3 import Web3
import logging
import time

from web3.eth import Contract
from web3.types import TxParams, Wei

from validator_client import DistributedBridgeClient

dotenv.load_dotenv()

logger = logging.getLogger(__name__)

# Monero types
XmrTxId = NewType("XmrTxId", bytes)
XmrTxKey = NewType("XmrTxKey", bytes)
XmrAddress = NewType("XmrAddress", str)
XmrAmount = NewType("XmrAmount", int)

# Ethereum types
EvmHeight = NewType("EvmHeight", int)


# EVM RPC API connection info
# https://chainlist.org/chain/11155111
EVM_SEPOLIA_API = "https://sepolia.gateway.tenderly.co"
# Completely arbitrary
EVM_REQUIRED_CONFIRMATIONS = 1

# monero cli RPC API connection info
# https://monero.fail/?chain=monero&network=stagenet
MONERY_STAGENET_API = "http://stagenet.xmr-tw.org:38081"
# Completely arbitrary
MONERY_REQUIRED_CONFIRMATIONS = 6

ETH_PRIVATE_KEY = os.environ["ETH_PRIVATE_KEY"]


# TODO
XMR_RECEIVE_ADDRESS = XmrAddress(os.environ["XMR_RECEIVE_ADDRESS"])
W_XMR_CONTRACT_ADDRESS = EvmAddress(
    HexAddress(HexStr(os.environ["W_XMR_CONTRACT_ADDRESS"]))
)

# Contract ABI
w_xmr_contract_abi = json.loads(Path("abi.json").read_text())


@dataclass(kw_only=True, frozen=True)
class XmrTxStateBase:
    txid: XmrTxId
    tx_key: XmrTxKey
    address: XmrAddress


@dataclass(kw_only=True, frozen=True)
class XmrNotFound(XmrTxStateBase):
    pass


@dataclass(kw_only=True, frozen=True)
class XmrPending(XmrTxStateBase):
    """Contains all information about a pending XMR tx."""

    confirmations: int


@dataclass(kw_only=True, frozen=True)
class XmrConfirmed(XmrTxStateBase):
    """Contains all information we care about for a confirmed XMR tx."""

    confirmations: int
    received: XmrAmount


@dataclass(kw_only=True, frozen=True)
class WXmrMintRequest:
    """Contains the information needed to mint wXMR."""

    txid: XmrTxId
    tx_key: XmrTxKey
    # Amount is pulled in from the XMR output
    # Who should receive the wXMR?
    receiver: EvmAddress
    # Maybe
    evm_height: EvmHeight


@dataclass(kw_only=True, frozen=True)
class ConfirmedXmrMintRequest:
    """Contains a mint request with confirmed XMR transaction."""

    mint_request: WXmrMintRequest
    xmr_confirmed: XmrConfirmed


@dataclass(kw_only=True, frozen=True)
class ProcessedXmrMintRequest:
    """Contains the information about a processed XMR mint request."""

    transaction_id: XmrTxId
    transaction_secret: XmrTxKey


class ProcessedRequestDict(TypedDict):
    """TypedDict for serializing processed requests to JSON."""

    transaction_id: str
    transaction_secret: str


# event MintRequested(bytes32 indexed txId, bytes32 indexed txSecret, address indexed receiver, uint256 amount);
def get_mint_requests(
    contract: Contract, min_block_height: EvmHeight, confirmed_block: EvmHeight
) -> list[WXmrMintRequest]:
    result: list[WXmrMintRequest] = []

    # 1. Check if we've already processed this confirmed block
    if confirmed_block <= min_block_height:
        logger.debug(
            "Already processed up to block %d, confirmed block is %d",
            min_block_height,
            confirmed_block,
        )
        return result

    # 2. Retrieve list of revealed txs on wXMR contract up to confirmed block
    logger.info(
        "Getting logs for MintRequested() from block %d to %d",
        min_block_height,
        confirmed_block,
    )
    logs = contract.events.MintRequested().get_logs(
        from_block=min_block_height + 1, to_block=confirmed_block
    )
    logger.info("Retrieved %d logs", len(logs))
    for log in logs:
        logger.info("Processing log from block height %d", log.blockNumber)
        # 2a. Extract txSecret
        tx_secret = log.args.txSecret
        # 2b. Extract txId
        txId = log.args.txId
        # 2c. Extract payout receiver address
        receiver = log.args.receiver
        request = WXmrMintRequest(
            tx_key=tx_secret,
            txid=txId,
            receiver=receiver,
            evm_height=EvmHeight(log.blockNumber),
        )
        result.append(request)

    return result


XmrTxState = Union[XmrConfirmed, XmrPending, XmrNotFound]


# https://docs.getmonero.org/rpc-library/wallet-rpc/#check_tx_key
def check_xmr_tx_key(
    txid: XmrTxId, address: XmrAddress, tx_key: XmrTxKey
) -> XmrTxState:
    """Check a Monero transaction key using the wallet RPC API."""
    payload = {
        "jsonrpc": "2.0",
        "id": "0",
        "method": "check_tx_key",
        "params": {"txid": txid.hex(), "tx_key": tx_key.hex(), "address": address},
    }
    logger.info("Checking XMR tx %s", txid)

    response = requests.post(
        MONERY_STAGENET_API + "/json_rpc",
        json=payload,
        headers={"Content-Type": "application/json"},
    )
    response.raise_for_status()

    result = response.json()

    if "error" in result:
        logger.error("Monero RPC error: %s", result["error"])
        return XmrNotFound(txid=txid, address=address, tx_key=tx_key)

    data = result["result"]
    confirmations = data["confirmations"]
    in_pool = data["in_pool"]
    received = XmrAmount(data["received"])

    enough_confirmations = confirmations >= MONERY_REQUIRED_CONFIRMATIONS
    if in_pool:
        return XmrPending(
            txid=txid, tx_key=tx_key, address=address, confirmations=confirmations
        )
    elif enough_confirmations:
        return XmrConfirmed(
            txid=txid,
            tx_key=tx_key,
            address=address,
            confirmations=confirmations,
            received=received,
        )
    else:
        return XmrPending(
            txid=txid, tx_key=tx_key, address=address, confirmations=confirmations
        )


def match_mint_request(request: WXmrMintRequest) -> Optional[XmrConfirmed]:
    """For an EVM mint req, find matching xmr tx."""
    state = check_xmr_tx_key(request.txid, XMR_RECEIVE_ADDRESS, request.tx_key)

    match state:
        case XmrConfirmed() if state.confirmations >= MONERY_REQUIRED_CONFIRMATIONS:
            return state
        case _:
            return None


def get_min_block_height(w3: Web3) -> EvmHeight:
    """Get the minimum block height to check from data/min_block_height.json.

    If the file doesn't exist, create it with the current block height.
    """
    data_file = Path("data/min_block_height.json")

    if data_file.exists():
        data = json.loads(data_file.read_text())
        min_block_height = EvmHeight(data["min_block_height"])
        return min_block_height

    data_file.parent.mkdir(exist_ok=True)
    current_height = EvmHeight(w3.eth.block_number)

    data = {"min_block_height": current_height}
    data_file.write_text(json.dumps(data, indent=2))
    return current_height


def set_min_block_height(block_height: EvmHeight) -> None:
    """Set the minimum block height in data/min_block_height.json.

    If the file doesn't exist, create it with the provided block height.
    """
    data_file = Path("data/min_block_height.json")

    if not data_file.exists():
        data_file.parent.mkdir(exist_ok=True)

    data = {"min_block_height": block_height}
    data_file.write_text(json.dumps(data, indent=2))


def get_processed_requests() -> set[ProcessedXmrMintRequest]:
    """Get the set of already processed XMR mint requests."""
    data_file = Path("data/processed_requests.json")

    if not data_file.exists():
        return set()

    data: list[ProcessedRequestDict] = json.loads(data_file.read_text())
    processed = set()
    for item in data:
        processed.add(
            ProcessedXmrMintRequest(
                transaction_id=XmrTxId(bytes.fromhex(item["transaction_id"])),
                transaction_secret=XmrTxKey(bytes.fromhex(item["transaction_secret"])),
            )
        )

    return processed


def add_processed_request(processed_request: ProcessedXmrMintRequest) -> None:
    """Add a processed XMR mint request to the tracking file."""
    data_file = Path("data/processed_requests.json")

    # Create directory if it doesn't exist
    data_file.parent.mkdir(exist_ok=True)

    # Load existing data or create empty list
    if data_file.exists():
        data: list[ProcessedRequestDict] = json.loads(data_file.read_text())
    else:
        data = []

    # Add new request if not already present
    new_request: ProcessedRequestDict = {
        "transaction_id": processed_request.transaction_id.hex(),
        "transaction_secret": processed_request.transaction_secret.hex(),
    }
    if new_request not in data:
        data.append(new_request)
        data_file.write_text(json.dumps(data, indent=2))


async def mint_w_xmr_THRES_SIGNATURE(
    contract: Contract, w3: Web3, amount: XmrAmount, tx_secret: XmrTxKey
) -> None:
    """Submit threshold-signature based mint confirmation to wXMR contract."""
    # Use decentralized validator client
    validator_urls = [
        "http://localhost:8001",
        "http://localhost:8002", 
        "http://localhost:8003",
        "http://localhost:8004",
        "http://localhost:8005",
        "http://localhost:8006",
        "http://localhost:8007"
    ]
    
    async with DistributedBridgeClient() as client:
        # Submit mint request to validator network
        result = await client.submit_threshold_mint_request(
            tx_secret, 
            int(amount), 
            "0x0000000000000000000000000000000000000000"  # placeholder
        )
        
        if not result:
            logger.error("Insufficient validator signatures for mint request")
            return
            
        logger.info("Got threshold signatures, constructing contract call")
        
        # Get account from private key
        account = w3.eth.account.from_key(ETH_PRIVATE_KEY)
        
        # Construct operation hash for contract verification
        operation_hash = result['operation_hash']
        signature = result['signature']
        
        # Build confirmMintWithSig transaction
        tx = contract.functions.confirmMintWithSig(
            tx_secret,
            int(amount),
            {
                "operationHash": operation_hash,
                "signature": signature,
                "timestamp": result['timestamp'],
                "nonce": result['nonce']
            },
            {
                "r": bytes.fromhex(signature['r']),
                "s": bytes.fromhex(signature['s']),  
                "v": signature['v']
            }
        )
        
        # Estimate and submit transaction
        gas_limit = tx.estimate_gas({"from": account.address})
        tx_hash = w3.eth.send_transaction(tx.build_transaction({
            "from": account.address,
            "gas": int(gas_limit * 1.2),
            "maxFeePerGas": w3.eth.gas_price * 2,
            "maxPriorityFeePerGas": w3.to_wei(2, "gwei"),
            "nonce": w3.eth.get_transaction_count(account.address)
        }))
        
        logger.info("Submitted threshold signature mint: %s", tx_hash.hex())
        
        # Wait for confirmation
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=180)
        if receipt.status == 1:
            logger.info("Threshold signature mint confirmed successfully")
        else:
            logger.error("Threshold signature mint failed")

# Legacy mint function kept for backward compatibility
def mint_w_xmr(
    contract: Contract, w3: Web3, amount: XmrAmount, tx_secret: XmrTxKey
) -> None:
    """Call the legacy confirmMint function (authority-based)."""
    # Old centralized authority approach - kept for migration period
    web3 = w3  
    account = web3.eth.account.from_key(ETH_PRIVATE_KEY)
    
    try:
        tx = contract.functions.confirmMint(tx_secret, int(amount)).send_transaction({
            "from": account.address,
            "gas": 500000,
            "maxFeePerGas": web3.eth.gas_price * 2,
            "nonce": web3.eth.get_transaction_count(account.address)
        })
        
        logger.info("Legacy mint transaction submitted: %s", tx.hex())
        
    except Exception as e:
        logger.error("Legacy mint failed: %s", str(e))

async def mint_w_xmr_threshold(
    contract: Contract, w3: Web3, amount: XmrAmount, tx_secret: XmrTxKey
) -> None:
    """New distributed minting using threshold signatures."""
    await mint_w_xmr_THRES_SIGNATURE(contract, w3, amount, tx_secret)


async def process_revealed_txs(contract: Contract, w3: Web3) -> None:
    # 1. Calculate the confirmed block height (current - required confirmations)
    current_block = contract.w3.eth.block_number
    confirmed_block = EvmHeight(max(0, current_block - EVM_REQUIRED_CONFIRMATIONS))

    # 2. Go over list of mint requests on EVM,
    min_block_height = get_min_block_height(w3)
    new_requests = get_mint_requests(contract, min_block_height, confirmed_block)

    # 2. Check for which revealed txs we already minted wXMR, filter them out
    processed_requests = get_processed_requests()
    processed_tuples = {
        (p.transaction_id, p.transaction_secret) for p in processed_requests
    }
    unprocessed_requests = [
        request
        for request in new_requests
        if (request.txid, request.tx_key) not in processed_tuples
    ]

    logger.info(
        "Found %d unprocessed mint requests out of %d total",
        len(unprocessed_requests),
        len(new_requests),
    )

    # 3. For each remaining address, find the matching, confirmed XMR deposit
    confirmed_requests: list[ConfirmedXmrMintRequest] = []
    for request in unprocessed_requests:
        xmr_confirmed = match_mint_request(request)
        if xmr_confirmed is None:
            continue
        confirmed_requests.append(
            ConfirmedXmrMintRequest(mint_request=request, xmr_confirmed=xmr_confirmed)
        )

    logger.info("Found %d confirmed XMR mint requests", len(confirmed_requests))

    # 4. Initiate threshold signing process with validator network
    minted_requests: set[ProcessedXmrMintRequest] = set()
    for confirmed_request in confirmed_requests:
        # Check if the secret has already been used on the contract
        secret_used = contract.functions.mintSecretUsed(
            confirmed_request.mint_request.tx_key
        ).call()
        if secret_used:
            logger.info(
                "Secret %s already used, skipping mint",
                confirmed_request.mint_request.tx_key.hex(),
            )
            continue

        logger.info("%s", confirmed_request)
        
        # Use new threshold signature approach
        asyncio.create_task(
            mint_w_xmr_threshold(
                contract,
                w3,
                confirmed_request.xmr_confirmed.received,
                confirmed_request.mint_request.tx_key,
            )
        )
        
        processed_request = ProcessedXmrMintRequest(
            transaction_id=confirmed_request.mint_request.txid,
            transaction_secret=confirmed_request.mint_request.tx_key,
        )
        minted_requests.add(processed_request)

    # 5. Mark minted requests as processed
    for minted_request in minted_requests:
        add_processed_request(minted_request)

    # 6. Store the confirmed block height as the new last_checked
    set_min_block_height(confirmed_block)


# TODO burn stuff


async def main() -> None:
    logging.basicConfig(level=logging.INFO)

    w3 = Web3(Web3.HTTPProvider(EVM_SEPOLIA_API))
    assert w3.is_connected()
    logging.info("Connected to EVM api at %s", EVM_SEPOLIA_API)

    w_xmr_contract: Contract = w3.eth.contract(
        address=W_XMR_CONTRACT_ADDRESS, abi=w_xmr_contract_abi
    )

    # Get account address for balance checking
    account = w3.eth.account.from_key(ETH_PRIVATE_KEY)
    logger.info("Using Ethereum address: %s", account.address)
    
    # Initialize distributed bridge client
    bridge_client = DistributedBridgeClient("./validator_urls.json")

    while True:
        # Check ETH balance
        balance_wei = w3.eth.get_balance(account.address)
        balance_eth = w3.from_wei(balance_wei, "ether")
        logger.info("Current ETH balance: %s ETH", balance_eth)

        await process_revealed_txs(w_xmr_contract, w3)
        await asyncio.sleep(10)  # Increased interval for validator coordination


if __name__ == "__main__":
    asyncio.run(main())
