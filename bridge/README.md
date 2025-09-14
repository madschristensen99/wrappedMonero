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

Change to the `bridge/` directory inside this repository. Here, you need
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

- Set `ETH_PRIVATE_KEY` to match the private key of the wrapped Monero mint authority's
address
- Set `XMR_RECEIVE_ADDRESS` to match a Monero receive address that the Monero mint
  authority owns
- Set `W_XMR_CONTRACT_ADDRESS` to match the Wrapped Monero smart contract's
  address

Configure the Monero RPC Api by editing the `bin/monero-rpc` file. Change the
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
uv ./main.py
```


# Monero operations

## Check whether a monero transaction exists and has been confirmed

From: <https://docs.getmonero.org/rpc-library/wallet-rpc/#check_tx_key>

check_tx_key¶

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
- Monery python: <https://monero-python.readthedocs.io/en/latest/quickstart.html>
