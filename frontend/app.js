import { ethers } from '../ethers.min.js';

// Contract ABI - Generated from Solidity compiler for WrappedMonero contract
const CONTRACT_ABI = [
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "spender",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "value",
				"type": "uint256"
			}
		],
		"name": "approve",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "uint64",
				"name": "amount",
				"type": "uint64"
			}
		],
		"name": "burn",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "txSecret",
				"type": "bytes32"
			},
			{
				"internalType": "uint64",
				"name": "amount",
				"type": "uint64"
			}
		],
		"name": "confirmMint",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "account",
				"type": "address"
			}
		],
		"name": "decryptBalance",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "decryptTotalSupply",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [],
		"stateMutability": "nonpayable",
		"type": "constructor"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "spender",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "allowance",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "needed",
				"type": "uint256"
			}
		],
		"name": "ERC20InsufficientAllowance",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "sender",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "balance",
				"type": "uint256"
			},
			{
				"internalType": "uint256",
				"name": "needed",
				"type": "uint256"
			}
		],
		"name": "ERC20InsufficientBalance",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "approver",
				"type": "address"
			}
		],
		"name": "ERC20InvalidApprover",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "receiver",
				"type": "address"
			}
		],
		"name": "ERC20InvalidReceiver",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "sender",
				"type": "address"
			}
		],
		"name": "ERC20InvalidSender",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "spender",
				"type": "address"
			}
		],
		"name": "ERC20InvalidSpender",
		"type": "error"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "txSecret",
				"type": "bytes32"
			},
			{
				"internalType": "address",
				"name": "receiver",
				"type": "address"
			}
		],
		"name": "requestMint",
		"outputs": [],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "int32",
				"name": "value",
				"type": "int32"
			}
		],
		"name": "SecurityZoneOutOfBounds",
		"type": "error"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "owner",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "spender",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "value",
				"type": "uint256"
			}
		],
		"name": "Approval",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "from",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "Burn",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "txSecret",
				"type": "bytes32"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "receiver",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "amount",
				"type": "uint256"
			}
		],
		"name": "MintConfirmed",
		"type": "event"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "bytes32",
				"name": "txSecret",
				"type": "bytes32"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "receiver",
				"type": "address"
			}
		],
		"name": "MintRequested",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"internalType": "uint64",
				"name": "amount",
				"type": "uint64"
			}
		],
		"name": "transfer",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "value",
				"type": "uint256"
			}
		],
		"name": "transfer",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"anonymous": false,
		"inputs": [
			{
				"indexed": true,
				"internalType": "address",
				"name": "from",
				"type": "address"
			},
			{
				"indexed": true,
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"indexed": false,
				"internalType": "uint256",
				"name": "value",
				"type": "uint256"
			}
		],
		"name": "Transfer",
		"type": "event"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "from",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "to",
				"type": "address"
			},
			{
				"internalType": "uint256",
				"name": "value",
				"type": "uint256"
			}
		],
		"name": "transferFrom",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "nonpayable",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "owner",
				"type": "address"
			},
			{
				"internalType": "address",
				"name": "spender",
				"type": "address"
			}
		],
		"name": "allowance",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "AUTHORITY",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "address",
				"name": "account",
				"type": "address"
			}
		],
		"name": "balanceOf",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "decimals",
		"outputs": [
			{
				"internalType": "uint8",
				"name": "",
				"type": "uint8"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "mintRequestReceiver",
		"outputs": [
			{
				"internalType": "address",
				"name": "",
				"type": "address"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [
			{
				"internalType": "bytes32",
				"name": "",
				"type": "bytes32"
			}
		],
		"name": "mintSecretUsed",
		"outputs": [
			{
				"internalType": "bool",
				"name": "",
				"type": "bool"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "name",
		"outputs": [
			{
				"internalType": "string",
				"name": "",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "symbol",
		"outputs": [
			{
				"internalType": "string",
				"name": "",
				"type": "string"
			}
		],
		"stateMutability": "view",
		"type": "function"
	},
	{
		"inputs": [],
		"name": "totalSupply",
		"outputs": [
			{
				"internalType": "uint256",
				"name": "",
				"type": "uint256"
			}
		],
		"stateMutability": "view",
		"type": "function"
	}
];

// Actual deployed contract address
const CONTRACT_ADDRESS = '0xb087c13f03b0b5a303d919cbf4d732b835afe434';

let provider = null;
let signer = null;
let contract = null;
let userAddress;

// Initialize the app
async function initApp() {
    console.log('Initializing app...');
    console.log('Ethers available:', typeof ethers !== 'undefined');

    // Check if MetaMask is installed
    if (typeof window.ethereum === 'undefined') {
        showError('Please install MetaMask to use this application');
        return;
    }

    try {
        // Request accounts
        provider = new ethers.BrowserProvider(window.ethereum);

        // Initialize event listeners
        initializeEventListeners();

        console.log('App initialized successfully');
    } catch (error) {
        console.error('Error initializing app:', error);
        showError('Failed to initialize application: ' + error.message);
    }
}

function initializeEventListeners() {
    // Wallet connection
    document.getElementById('connectWallet').addEventListener('click', connectWallet);

    // Tab switching
    document.querySelectorAll('.tab-btn').forEach(button => {
        button.addEventListener('click', (e) => switchTab(e.target.dataset.tab));
    });

    // Balance refresh
    document.getElementById('refreshBalance').addEventListener('click', refreshBalance);

    // Transfer form
    document.getElementById('transferForm').addEventListener('submit', handleTransfer);

    // Admin functions
    document.getElementById('decryptTotalSupply').addEventListener('click', decryptTotalSupply);
    document.getElementById('decryptBalance').addEventListener('click', decryptBalance);
    document.getElementById('mintBtn').addEventListener('click', mintTokens);
    document.getElementById('burnBtn').addEventListener('click', burnTokens);
}

async function connectWallet() {
    try {
        showLoading(true);

        // Switch to Sepolia network (11155111)
        try {
            await window.ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: '0xaa36a7' }]
            });
            console.log('Switched to Sepolia network');
        } catch (switchError) {
            // Network not added to MetaMask, add it
            if (switchError.code === 4902) {
                await window.ethereum.request({
                    method: 'wallet_addEthereumChain',
                    params: [{
                        chainId: '0xaa36a7',
                        chainName: 'Sepolia Testnet',
                        rpcUrls: ['https://ethereum-sepolia.therpc.io'],
                        nativeCurrency: {
                            name: 'ETH',
                            symbol: 'ETH',
                            decimals: 18
                        },
                        blockExplorerUrls: ['https://sepolia.etherscan.io']
                    }]
                });
            } else {
                throw switchError;
            }
        }

        const accounts = await provider.send('eth_requestAccounts', []);
        userAddress = accounts[0];
        signer = provider.getSigner();

        // Create contract instance with signer for writes
        contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

        // Update UI
        document.getElementById('walletAddress').textContent = userAddress.substring(0, 6) + '...' + userAddress.substring(38);
        document.getElementById('connectWallet').style.display = 'none';
        document.getElementById('walletInfo').style.display = 'block';

        // Get network name
        const network = await provider.getNetwork();
        document.getElementById('networkName').textContent = network.name || 'Fhenix Network';

        // Load initial data
        await refreshBalance();

        showLoading(false);
        showSuccess('Wallet connected successfully');
    } catch (error) {
        showLoading(false);
        console.error('Error connecting wallet:', error);
        showError('Failed to connect wallet: ' + error.message);
    }
}

async function refreshBalance() {
    if (!provider || !userAddress) {
        showError('Please connect your wallet first');
        return;
    }

    try {
        // Create contract instance with provider for reads
        const readContract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

        console.log('Fetching balance for address:', userAddress);
        console.log('Contract address:', CONTRACT_ADDRESS);
        const network = await provider.getNetwork();
        console.log('Network:', network);
        console.log('Chain ID:', network.chainId);

        try {
            const balance = await readContract.balanceOf(userAddress);
            const totalSupply = await readContract.totalSupply();

            document.getElementById('balance').textContent = ethers.formatEther(balance);
            document.getElementById('totalSupply').textContent = ethers.formatEther(totalSupply);
        } catch (error) {
            console.log('Contract might not be deployed at this address on Sepolia');
            document.getElementById('balance').textContent = 'Contract Not Deployed';
            document.getElementById('totalSupply').textContent = 'Contract Not Deployed';

            // Add deployment guidance
            const msg = `Contract not found at ${CONTRACT_ADDRESS} on Sepolia. Please deploy the contract or update the address.`;
            console.error(msg);
            throw new Error("Deployment required - update CONTRACT_ADDRESS to your deployed contract");
        }
    } catch (error) {
        console.error('Error fetching balance:', error);
        showError('Failed to fetch balance: ' + error.message);
    }
}

async function handleTransfer(event) {
    event.preventDefault();

    if (!contract) {
        showError('Please connect your wallet first');
        return;
    }

    const recipient = document.getElementById('recipient').value;
    const amount = document.getElementById('amount').value;

    if (!ethers.isAddress(recipient)) {
        showError('Invalid recipient address');
        return;
    }

    const amountWei = ethers.parseEther(amount);

    try {
        showLoading(true);
        const tx = await contract.transfer(recipient, amountWei);
        await tx.wait();

        showLoading(false);
        showSuccess('Transfer completed successfully');
        document.getElementById('transferForm').reset();
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error('Error transferring tokens:', error);
        showError('Transfer failed: ' + error.message);
    }
}

async function decryptTotalSupply() {
    if (!contract) {
        showError('Please connect your wallet first');
        return;
    }

    try {
        showLoading(true);
        const tx = await contract.decryptTotalSupply();
        await tx.wait();

        showLoading(false);
        showSuccess('Total supply decrypted');
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error('Error decrypting total supply:', error);
        showError('Failed to decrypt total supply: ' + error.message);
    }
}

async function decryptBalance() {
    if (!contract || !userAddress) {
        showError('Please connect your wallet first');
        return;
    }

    try {
        showLoading(true);
        const tx = await contract.decryptBalance(userAddress);
        await tx.wait();

        showLoading(false);
        showSuccess('Balance decrypted');
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error('Error decrypting balance:', error);
        showError('Failed to decrypt balance: ' + error.message);
    }
}

async function mintTokens() {
    if (!contract) {
        showError('Please connect your wallet first');
        return;
    }

    const toAddress = document.getElementById('mintAddress').value;
    const amount = document.getElementById('mintAmount').value;
    const vInputs = document.getElementById('mintV').value.split(',').map(v => parseInt(v.trim()));
    const rInputs = document.getElementById('mintR').value.split(',').map(r => r.trim());
    const sInputs = document.getElementById('mintS').value.split(',').map(s => s.trim());

    if (!ethers.isAddress(toAddress)) {
        showError('Invalid recipient address');
        return;
    }

    if (vInputs.length !== 3 || rInputs.length !== 3 || sInputs.length !== 3) {
        showError('Please provide exactly 3 signatures for minting');
        return;
    }

    try {
        showLoading(true);
        const amountWei = ethers.parseEther(amount);

        const tx = await contract.mint(
            toAddress,
            amountWei,
            vInputs,
            rInputs.map(r => ethers.zeroPadValue(r, 32)),
            sInputs.map(s => ethers.zeroPadValue(s, 32))
        );
        await tx.wait();

        showLoading(false);
        showSuccess('Tokens minted successfully');
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error('Error minting tokens:', error);
        showError('Minting failed: ' + error.message);
    }
}

async function burnTokens() {
    if (!contract) {
        showError('Please connect your wallet first');
        return;
    }

    const amount = document.getElementById('burnAmount').value;
    const vInputs = document.getElementById('burnV').value.split(',').map(v => parseInt(v.trim()));
    const rInputs = document.getElementById('burnR').value.split(',').map(r => r.trim());
    const sInputs = document.getElementById('burnS').value.split(',').map(s => s.trim());

    if (vInputs.length !== 3 || rInputs.length !== 3 || sInputs.length !== 3) {
        showError('Please provide exactly 3 signatures for burning');
        return;
    }

    try {
        showLoading(true);
        const amountWei = ethers.parseEther(amount);

        const tx = await contract.burn(
            amountWei,
            vInputs,
            rInputs.map(r => ethers.zeroPadValue(r, 32)),
            sInputs.map(s => ethers.zeroPadValue(s, 32))
        );
        await tx.wait();

        showLoading(false);
        showSuccess('Tokens burned successfully');
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error('Error burning tokens:', error);
        showError('Burning failed: ' + error.message);
    }
}

// Utility functions
function showLoading(show) {
    document.getElementById('loading').style.display = show ? 'flex' : 'none';
}

function showError(message) {
    document.getElementById('errorText').textContent = message;
    document.getElementById('error').style.display = 'flex';
    setTimeout(() => document.getElementById('error').style.display = 'none', 10000);
}

function showSuccess(message) {
    document.getElementById('successText').textContent = message;
    document.getElementById('success').style.display = 'flex';
    setTimeout(() => document.getElementById('success').style.display = 'none', 5000);
}

function switchTab(tabName) {
    // Update tab buttons
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.classList.remove('active');
    });
    document.querySelector(`[data-tab="${tabName}"]`).classList.add('active');

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
    });
    document.getElementById(`${tabName}-tab`).classList.add('active');
}

// Initialize app on load
document.addEventListener('DOMContentLoaded', initApp);

// Handle account changes
if (window.ethereum) {
    window.ethereum.on('accountsChanged', (accounts) => {
        if (accounts.length === 0) {
            // User disconnected
            location.reload();
        } else if (accounts[0] !== userAddress) {
            // Account changed
            location.reload();
        }
    });

    window.ethereum.on('chainChanged', () => {
        // Network changed
        location.reload();
    });
}
