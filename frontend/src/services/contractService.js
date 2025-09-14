import { CONTRACT_ABI, CONTRACT_ADDRESSES } from '../config/constants.js';
import { walletService } from './walletService.js';
import { showError, showSuccess } from '../utils/uiHelpers.js';

class ContractService {
  constructor() {
    this.contract = null;
    this.readContract = null;
    this.contractAddress = CONTRACT_ADDRESSES.WXMR;
  }

  async initialize() {
    try {
      const signer = walletService.getSigner();
      const provider = walletService.getProvider();
      
      if (!signer || !provider) {
        throw new Error('Wallet not connected');
      }

      this.contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, signer);
      this.readContract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, provider);
      
      return this.contract;
    } catch (error) {
      console.error('Error initializing contract:', error);
      throw error;
    }
  }

  async getBalance(address) {
    if (!this.readContract) {
      throw new Error('Contract not initialized');
    }

    try {
      const balance = await this.readContract.balanceOf(address);
      return ethers.formatEther(balance);
    } catch (error) {
      console.error('Error fetching balance:', error);
      throw new Error('Failed to fetch balance');
    }
  }

  async getTotalSupply() {
    if (!this.readContract) {
      throw new Error('Contract not initialized');
    }

    try {
      const totalSupply = await this.readContract.totalSupply();
      return ethers.formatEther(totalSupply);
    } catch (error) {
      console.error('Error fetching total supply:', error);
      throw new Error('Failed to fetch total supply');
    }
  }

  async transferTokens(recipient, amount) {
    if (!this.contract) {
      throw new Error('Contract not initialized');
    }

    try {
      const amountWei = ethers.parseEther(amount);
      const tx = await this.contract.transfer(recipient, amountWei);
      await tx.wait();
      return tx;
    } catch (error) {
      console.error('Error transferring tokens:', error);
      throw error;
    }
  }

  async decryptTotalSupply() {
    if (!this.contract) {
      throw new Error('Contract not initialized');
    }

    try {
      const tx = await this.contract.decryptTotalSupply();
      await tx.wait();
      showSuccess('Total supply decrypted');
      return tx;
    } catch (error) {
      console.error('Error decrypting total supply:', error);
      throw error;
    }
  }

  async decryptBalance(address) {
    if (!this.contract) {
      throw new Error('Contract not initialized');
    }

    try {
      const tx = await this.contract.decryptBalance(address);
      await tx.wait();
      showSuccess('Balance decrypted');
      return tx;
    } catch (error) {
      console.error('Error decrypting balance:', error);
      throw error;
    }
  }

  async mintTokens(toAddress, amount, v, r, s) {
    if (!this.contract) {
      throw new Error('Contract not initialized');
    }

    try {
      const amountWei = ethers.parseEther(amount);
      const tx = await this.contract.mint(
        toAddress,
        amountWei,
        v,
        r,
        s
      );
      await tx.wait();
      showSuccess('Tokens minted successfully');
      return tx;
    } catch (error) {
      console.error('Error minting tokens:', error);
      throw error;
    }
  }

  async burnTokens(amount, v, r, s) {
    if (!this.contract) {
      throw new Error('Contract not initialized');
    }

    try {
      const amountWei = ethers.parseEther(amount);
      const tx = await this.contract.burn(amountWei, v, r, s);
      await tx.wait();
      showSuccess('Tokens burned successfully');
      return tx;
    } catch (error) {
      console.error('Error burning tokens:', error);
      throw error;
    }
  }

  getContract() {
    return this.contract;
  }

  getReadContract() {
    return this.readContract;
  }
}

export const contractService = new ContractService();