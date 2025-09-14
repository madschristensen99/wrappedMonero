#!/usr/bin/env -S uv run
"""
XMR to wXMR Bridge

This bridge has two main functions:

1. Mint wXMR and accepting XMR when receiving wXMR mint requests
2. Burn wXMR and transfer XMR to receiver address when receiving wXMR burn request.

   -------->NETWORK VIEW<-----------

     .------------.               .--------.
     |XMR Stagenet|               |Ethereum|
     .------+-----.               |Sepolia |
            |                     .-----+--.
            |                           |
        .---+----.                .-----+-------.
        |XMR Node|    .-----------+Ethereum Node|
        .---+----.    |           .-------------.
            |         |
        .---+--.      |
        |Bridge+------+
        .------.

     ----->LOGICAL VIEW (mint)<------------


                          (1) Send XMR
                      .------------------.
                      v                  |
                  .------.             .-------------.
            .-----+Bridge|     .-------+XMR Depositor|
            |     .------.     |       .-------------.
            |           ^      |
       (4)  |      (3)  |      |
      Mint  |  Request  |      | (2) Request
      wXMR  |     Mint  |      |     Mint
            |    Event  |      |
            |           |      |
            |           |      |
            |           |      |
            |           |      v
            |    .----+---------.
            .--->|wXMR Contract |      wXMR holder
                 .--------------.

     ----->LOGICAL VIEW (burn)<------------


                          (4) Send XMR
                      .------------------.
                      |                  v
                  .------.             .-------------.
            .-----+Bridge|     .-------+XMR Depositor|
            |     .------.     |       .-------------.
            |           ^      |
       (3)  |      (2)  |      |
      Burn  |  Request  |      | (1) Request
      wXMR  |     Burn  |      |     Burn
            |    Event  |      |
            |           |      |
            |           |      |
            |           |      |
            |           |      v
            |    .----+---------.
            .--->|wXMR Contract |      wXMR holder
                 .--------------.

---->Description of minting algorithm<----

For minting transactions, we distinguish between the following mint requests:

1. Mint requests with no matching XMR deposit
2. Mint requests with a matching XMR deposit
3. Mint requests that the bridge has already minted wXMR for

To avoid querying the state of the Ethereum (or EVM) node for event logs
continuously, the bridge caches mint requests. In the code, their variable name
is `pending_mint_requests`. Mint requests that the bridge pulls out of the event
logs are `log_requests`.

Once the bridge has handled a request, it puts these in a separate cache and
in a variable called `processed_requests`. All the bridge has to do then is
to filter out mint requests with no matching XMR deposit and those
that it has already minted wXMR for. It puts these new requests in a variable
called `confirmed_requests`.

Once these mint requests have their matching wXMR minted, these fully
processed mint requests then move to `minted_requests`. Finally, the bridge
updates its minimimum block height for EVM event logs to match the
most recently handled event log's block height. Doing so, the bridge avoids
fetching old event logs.

Interesting edge cases not handled:

1. Any crash while handling mint requests before marking them as `minted`.
2. Accidentally handling the same mint request twice
3. Running out of gas
4. Miscalculation of required gas and gas limit

The wXMR contract prevents the bridge from minting wXMR for the same request
twice. Every `confirmMint` (the ABI function name for fulfilling a mint request)
requires the bridge to pass the XMR transaction secret. Once the bridge
confirms the mint, the wXMR marks this particular mint request as done.
If the bridge then tries to confirm this mint a second time, the transaction
will revert.

This may lead to the bridge wasting gas fees on a transaction that does not
do anything productive.
"""
import json
from dataclasses import dataclass
import asyncio
from typing import Any, Optional, Union, NewType, TypedDict
from pathlib import Path
import requests
from requests.auth import HTTPDigestAuth

from eth_typing import HexAddress, HexStr
from eth_typing.evm import ChecksumAddress as EvmAddress
from web3 import Web3
import logging

from web3.eth import Contract
from web3.types import TxParams, Wei

from lib import (
    ETH_PRIVATE_KEY,
    XMR_RECEIVE_ADDRESS,
    W_XMR_CONTRACT_ADDRESS,
    EVM_SEPOLIA_API,
    EVM_REQUIRED_CONFIRMATIONS,
    MONERO_STAGENET_API,
    MONERO_REQUIRED_CONFIRMATIONS,
    GAS_BUFFER_MULTIPLIER,
    XmrAddress,
)

logger = logging.getLogger(__name__)

# Monero types
XmrTxId = NewType("XmrTxId", bytes)
XmrTxKey = NewType("XmrTxKey", bytes)
XmrAmount = NewType("XmrAmount", int)

# Ethereum types
EvmHeight = NewType("EvmHeight", int)


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
class WXmrBurnRequest:
    """Contains the information needed to process a wXMR burn."""

    user_address: EvmAddress
    amount: XmrAmount
    xmr_destination: XmrAddress
    evm_height: EvmHeight
    # Transaction hash of the burn event for tracking
    burn_tx_hash: str


@dataclass(kw_only=True, frozen=True)
class ProcessedXmrBurnRequest:
    """Contains the information about a processed XMR burn request."""

    burn_tx_hash: str
    user_address: EvmAddress
    amount: XmrAmount
    xmr_destination: XmrAddress
    # The XMR transaction ID that was sent
    xmr_tx_id: Optional[XmrTxId]


@dataclass(kw_only=True, frozen=True)
class PendingXmrBurnRequest:
    """Contains a burn request that is pending XMR transfer."""

    burn_request: WXmrBurnRequest
    # Optional: track attempts and failures
    attempts: int = 0
    last_error: Optional[str] = None


@dataclass(kw_only=True, frozen=True)
class ConfirmedXmrMintRequest:
    """Contains a mint request with confirmed XMR transaction."""

    mint_request: WXmrMintRequest
    xmr_confirmed: XmrConfirmed


@dataclass(kw_only=True, frozen=True)
class MoneroRpcError:
    """Represents an error from the Monero RPC API."""

    error_code: Optional[int]
    error_message: str


@dataclass(kw_only=True, frozen=True)
class ProcessedXmrMintRequest:
    """Contains the information about a processed XMR mint request."""

    transaction_id: XmrTxId
    transaction_secret: XmrTxKey


@dataclass(kw_only=True, frozen=True)
class PendingXmrMintRequest:
    """Contains a mint request with pending XMR transaction."""

    mint_request: WXmrMintRequest
    xmr_pending: XmrPending


class ProcessedRequestDict(TypedDict):
    """TypedDict for serializing processed requests to JSON."""

    transaction_id: str
    transaction_secret: str


class PendingRequestDict(TypedDict):
    """TypedDict for serializing pending requests to JSON."""

    transaction_id: str
    transaction_secret: str
    receiver: str
    evm_height: int
    confirmations: int


class ProcessedBurnDict(TypedDict):
    """TypedDict for serializing processed burn requests to JSON."""

    burn_tx_hash: str
    user_address: str
    amount: int
    xmr_destination: str
    xmr_tx_id: Optional[str]
    processed_at: str  # ISO timestamp


class PendingBurnRequestDict(TypedDict):
    """TypedDict for serializing pending burn requests to JSON."""

    burn_tx_hash: str
    user_address: str
    amount: int
    xmr_destination: str
    evm_height: int
    attempts: int
    last_error: Optional[str]


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


def call_monero_rpc(
    method: str, params: Optional[dict[str, Any]] = None
) -> Union[dict[str, Any], MoneroRpcError]:
    """Make a JSON-RPC call to the Monero wallet RPC API."""
    payload: dict[str, Any] = {
        "jsonrpc": "2.0",
        "id": "0",
        "method": method,
    }

    if params:
        payload["params"] = params

    response = requests.post(
        MONERO_STAGENET_API + "/json_rpc",
        json=payload,
        headers={"Content-Type": "application/json"},
        auth=HTTPDigestAuth("monero", "rpcPassword"),
        timeout=10,
    )
    if not response.ok:
        logger.error("Monero RPC request failed")
        return MoneroRpcError(error_code=None, error_message=response.text)

    try:
        response_json = response.json()
    except ValueError as e:
        logger.error("Failed to parse Monero RPC response as JSON: %s", e)
        return MoneroRpcError(
            error_code=None, error_message=f"Invalid JSON response: {e}"
        )

    if "error" in response_json:
        error = response_json["error"]
        error_code = error.get("code") if isinstance(error, dict) else None
        error_message = (
            error.get("message", str(error)) if isinstance(error, dict) else str(error)
        )
        logger.error("Monero RPC error: %s", error_message)
        return MoneroRpcError(error_code=error_code, error_message=error_message)

    result: dict[str, Any] = response_json["result"]
    return result


def test_monero_rpc_connection() -> None:
    """Test the Monero RPC connection by calling get_version."""
    logger.info("Testing Monero RPC connection...")

    result = call_monero_rpc("get_version")

    match result:
        case MoneroRpcError() as error:
            logger.error("Failed to connect to Monero RPC: %s", error.error_message)
            raise RuntimeError(f"Monero RPC connection failed: {error.error_message}")
        case dict() as data:
            version = data["version"]
            major = version >> 16
            minor = version & 0xFFFF
            logger.info(
                "Monero RPC connection to %s successful. Version: %d.%d",
                MONERO_STAGENET_API,
                major,
                minor,
            )
        case _:
            raise RuntimeError("Unexpected response type from Monero RPC")


# https://docs.getmonero.org/rpc-library/wallet-rpc/#check_tx_key
def check_xmr_tx_key(
    txid: XmrTxId, address: XmrAddress, tx_key: XmrTxKey
) -> XmrTxState:
    """Check a Monero transaction key using the wallet RPC API."""
    params = {"txid": txid.hex(), "tx_key": tx_key.hex(), "address": address}

    logger.info("Checking XMR tx %s", txid)

    result = call_monero_rpc("check_tx_key", params)

    match result:
        case MoneroRpcError():
            return XmrNotFound(txid=txid, address=address, tx_key=tx_key)
        case dict() as data:
            confirmations = data["confirmations"]
            in_pool: bool = data["in_pool"]
            received = XmrAmount(data["received"])

            enough_confirmations: bool = confirmations >= MONERO_REQUIRED_CONFIRMATIONS
            match in_pool, enough_confirmations:
                case True, _:
                    return XmrPending(
                        txid=txid,
                        tx_key=tx_key,
                        address=address,
                        confirmations=confirmations,
                    )
                case _, True:
                    return XmrConfirmed(
                        txid=txid,
                        tx_key=tx_key,
                        address=address,
                        confirmations=confirmations,
                        received=received,
                    )
                case _, _:
                    return XmrPending(
                        txid=txid,
                        tx_key=tx_key,
                        address=address,
                        confirmations=confirmations,
                    )


def match_mint_request(request: WXmrMintRequest) -> Optional[XmrConfirmed]:
    """For an EVM mint req, find matching xmr tx."""
    state = check_xmr_tx_key(request.txid, XMR_RECEIVE_ADDRESS, request.tx_key)

    match state:
        case XmrConfirmed() if state.confirmations >= MONERO_REQUIRED_CONFIRMATIONS:
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


def get_pending_requests() -> set[PendingXmrMintRequest]:
    """Get the set of pending XMR mint requests."""
    data_file = Path("data/pending_requests.json")

    if not data_file.exists():
        return set()

    data: list[PendingRequestDict] = json.loads(data_file.read_text())
    pending = set()
    for item in data:
        mint_request = WXmrMintRequest(
            txid=XmrTxId(bytes.fromhex(item["transaction_id"])),
            tx_key=XmrTxKey(bytes.fromhex(item["transaction_secret"])),
            receiver=EvmAddress(HexAddress(HexStr(item["receiver"]))),
            evm_height=EvmHeight(item["evm_height"]),
        )
        xmr_pending = XmrPending(
            txid=XmrTxId(bytes.fromhex(item["transaction_id"])),
            tx_key=XmrTxKey(bytes.fromhex(item["transaction_secret"])),
            address=XMR_RECEIVE_ADDRESS,
            confirmations=item["confirmations"],
        )
        pending.add(
            PendingXmrMintRequest(mint_request=mint_request, xmr_pending=xmr_pending)
        )

    return pending


def add_pending_request(pending_request: PendingXmrMintRequest) -> None:
    """Add a pending XMR mint request to the tracking file."""
    data_file = Path("data/pending_requests.json")

    # Create directory if it doesn't exist
    data_file.parent.mkdir(exist_ok=True)

    # Load existing data or create empty list
    if data_file.exists():
        data: list[PendingRequestDict] = json.loads(data_file.read_text())
    else:
        data = []

    # Add new request if not already present
    new_request: PendingRequestDict = {
        "transaction_id": pending_request.mint_request.txid.hex(),
        "transaction_secret": pending_request.mint_request.tx_key.hex(),
        "receiver": pending_request.mint_request.receiver,
        "evm_height": pending_request.mint_request.evm_height,
        "confirmations": pending_request.xmr_pending.confirmations,
    }

    # Check if request already exists (by txid and tx_key)
    existing = any(
        item["transaction_id"] == new_request["transaction_id"]
        and item["transaction_secret"] == new_request["transaction_secret"]
        for item in data
    )

    if not existing:
        data.append(new_request)
        data_file.write_text(json.dumps(data, indent=2))


def remove_pending_request(pending_request: PendingXmrMintRequest) -> None:
    """Remove a pending XMR mint request from the tracking file."""
    data_file = Path("data/pending_requests.json")

    if not data_file.exists():
        return

    data: list[PendingRequestDict] = json.loads(data_file.read_text())

    # Remove the request
    data = [
        item
        for item in data
        if not (
            item["transaction_id"] == pending_request.mint_request.txid.hex()
            and item["transaction_secret"] == pending_request.mint_request.tx_key.hex()
        )
    ]

    data_file.write_text(json.dumps(data, indent=2))


def get_processed_burn_requests() -> set[ProcessedXmrBurnRequest]:
    """Get the set of already processed XMR burn requests."""
    data_file = Path("data/processed_burns.json")

    if not data_file.exists():
        return set()

    data: list[ProcessedBurnDict] = json.loads(data_file.read_text())
    processed = set()
    for item in data:
        xmr_tx_id = XmrTxId(bytes.fromhex(item["xmr_tx_id"])) if item["xmr_tx_id"] else None
        processed.add(
            ProcessedXmrBurnRequest(
                burn_tx_hash=item["burn_tx_hash"],
                user_address=EvmAddress(HexAddress(HexStr(item["user_address"]))),
                amount=XmrAmount(item["amount"]),
                xmr_destination=XmrAddress(item["xmr_destination"]),
                xmr_tx_id=xmr_tx_id,
            )
        )

    return processed


def add_processed_burn_request(processed_request: ProcessedXmrBurnRequest) -> None:
    """Add a processed XMR burn request to the tracking file."""
    from datetime import datetime

    data_file = Path("data/processed_burns.json")

    # Create directory if it doesn't exist
    data_file.parent.mkdir(exist_ok=True)

    # Load existing data or create empty list
    if data_file.exists():
        data: list[ProcessedBurnDict] = json.loads(data_file.read_text())
    else:
        data = []

    # Add new request if not already present
    new_request: ProcessedBurnDict = {
        "burn_tx_hash": processed_request.burn_tx_hash,
        "user_address": processed_request.user_address,
        "amount": processed_request.amount,
        "xmr_destination": processed_request.xmr_destination,
        "xmr_tx_id": processed_request.xmr_tx_id.hex() if processed_request.xmr_tx_id else None,
        "processed_at": datetime.utcnow().isoformat(),
    }

    # Check if request already exists (by burn_tx_hash)
    existing = any(item["burn_tx_hash"] == new_request["burn_tx_hash"] for item in data)

    if not existing:
        data.append(new_request)
        data_file.write_text(json.dumps(data, indent=2))


def get_pending_burn_requests() -> set[PendingXmrBurnRequest]:
    """Get the set of pending XMR burn requests."""
    data_file = Path("data/pending_burn_requests.json")

    if not data_file.exists():
        return set()

    data: list[PendingBurnRequestDict] = json.loads(data_file.read_text())
    pending = set()
    for item in data:
        burn_request = WXmrBurnRequest(
            user_address=EvmAddress(HexAddress(HexStr(item["user_address"]))),
            amount=XmrAmount(item["amount"]),
            xmr_destination=XmrAddress(item["xmr_destination"]),
            evm_height=EvmHeight(item["evm_height"]),
            burn_tx_hash=item["burn_tx_hash"],
        )
        pending.add(
            PendingXmrBurnRequest(
                burn_request=burn_request,
                attempts=item["attempts"],
                last_error=item["last_error"],
            )
        )

    return pending


def add_pending_burn_request(pending_request: PendingXmrBurnRequest) -> None:
    """Add a pending XMR burn request to the tracking file."""
    data_file = Path("data/pending_burn_requests.json")

    # Create directory if it doesn't exist
    data_file.parent.mkdir(exist_ok=True)

    # Load existing data or create empty list
    if data_file.exists():
        data: list[PendingBurnRequestDict] = json.loads(data_file.read_text())
    else:
        data = []

    # Add new request if not already present
    new_request: PendingBurnRequestDict = {
        "burn_tx_hash": pending_request.burn_request.burn_tx_hash,
        "user_address": pending_request.burn_request.user_address,
        "amount": pending_request.burn_request.amount,
        "xmr_destination": pending_request.burn_request.xmr_destination,
        "evm_height": pending_request.burn_request.evm_height,
        "attempts": pending_request.attempts,
        "last_error": pending_request.last_error,
    }

    # Check if request already exists (by burn_tx_hash)
    existing = any(item["burn_tx_hash"] == new_request["burn_tx_hash"] for item in data)

    if not existing:
        data.append(new_request)
        data_file.write_text(json.dumps(data, indent=2))


def remove_pending_burn_request(pending_request: PendingXmrBurnRequest) -> None:
    """Remove a pending XMR burn request from the tracking file."""
    data_file = Path("data/pending_burn_requests.json")

    if not data_file.exists():
        return

    data: list[PendingBurnRequestDict] = json.loads(data_file.read_text())

    # Remove the request
    data = [
        item
        for item in data
        if item["burn_tx_hash"] != pending_request.burn_request.burn_tx_hash
    ]

    data_file.write_text(json.dumps(data, indent=2))


def mint_w_xmr(
    contract: Contract, w3: Web3, amount: XmrAmount, tx_secret: XmrTxKey
) -> None:
    """Call the confirmMint function on the wXMR contract."""
    # Get account from private key
    account = w3.eth.account.from_key(ETH_PRIVATE_KEY)

    # Log the parameters being passed to confirmMint
    logger.info(
        "Calling confirmMint with tx_secret: %s, amount: %d",
        tx_secret.hex(),
        int(amount),
    )

    # Estimate gas first
    estimated_gas = contract.functions.confirmMint(
        tx_secret,  # Convert to bytes32
        int(amount),  # Convert to uint64
    ).estimate_gas({"from": account.address})
    gas_limit = int(estimated_gas * GAS_BUFFER_MULTIPLIER)
    logger.info("Estimated gas: %d, using limit: %d", estimated_gas, gas_limit)

    # Calculate proper fee structure for London transaction
    base_fee = w3.eth.gas_price
    priority_fee = w3.to_wei(2, "gwei")
    max_fee = Wei(max(base_fee * 2, priority_fee + base_fee))

    # Build transaction
    params: TxParams = {
        "from": account.address,
        "nonce": w3.eth.get_transaction_count(account.address),
        "gas": gas_limit,
        "maxFeePerGas": max_fee,  # London transaction
        "maxPriorityFeePerGas": priority_fee,  # Priority fee
    }
    tx = contract.functions.confirmMint(
        tx_secret,  # Convert to bytes32
        int(amount),  # Convert to uint64
    ).build_transaction(params)

    # Sign and send transaction
    signed_tx = w3.eth.account.sign_transaction(tx, ETH_PRIVATE_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed_tx.raw_transaction)

    logger.info("Sent confirmMint transaction: %s", tx_hash.hex())

    # Wait for transaction confirmation
    try:
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        match receipt["status"]:
            case 1:
                logger.info(
                    "Transaction %s confirmed successfully in block %d",
                    tx_hash.hex(),
                    receipt["blockNumber"],
                )
            case _:
                logger.error(
                    "Transaction %s failed with status %d",
                    tx_hash.hex(),
                    receipt["status"],
                )
    except Exception as e:
        logger.error(
            "Error waiting for transaction %s confirmation: %s", tx_hash.hex(), e
        )


def process_revealed_txs(contract: Contract, w3: Web3) -> None:
    # 1. Calculate the confirmed block height (current - required confirmations)
    current_block = contract.w3.eth.block_number
    confirmed_block = EvmHeight(max(0, current_block - EVM_REQUIRED_CONFIRMATIONS))

    # 2. Go over list of mint requests on EVM,
    min_block_height = get_min_block_height(w3)
    log_requests = get_mint_requests(contract, min_block_height, confirmed_block)

    # 2b. Get pending requests and convert them to WXmrMintRequest format
    pending_requests = get_pending_requests()
    pending_mint_requests = [pending.mint_request for pending in pending_requests]

    # 2c. Concatenate log requests and pending requests
    new_requests = log_requests + pending_mint_requests

    # 3. Check for which revealed txs we already minted wXMR, filter them out
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
        "Found %d unprocessed mint requests out of %d total (%d from logs, %d from pending)",
        len(unprocessed_requests),
        len(new_requests),
        len(log_requests),
        len(pending_mint_requests),
    )

    # 4. For each remaining request, check XMR transaction state
    confirmed_requests: list[ConfirmedXmrMintRequest] = []
    for request in unprocessed_requests:
        state = check_xmr_tx_key(request.txid, XMR_RECEIVE_ADDRESS, request.tx_key)

        match state:
            case XmrConfirmed() if state.confirmations >= MONERO_REQUIRED_CONFIRMATIONS:
                # Transaction is confirmed, process immediately
                confirmed_requests.append(
                    ConfirmedXmrMintRequest(mint_request=request, xmr_confirmed=state)
                )
                # If this was from pending requests, remove it from pending
                for pending_request in pending_requests:
                    if (
                        pending_request.mint_request.txid == request.txid
                        and pending_request.mint_request.tx_key == request.tx_key
                    ):
                        remove_pending_request(pending_request)
                        break
            case XmrPending():
                # Transaction is pending, add to pending queue (if not already there)
                is_already_pending = any(
                    pending.mint_request.txid == request.txid
                    and pending.mint_request.tx_key == request.tx_key
                    for pending in pending_requests
                )
                if not is_already_pending:
                    pending_request = PendingXmrMintRequest(
                        mint_request=request, xmr_pending=state
                    )
                    add_pending_request(pending_request)
                    logger.info(
                        "Added pending request %s with %d confirmations",
                        request.txid.hex(),
                        state.confirmations,
                    )
                else:
                    logger.info(
                        "Pending request %s with %d confirmations is already pending",
                        request.txid.hex(),
                        state.confirmations,
                    )
            case XmrNotFound():
                # Transaction not found, remove from pending if it was there
                for pending_request in pending_requests:
                    if (
                        pending_request.mint_request.txid == request.txid
                        and pending_request.mint_request.tx_key == request.tx_key
                    ):
                        remove_pending_request(pending_request)
                        break
                logger.warning(
                    "XMR transaction %s not found for mint request", request.txid.hex()
                )

    logger.info("Found %d confirmed XMR mint requests", len(confirmed_requests))

    # 5. Send a mint transaction to the wXMR
    #    contract with the matching amount of wXMR to the receive address
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
        mint_w_xmr(
            contract,
            w3,
            confirmed_request.xmr_confirmed.received,
            confirmed_request.mint_request.tx_key,
        )
        processed_request = ProcessedXmrMintRequest(
            transaction_id=confirmed_request.mint_request.txid,
            transaction_secret=confirmed_request.mint_request.tx_key,
        )
        minted_requests.add(processed_request)

    # 6. Mark minted requests as processed
    for minted_request in minted_requests:
        add_processed_request(minted_request)

    # 7. Store the confirmed block height as the new last_checked
    set_min_block_height(confirmed_block)


def process_burn_requests(contract: Contract, w3: Web3) -> None:
    """Process burn requests from the wXMR contract and send XMR to users."""
    # TODO: This function will be implemented once the burn event is added to the contract
    # For now, just log that it's being called
    logger.debug("Processing burn requests (not yet implemented)")

    # When implemented, this function will:
    # 1. Get burn events from the contract logs
    # 2. Filter out already processed burns
    # 3. Attempt to send XMR to the destination addresses
    # 4. Track successful and failed transfers
    # 5. Retry failed transfers with exponential backoff


async def main() -> None:
    logging.basicConfig(level=logging.INFO)

    # Test Monero RPC connection first
    test_monero_rpc_connection()

    w3 = Web3(Web3.HTTPProvider(EVM_SEPOLIA_API))
    assert w3.is_connected()
    logger.info("Connected to EVM api at %s", EVM_SEPOLIA_API)

    w_xmr_contract: Contract = w3.eth.contract(
        address=W_XMR_CONTRACT_ADDRESS, abi=w_xmr_contract_abi
    )

    # Get account address for balance checking
    account = w3.eth.account.from_key(ETH_PRIVATE_KEY)
    logger.info("Using Ethereum address: %s", account.address)

    while True:
        # Check ETH balance
        balance_wei = w3.eth.get_balance(account.address)
        balance_eth = w3.from_wei(balance_wei, "ether")
        logger.info("Current ETH balance: %s ETH", balance_eth)

        process_revealed_txs(w_xmr_contract, w3)
        process_burn_requests(w_xmr_contract, w3)
        await asyncio.sleep(1)


if __name__ == "__main__":
    asyncio.run(main())
