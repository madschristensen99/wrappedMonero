import { walletService } from '../services/walletService.js';
import { contractService } from '../services/contractService.js';
import { showLoading, showError, showSuccess } from '../utils/uiHelpers.js';
import { isValidAddress, isValidAmount } from '../utils/validation.js';

class UIController {
  constructor() {
    this.currentTab = 'balance';
  }

  async initialize() {
    this.setupEventListeners();
    this.setupModalEvents();
    await this.updateBalance();
  }

  setupEventListeners() {
    // Wallet connection
    const connectBtn = document.getElementById('connectWallet');
    if (connectBtn) {
      connectBtn.addEventListener('click', async () => {
        try {
          showLoading(true);
          await walletService.connect();
          await contractService.initialize();
          await this.updateBalance();
          showLoading(false);
        } catch (error) {
          showLoading(false);
          showError(error.message);
        }
      });
    }

    // Tab switching
    document.querySelectorAll('.tab-btn').forEach(button => {
      button.addEventListener('click', (e) => {
        this.switchTab(e.target.dataset.tab);
      });
    });

    // Balance refresh
    const refreshBtn = document.getElementById('refreshBalance');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', async () => {
        await this.updateBalance();
      });
    }

    // Transfer form
    const transferForm = document.getElementById('transferForm');
    if (transferForm) {
      transferForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        await this.handleTransfer();
      });
    }

    // Admin functions
    this.setupAdminEvents();
  }

  setupAdminEvents() {
    const decryptTotalSupplyBtn = document.getElementById('decryptTotalSupply');
    const decryptBalanceBtn = document.getElementById('decryptBalance');
    const mintBtn = document.getElementById('mintBtn');
    const burnBtn = document.getElementById('burnBtn');

    if (decryptTotalSupplyBtn) {
      decryptTotalSupplyBtn.addEventListener('click', async () => {
        await this.handleDecryptTotalSupply();
      });
    }

    if (decryptBalanceBtn) {
      decryptBalanceBtn.addEventListener('click', async () => {
        await this.handleDecryptBalance();
      });
    }

    if (mintBtn) {
      mintBtn.addEventListener('click', async () => {
        await this.handleMint();
      });
    }

    if (burnBtn) {
      burnBtn.addEventListener('click', async () => {
        await this.handleBurn();
      });
    }
  }

  setupModalEvents() {
    // Close buttons for error/success messages
    document.querySelectorAll('.error-message button, .success-message button').forEach(button => {
      button.addEventListener('click', function() {
        this.parentElement.style.display = 'none';
      });
    });
  }

  switchTab(tabName) {
    this.currentTab = tabName;

    // Update tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
      btn.classList.remove('active');
    });
    document.querySelector(`[data-tab="${tabName}"]`)?.classList.add('active');

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
      content.classList.remove('active');
    });
    document.getElementById(`${tabName}-tab`)?.classList.add('active');
  }

  async updateBalance() {
    if (!walletService.isWalletConnected()) {
      document.getElementById('balance').textContent = '-';
      document.getElementById('totalSupply').textContent = '-';
      return;
    }

    try {
      const address = walletService.getAddress();
      const [balance, totalSupply] = await Promise.all([
        contractService.getBalance(address),
        contractService.getTotalSupply()
      ]);

      document.getElementById('balance').textContent = balance;
      document.getElementById('totalSupply').textContent = totalSupply;
    } catch (error) {
      console.error('Error updating balance:', error);
      document.getElementById('balance').textContent = 'Error';
      document.getElementById('totalSupply').textContent = 'Error';
    }
  }

  async handleTransfer() {
    if (!walletService.isWalletConnected()) {
      showError('Please connect your wallet first');
      return;
    }

    const recipient = document.getElementById('recipient')?.value;
    const amount = document.getElementById('amount')?.value;

    if (!isValidAddress(recipient)) {
      showError('Invalid recipient address');
      return;
    }

    if (!isValidAmount(amount)) {
      showError('Invalid amount');
      return;
    }

    try {
      showLoading(true);
      await contractService.transferTokens(recipient, amount);
      document.getElementById('transferForm')?.reset();
      await this.updateBalance();
      showLoading(false);
    } catch (error) {
      showLoading(false);
      showError(error.message);
    }
  }

  async handleDecryptTotalSupply() {
    if (!walletService.isWalletConnected()) {
      showError('Please connect your wallet first');
      return;
    }

    try {
      showLoading(true);
      await contractService.decryptTotalSupply();
      await this.updateBalance();
      showLoading(false);
    } catch (error) {
      showLoading(false);
      showError(error.message);
    }
  }

  async handleDecryptBalance() {
    if (!walletService.isWalletConnected()) {
      showError('Please connect your wallet first');
      return;
    }

    const address = walletService.getAddress();
    try {
      showLoading(true);
      await contractService.decryptBalance(address);
      await this.updateBalance();
      showLoading(false);
    } catch (error) {
      showLoading(false);
      showError(error.message);
    }
  }

  async handleMint() {
    if (!walletService.isWalletConnected()) {
      showError('Please connect your wallet first');
      return;
    }

    const toAddress = document.getElementById('mintAddress')?.value;
    const amount = document.getElementById('mintAmount')?.value;
    const vStr = document.getElementById('mintV')?.value;
    const rStr = document.getElementById('mintR')?.value;
    const sStr = document.getElementById('mintS')?.value;

    if (!isValidAddress(toAddress)) {
      showError('Invalid recipient address');
      return;
    }

    if (!isValidAmount(amount)) {
      showError('Invalid amount');
      return;
    }

    try {
      const v = vStr.split(',').map(v => parseInt(v.trim()));
      const r = rStr.split(',').map(r => r.trim());
      const s = sStr.split(',').map(s => s.trim());

      showLoading(true);
      await contractService.mintTokens(toAddress, amount, v, r, s);
      await this.updateBalance();
      showLoading(false);
    } catch (error) {
      showLoading(false);
      showError(error.message);
    }
  }

  async handleBurn() {
    if (!walletService.isWalletConnected()) {
      showError('Please connect your wallet first');
      return;
    }

    const amount = document.getElementById('burnAmount')?.value;
    const vStr = document.getElementById('burnV')?.value;
    const rStr = document.getElementById('burnR')?.value;
    const sStr = document.getElementById('burnS')?.value;

    if (!isValidAmount(amount)) {
      showError('Invalid amount');
      return;
    }

    try {
      const v = vStr.split(',').map(v => parseInt(v.trim()));
      const r = rStr.split(',').map(r => r.trim());
      const s = sStr.split(',').map(s => s.trim());

      showLoading(true);
      await contractService.burnTokens(amount, v, r, s);
      await this.updateBalance();
      showLoading(false);
    } catch (error) {
      showLoading(false);
      showError(error.message);
    }
  }
}

export const uiController = new UIController();