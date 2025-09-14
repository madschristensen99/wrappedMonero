# Wrapped Monero Bridge

This directory contains the bridge program for Wrapped Monero.
It fulfills two roles within Wrapped Monero:

1. It responds to Wrapped Monero mint requests, validates the arrival of
   Monero, and mints new wXMR in the Wrapped Monero contract.
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
- Set `W_XMR_CONTRACT_ADDRESS` to match the wrapped Monero smart contract's
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
