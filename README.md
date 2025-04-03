# WXMR Bridge - Atomic Swaps between Monero and EVM Chains

A decentralized bridge enabling trustless swaps between Monero (XMR) and Wrapped Monero (WXMR) on EVM-compatible blockchains.

## Features

- **Atomic Swaps**: Secure peer-to-peer swaps between XMR and WXMR
- **Liquidity Pools**: Earn 0.27% fees by providing liquidity
- **Non-custodial**: Users maintain control of their funds
- **Time-locked Transactions**: Secure cross-chain transfers
- **Fixed Fee Structure**: Transparent 0.27% fee on swaps

## Contracts

### wXmr.sol
- ERC20 token representing Wrapped Monero (WXMR)
- Fixed 12 decimal places to match Monero's divisibility
- Only mintable/burnable by the bridge contract
- Implements OpenZeppelin's ERC20 and ERC20Burnable

### wXmrBridge.sol
- Handles atomic swaps between XMR and WXMR
- Manages liquidity provider pools and fee distribution
- Implements time-locked transactions for security
- Uses role-based access control (Admin, Swap Facilitator)
- Includes slippage protection and swap expiration

## How It Works

### XMR → WXMR Flow
1. User locks XMR in a time-locked Monero address
2. After confirmation, WXMR is minted on the EVM chain
3. User can trade or use WXMR on EVM DeFi

### WXMR → XMR Flow
1. User burns WXMR on the EVM chain
2. After confirmation, XMR is released from time-lock
3. User receives XMR in their wallet

### Liquidity Providers
1. Deposit XMR equivalent to back WXMR supply
2. Earn 0.27% of all swap volume
3. Withdraw liquidity after cooldown period

## Requirements
- Node.js
- Hardhat/Truffle (for local development)
- Web3 provider (e.g. MetaMask)

## Installation
1. Clone the repository
2. Install dependencies: `npm install`
3. Configure environment variables
4. Deploy contracts: `npx hardhat deploy`

## Security
- Audited by [TBD]
- Time-locked transactions prevent front-running
- Reentrancy guards on all critical functions
- Fixed 0.27% fee with maximum cap

## Roadmap

### Phase 1 (Current)
- Core swap functionality
- Basic liquidity pools
- Web interface for swaps
- Security audits

### Phase 2 (Q3 2025)
- Multi-chain expansion (Polygon, Arbitrum)
- Advanced liquidity incentives
- DAO governance foundation
- Mobile interface

### Phase 3 (Q1 2026)
- Full DAO governance
- Decentralized oracle network
- Cross-chain liquidity routing
- Institutional-grade APIs

## Community Growth

We're building an open, transparent community around WXMR:

- **Developer Grants**: Funding for ecosystem projects
- **Ambassador Program**: Community leaders who promote adoption
- **Governance Participation**: Gradual transition to community voting
- **Educational Content**: Tutorials, workshops, and documentation

## Gradual Decentralization

Our path to full decentralization:

1. **Initial Phase**: Core team maintains admin controls
2. **Transition Phase**: 
   - Community-elected multisig
   - Progressive DAO implementation
   - Decentralized frontends
3. **Mature Phase**:
   - Fully community-governed
   - Distributed infrastructure
   - Permissionless participation

## Disclaimer

**Important**: The WXMR Bridge is experimental software. Users should:

- Understand the risks of cross-chain transactions
- Never supply more funds than they can afford to lose
- Verify all contract addresses before transacting
- Be aware that Monero's privacy features don't extend to WXMR

The development team makes no warranties about the security or functionality of this software. Use at your own risk.
