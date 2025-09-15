# Wrapped Monero Bridge

This directory contains the bridge program for Wrapped Monero.
It fulfills two roles within Wrapped Monero:

1. It responds to Wrapped Monero mint requests, validates the arrival of
   Monero, and mints new WXMR in the Wrapped Monero contract.
2. It responds to Wrapped Monero burn requests, removes Wrapped Monero from
circulation, and transfers XMR to the requested Monero address.

## How to run

This section explains how to run the bridge program.

Make sure that you have installed the Monero client and that the following
commands are available in your terminal:

- `monero-wallet-cli`
- `monero-wallet-rpc`

Change to the `bridge/` directory inside this repository. Here, you need to
install all dependencies with [uv](https://docs.astral.sh/uv/):

```bash
# Change to the bridge directory inside the repository
cd bridge/
uv sync
```

Create the `.env` file from `.env.template`:

```bash
cp .env.template .env
```

Populate the values inside `.env`:

- Set `ETH_PRIVATE_KEY` to match the private key of the Wrapped Monero mint authority's
  address
- Set `XMR_RECEIVE_ADDRESS` to match a Monero receive address that the Monero mint
  authority owns
- Set `W_XMR_CONTRACT_ADDRESS` to match the Wrapped Monero smart contract's
  address

Configure the Monero RPC API by editing the `bin/monero-rpc` file. Change the
following line and make sure that it contains a path to a valid Monero wallet:

```patch
-wallet_file=$HOME/Monero/wallets/wallet_3
+wallet_file=PATH_TO_WHERE_YOU_PUT_YOUR_WALLET
```

Make sure to save the contents of this file.
`bin/monero-rpc` expects your wallet to have an empty password.

**Note**: You should only run this on
stagenet and with funds and private key material that you can afford to lose or accidentally disclose to the public.

In a new terminal, start the Monero RPC API by running the following command
inside the `bridge/` directory:

```bash
# Make sure you head into the bridge directory
cd bridge
bin/monero-rpc
```

Then, run the bridge with the following command:

```bash
uv run ./main.py
```

# Technical Description

## Network View

```
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
```

## Logical View (mint)

```
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
   WXMR  |     Mint  |      |     Mint
         |    Event  |      |
         |           |      |
         |           |      |
         |           |      |
         |           |      v
         |    .----+---------.
         .--->|WXMR Contract |      WXMR holder
              .--------------.
```

## Logical View (burn)

```
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
   WXMR  |     Burn  |      |     Burn
         |    Event  |      |
         |           |      |
         |           |      |
         |           |      |
         |           |      v
         |    .----+---------.
         .--->|WXMR Contract |      WXMR holder
              .--------------.
```

## Minting algorithm

For minting transactions, we distinguish between the following mint requests:

1. Mint requests with no matching XMR deposit
2. Mint requests with a matching XMR deposit
3. Mint requests that the bridge has already minted WXMR for

To avoid querying the state of the Ethereum (or EVM) node for event logs
continuously, the bridge caches mint requests. In the code, their variable name
is pending_mint_requests. Mint requests that the bridge pulls out of the event
logs are log_requests.

Once the bridge has handled a request, it puts these in a separate cache and
in a variable called processed_requests. All the bridge has to do then is
to filter out mint requests with no matching XMR deposit and those
that it has already minted WXMR for. It puts these new requests in a variable
called confirmed_requests.

Once these mint requests have their matching WXMR minted, these fully
processed mint requests then move to minted_requests. Finally, the bridge
updates its minimimum block height for EVM event logs to match the
most recently handled event log's block height. Doing so, the bridge avoids
fetching old event logs.

### Interesting edge cases not handled

1. Any crash while handling mint requests before marking them as minted.
2. Accidentally handling the same mint request twice
3. Running out of gas
4. Miscalculation of required gas and gas limit

The WXMR contract prevents the bridge from minting WXMR for the same request
twice. Every confirmMint (the ABI function name for fulfilling a mint request)
requires the bridge to pass the XMR transaction secret. Once the bridge
confirms the mint, the WXMR marks this particular mint request as done.
If the bridge then tries to confirm this mint a second time, the transaction
will revert.

This may lead to the bridge wasting gas fees on a transaction that does not
do anything productive.

# Monero operations

## Check whether a Monero transaction exists and has been confirmed

From: <https://docs.getmonero.org/rpc-library/wallet-rpc/#check_tx_key>

check_tx_key

Check a transaction in the blockchain with its secret key.

Alias: None.

Inputs:

- txid - string; transaction id.
- tx_key - string; transaction secret key.
- address - string; destination public address of the transaction.

Outputs:

- confirmations - unsigned int; Number of block mined after the one with the transaction.
- in_pool - boolean; States if the transaction is still in pool or has been added to a block.
- received - unsigned int; Amount of the transaction.

Example:

```bash
curl -X POST http://127.0.0.1:18088/json_rpc -d \
    '{"jsonrpc":"2.0","id":"0","method":"check_tx_key","params":{"txid":"19d5089f9469db3d90aca9024dfcb17ce94b948300101c8345a5e9f7257353be","tx_key":"feba662cf8fb6d0d0da18fc9b70ab28e01cc76311278fdd7fe7ab16360762b06","address":"7BnERTpvL5MbCLtj5n9No7J5oE5hHiB3tVCK5cjSvCsYWD2WRJLFuWeKTLiXo5QJqt2ZwUaLy2Vh1Ad51K7FNgqcHgjW85o"}}' -H 'Content-Type: application/json'

```json
{
  "id": "0",
  "jsonrpc": "2.0",
  "result": {
    "confirmations": 0,
    "in_pool": false,
    "received": 1000000000000
  }
}
```

# Docs

- Ethereum web3py: <https://web3py.readthedocs.io/en/stable/transactions.html>
- Monero python: <https://monero-python.readthedocs.io/en/latest/quickstart.html>
