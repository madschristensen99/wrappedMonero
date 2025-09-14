// Import ethers (you'll need to include ethers.min.js in your HTML)
import { walletService } from './services/walletService.js';
import { contractService } from './services/contractService.js';
import { uiController } from './components/uiController.js';

class App {
  constructor() {
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    try {
      console.log('Initializing WXMR Application...');

      await this.loadDependencies();
      await this.initializeServices();
      await this.initializeComponents();

      this.initialized = true;
      console.log('Application initialized successfully');
    } catch (error) {
      console.error('Failed to initialize application:', error);
      throw error;
    }
  }

  async loadDependencies() {
    // Check if ethers is available
    if (typeof ethers === 'undefined') {
      throw new Error('Ethers.js is not available. Please include ethers.min.js in your HTML.');
    }

    // Check for MetaMask
    if (typeof window.ethereum === 'undefined') {
      throw new Error('MetaMask is not installed. Please install MetaMask to use this application.');
    }
  }

  async initializeServices() {
    // Initialize wallet service
    await walletService.init();
    
    // Initialize contract service (but don't connect yet)
    // contractService.initialize() will be called after wallet connection
  }

  async initializeComponents() {
    // Initialize UI controller
    await uiController.initialize();
  }

  async connectWallet() {
    try {
      // Connect wallet through service
      await walletService.connect();
      
      // Initialize contract service now that wallet is connected
      await contractService.initialize();
      
      // Update UI
      await uiController.updateBalance();
      
      console.log('Wallet connected successfully');
      return true;
    } catch (error) {
      console.error('Failed to connect wallet:', error);
      throw error;
    }
  }

  isWalletConnected() {
    return walletService.isWalletConnected();
  }

  getWalletAddress() {
    return walletService.getAddress();
  }

  getContractService() {
    return contractService;
  }

  getWalletService() {
    return walletService;
  }
}

// Create global app instance
const app = new App();

// Initialize app when DOM is ready
document.addEventListener('DOMContentLoaded', async () => {
  try {
    await app.initialize();
  } catch (error) {
    console.error('Application initialization failed:', error);
    
    // Show error to user
    const errorElement = document.getElementById('error');
    const errorTextElement = document.getElementById('errorText');
    
    if (errorElement && errorTextElement) {
      errorTextElement.textContent = error.message;
      errorElement.style.display = 'flex';
    }
  }
});

// Make app available globally for debugging
window.wxmrApp = app;

export default app;