import { NETWORK_CONFIG, CONTRACT_ADDRESSES } from '../config/constants.js';
import { showError, showSuccess } from '../utils/uiHelpers.js';

class WalletService {
  constructor() {
    this.provider = null;
    this.signer = null;
    this.userAddress = null;
    this.contract = null;
    this.isConnected = false;
  }

  async init() {
    if (typeof window.ethereum === 'undefined') {
      throw new Error('Please install MetaMask to use this application');
    }

    this.provider = new ethers.BrowserProvider(window.ethereum);
    
    // Set up event listeners
    this.setupEventListeners();
    
    return !!this.provider;
  }

  async connect() {
    try {
      await this.switchToSepolia();
      const accounts = await this.provider.send('eth_requestAccounts', []);
      this.userAddress = accounts[0];
      this.signer = this.provider.getSigner();
      
      // Update UI
      this.updateWalletUI();
      
      // Get network info
      const network = await this.provider.getNetwork();
      this.updateNetworkUI(network);
      
      this.isConnected = true;
      showSuccess('Wallet connected successfully');
      
      return {
        address: this.userAddress,
        signer: this.signer,
        network: network
      };
    } catch (error) {
      console.error('Error connecting wallet:', error);
      showError(`Failed to connect wallet: ${error.message}`);
      throw error;
    }
  }

  async switchToSepolia() {
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: NETWORK_CONFIG.SEPOLIA.chainId }]
      });
    } catch (switchError) {
      // Network not added
      if (switchError.code === 4902) {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [NETWORK_CONFIG.SEPOLIA]
        });
      } else {
        throw switchError;
      }
    }
  }

  async disconnect() {
    this.provider = null;
    this.signer = null;
    this.userAddress = null;
    this.contract = null;
    this.isConnected = false;
  }

  setupEventListeners() {
    if (!window.ethereum) return;

    window.ethereum.on('accountsChanged', (accounts) => {
      if (accounts.length === 0) {
        this.disconnect();
        window.location.reload();
      } else if (accounts[0] !== this.userAddress) {
        this.userAddress = accounts[0];
        this.updateWalletUI();
        showSuccess('Account changed');
      }
    });

    window.ethereum.on('chainChanged', () => {
      window.location.reload();
    });
  }

  updateWalletUI() {
    const connectButton = document.getElementById('connectWallet');
    const walletInfo = document.getElementById('walletInfo');
    const walletAddress = document.getElementById('walletAddress');

    if (!connectButton || !walletInfo || !walletAddress) return;

    if (this.userAddress) {
      connectButton.style.display = 'none';
      walletInfo.style.display = 'block';
      walletAddress.textContent = `${this.userAddress.substring(0, 6)}...${this.userAddress.substring(38)}`;
    } else {
      connectButton.style.display = 'block';
      walletInfo.style.display = 'none';
    }
  }

  updateNetworkUI(network) {
    const networkName = document.getElementById('networkName');
    if (networkName) {
      networkName.textContent = network.name || 'Fhenix Network';
    }
  }

  getAddress() {
    return this.userAddress;
  }

  getSigner() {
    return this.signer;
  }

  getProvider() {
    return this.provider;
  }

  isWalletConnected() {
    return this.isConnected && this.userAddress !== null;
  }
}

export const walletService = new WalletService();