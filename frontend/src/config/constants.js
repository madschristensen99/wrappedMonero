// Network configuration
export const NETWORK_CONFIG = {
  SEPOLIA: {
    chainId: '0xaa36a7',
    chainName: 'Sepolia Testnet',
    rpcUrls: ['https://ethereum-sepolia.therpc.io'],
    nativeCurrency: {
      name: 'ETH',
      symbol: 'ETH',
      decimals: 18
    },
    blockExplorerUrls: ['https://sepolia.etherscan.io']
  }
};

// Contract addresses
export const CONTRACT_ADDRESSES = {
  WXMR: '0xb087c13f03b0b5a303d919cbf4d732b835afe434'
};

// Application settings
export const APP_SETTINGS = {
  NAME: 'Wrapped Monero (WXMR) Interface',
  TOKEN_NAME: 'Wrapped Monero',
  TOKEN_SYMBOL: 'WXMR',
  DECIMALS: 18
};

// UI settings
export const UI_SETTINGS = {
  ERROR_TIMEOUT: 10000,
  SUCCESS_TIMEOUT: 5000,
  REQUIRED_SIGNATURES: 3
};