import { ethers } from "../ethers.min.js";

// Contract ABI will be loaded from abi.json
/** @type {any[] | null} */
let CONTRACT_ABI = null;

// Actual deployed contract address
/** @type {string} */
const CONTRACT_ADDRESS = "0xb087c13f03b0b5a303d919cbf4d732b835afe434";

/** @type {ethers.BrowserProvider | null} */
let provider = null;
/** @type {ethers.JsonRpcSigner | null} */
let signer = null;
/** @type {ethers.Contract | null} */
let contract = null;
/** @type {string | undefined} */
let userAddress;

/**
 * Load contract ABI from file
 * @returns {Promise<void>}
 */
async function loadContractABI() {
    try {
        const response = await fetch('./abi.json');
        if (!response.ok) {
            throw new Error(`Failed to load ABI: ${response.status}`);
        }
        CONTRACT_ABI = await response.json();
        console.log("Contract ABI loaded successfully");
    } catch (error) {
        console.error("Error loading contract ABI:", error);
        throw new Error("Failed to load contract ABI: " + error.message);
    }
}

/**
 * Initialize the app
 * @returns {Promise<void>}
 */
async function initApp() {
    console.log("Initializing app...");
    console.log("Ethers available:", typeof ethers !== "undefined");

    // Check if MetaMask is installed
    if (typeof window.ethereum === "undefined") {
        showError("Please install MetaMask to use this application");
        return;
    }

    try {
        // Load contract ABI first
        await loadContractABI();

        // Request accounts
        provider = new ethers.BrowserProvider(window.ethereum);

        // Initialize event listeners
        initializeEventListeners();

        // Try to auto-connect if previously connected
        await tryAutoConnect();

        console.log("App initialized successfully");
    } catch (error) {
        console.error("Error initializing app:", error);
        showError("Failed to initialize application: " + error.message);
    }
}

/**
 * Initialize event listeners for UI elements
 * @returns {void}
 */
function initializeEventListeners() {
    // Wallet connection
    document
        .getElementById("connectWallet")
        .addEventListener("click", connectWallet);

    // Tab switching
    document.querySelectorAll(".tab-btn").forEach((button) => {
        button.addEventListener("click", (e) =>
            switchTab(e.target.dataset.tab),
        );
    });

    // Balance refresh
    document
        .getElementById("refreshBalance")
        .addEventListener("click", refreshBalance);

    // Transfer form
    document
        .getElementById("transferForm")
        .addEventListener("submit", handleTransfer);

    // Mint request form
    document
        .getElementById("mintRequestForm")
        .addEventListener("submit", handleMintRequest);
    document
        .getElementById("useCurrentWallet")
        .addEventListener("click", useCurrentWalletAddress);

}

/**
 * Try to auto-connect if previously connected
 * @returns {Promise<void>}
 */
async function tryAutoConnect() {
    try {
        // Check if already connected
        const accounts = await window.ethereum.request({
            method: "eth_accounts",
        });

        if (accounts.length > 0) {
            console.log("Auto-connecting to previously connected account...");
            await connectWallet();
        } else {
            console.log("No previously connected accounts found");
        }
    } catch (error) {
        console.log(
            "Auto-connect failed, user will need to connect manually:",
            error.message,
        );
        // Don't show error to user for auto-connect failure
    }
}

/**
 * Connect to MetaMask wallet
 * @returns {Promise<void>}
 */
async function connectWallet() {
    try {
        showLoading(true);

        // Switch to Sepolia network (11155111)
        try {
            await window.ethereum.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: "0xaa36a7" }],
            });
            console.log("Switched to Sepolia network");
        } catch (switchError) {
            // Network not added to MetaMask, add it
            if (switchError.code === 4902) {
                await window.ethereum.request({
                    method: "wallet_addEthereumChain",
                    params: [
                        {
                            chainId: "0xaa36a7",
                            chainName: "Sepolia Testnet",
                            rpcUrls: ["https://ethereum-sepolia.therpc.io"],
                            nativeCurrency: {
                                name: "ETH",
                                symbol: "ETH",
                                decimals: 18,
                            },
                            blockExplorerUrls: [
                                "https://sepolia.etherscan.io",
                            ],
                        },
                    ],
                });
            } else {
                throw switchError;
            }
        }

        const accounts = await provider.send("eth_requestAccounts", []);
        userAddress = accounts[0];
        signer = await provider.getSigner();

        // Create contract instance with signer for writes
        contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

        // Update UI
        document.getElementById("walletAddress").textContent =
            userAddress.substring(0, 6) + "..." + userAddress.substring(38);
        document.getElementById("connectWallet").style.display = "none";
        document.getElementById("walletInfo").style.display = "block";

        // Get network name
        const network = await provider.getNetwork();
        document.getElementById("networkName").textContent =
            network.name || "Fhenix Network";

        // Load initial data
        await refreshBalance();

        showLoading(false);
        showSuccess("Wallet connected successfully");
    } catch (error) {
        showLoading(false);
        console.error("Error connecting wallet:", error);
        showError("Failed to connect wallet: " + error.message);
    }
}

/**
 * Refresh user balance and total supply
 * @returns {Promise<void>}
 */
async function refreshBalance() {
    if (!provider || !userAddress) {
        showError("Please connect your wallet first");
        return;
    }

    // TODO
}

/**
 * Handle transfer form submission
 * @param {Event} event - Form submit event
 * @returns {Promise<void>}
 */
async function handleTransfer(event) {
    event.preventDefault();

    if (!contract) {
        showError("Please connect your wallet first");
        return;
    }

    const recipient = document.getElementById("recipient").value;
    const amount = document.getElementById("amount").value;

    if (!ethers.isAddress(recipient)) {
        showError("Invalid recipient address");
        return;
    }

    const amountWei = ethers.parseEther(amount);

    try {
        showLoading(true);
        const tx = await contract.transfer(recipient, amountWei);
        await tx.wait();

        showLoading(false);
        showSuccess("Transfer completed successfully");
        document.getElementById("transferForm").reset();
        await refreshBalance();
    } catch (error) {
        showLoading(false);
        console.error("Error transferring tokens:", error);
        showError("Transfer failed: " + error.message);
    }
}


/**
 * Fill receiver address with current wallet address
 * @returns {void}
 */
function useCurrentWalletAddress() {
    if (!userAddress) {
        showError("Please connect your wallet first");
        return;
    }

    document.getElementById("receiverAddress").value = userAddress;
    showSuccess("Current wallet address filled in");
}

/**
 * Handle mint request form submission
 * @param {Event} event - Form submit event
 * @returns {Promise<void>}
 */
async function handleMintRequest(event) {
    event.preventDefault();

    if (!contract) {
        showError("Please connect your wallet first");
        return;
    }

    const txId = document.getElementById("txId").value.trim();
    const txSecret = document.getElementById("txSecret").value.trim();
    const receiverAddress = document
        .getElementById("receiverAddress")
        .value.trim();

    // Validate inputs
    if (!txId || !txSecret || !receiverAddress) {
        showError("Please fill in all fields");
        return;
    }

    if (!ethers.isAddress(receiverAddress)) {
        showError("Invalid receiver address");
        return;
    }

    // Validate hex format for txId and txSecret
    if (!/^[0-9a-fA-F]+$/.test(txId) || !/^[0-9a-fA-F]+$/.test(txSecret)) {
        showError("Transaction ID and secret must be valid hex strings");
        return;
    }

    try {
        showLoading(true);

        // Convert to bytes32 format
        const txIdBytes32 = ethers.zeroPadValue("0x" + txId, 32);
        const txSecretBytes32 = ethers.zeroPadValue("0x" + txSecret, 32);

        console.log("Requesting mint with:", {
            txId: txIdBytes32,
            txSecret: txSecretBytes32,
            receiver: receiverAddress,
        });

        const tx = await contract.requestMint(
            txIdBytes32,
            txSecretBytes32,
            receiverAddress,
        );
        await tx.wait();

        showLoading(false);
        showSuccess(
            "Mint request submitted successfully! The bridge will process your request.",
        );
        document.getElementById("mintRequestForm").reset();
    } catch (error) {
        showLoading(false);
        console.error("Error requesting mint:", error);
        showError("Mint request failed: " + error.message);
    }
}

/**
 * Show or hide loading spinner
 * @param {boolean} show - Whether to show loading
 * @returns {void}
 */
function showLoading(show) {
    document.getElementById("loading").style.display = show ? "flex" : "none";
}

/**
 * Show error message
 * @param {string} message - Error message to display
 * @returns {void}
 */
function showError(message) {
    document.getElementById("errorText").textContent = message;
    document.getElementById("error").style.display = "flex";
    setTimeout(
        () => (document.getElementById("error").style.display = "none"),
        10000,
    );
}

/**
 * Show success message
 * @param {string} message - Success message to display
 * @returns {void}
 */
function showSuccess(message) {
    document.getElementById("successText").textContent = message;
    document.getElementById("success").style.display = "flex";
    setTimeout(
        () => (document.getElementById("success").style.display = "none"),
        5000,
    );
}

/**
 * Switch between tabs
 * @param {string} tabName - Name of tab to switch to
 * @returns {void}
 */
function switchTab(tabName) {
    // Update tab buttons
    document.querySelectorAll(".tab-btn").forEach((btn) => {
        btn.classList.remove("active");
    });
    document.querySelector(`[data-tab="${tabName}"]`).classList.add("active");

    // Update tab content
    document.querySelectorAll(".tab-content").forEach((content) => {
        content.classList.remove("active");
    });
    document.getElementById(`${tabName}-tab`).classList.add("active");
}

// Initialize app on load
document.addEventListener("DOMContentLoaded", initApp);

// Handle account changes
if (window.ethereum) {
    window.ethereum.on("accountsChanged", (accounts) => {
        if (accounts.length === 0) {
            // User disconnected
            location.reload();
        } else if (accounts[0] !== userAddress) {
            // Account changed
            location.reload();
        }
    });

    window.ethereum.on("chainChanged", () => {
        // Network changed
        location.reload();
    });
}
