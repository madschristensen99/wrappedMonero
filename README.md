# Wrapped Monero (WXMR)

A privacy-focused bridge between Monero (XMR) and Ethereum, featuring encrypted balances using Fhenix's Fully Homomorphic Encryption (FHE).

## Overview

WXMR (Wrapped Monero) is a privacy-preserving ERC20 token that represents Monero on Ethereum. Key features:

- **Encrypted Balances**: All token balances are encrypted using Fhenix FHE, ensuring privacy on-chain
- **Trustless Bridge**: Two-step minting process with cryptographic verification of Monero transactions
- **User-Friendly Interface**: Modern web interface for interacting with the WXMR token

## Architecture

The system consists of three main components:

1. **Smart Contract** (`contract/wxMR.sol`)
   - ERC20-compatible token with encrypted balances
   - Two-step minting process for bridging XMR
   - Authority-controlled minting and burning
   - FHE-powered private transfers

2. **Bridge Service** (`bridge/`)
   - Monitors Monero network for incoming transactions
   - Verifies XMR deposits using transaction keys
   - Automatically mints WXMR tokens upon confirmation
   - Python-based service using Monero RPC

3. **Frontend** (`frontend/`)
   - Web interface for token operations
   - MetaMask integration
   - Transfer, mint, and burn functionality
   - Real-time balance updates
   -
 ## Deployed Contract Address
[0x25305b62299562197582eB87443B64B894685Fb4](https://sepolia.etherscan.io/address/0x25305b62299562197582eB87443B64B894685Fb4)

## Usage

### How to demo

Here's how to set up everything

1. Install dependencies for bridge  by running `uv sync` inside
   the `bridge/` directory.
2. Install dependencies for the frontend by running `npm i` inside
   the `frontend/` directory
3. Install the monero cli tools and make sure that you have the
   `monero-wallet-rpc` program available in your terminal.
4. Create a Monero wallet that receives the XMR to be wrapped and make sure
   that it's available in a directory that `monero-wallet-rpc` can access

Here's how to start up everything

1. Start the monero wallet rpc endpoint by running `bridge/bin/monero-cli`
1. Start bridge by running `uv run ./main.py` inside the `bridge/` directory.
2. Start the frontend by running `npm run dev` inside the `frontend/`
   directory.



### Wrapping XMR to WXMR

1. Send XMR to the bridge's Monero address
2. Call `requestMint()` with the transaction details
3. Wait for the bridge to verify and confirm the mint
4. Receive encrypted WXMR tokens

### Transferring WXMR

1. Connect MetaMask to the dApp
2. Enter recipient's address and amount
3. Submit the transfer transaction
4. Transaction is processed with encrypted balances

### Unwrapping WXMR to XMR

1. Access the admin interface
2. Initiate a burn request with your Monero address
3. Wait for the authority to process the burn
4. Receive XMR at your specified address

## Security Features

- Encrypted balances using Fhenix FHE
- Two-step minting process with cryptographic verification
- Authority-controlled bridge operations
- Monero transaction key verification
- Multisig support for administrative functions


## License

MIT License

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Open a pull request
