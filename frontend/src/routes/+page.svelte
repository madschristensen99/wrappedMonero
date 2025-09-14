<script lang="ts">
    import { onMount } from "svelte";
    import { ethers } from "ethers";
    import { cofhejs } from "cofhejs/web";
    import type { BrowserProvider, JsonRpcSigner, Contract } from "ethers";

    // Contract ABI will be loaded from abi.json
    let CONTRACT_ABI: any[] | null = null;

    // Actual deployed contract address
    const CONTRACT_ADDRESS: string =
        "0xb087c13f03b0b5a303d919cbf4d732b835afe434";

    let provider: BrowserProvider | null = null;
    let signer: JsonRpcSigner | null = null;
    let contract: Contract | null = null;
    let userAddress: string = "";
    let cofheClient: any = null;

    // UI state
    let walletConnected: boolean = false;
    let networkName: string = "";
    let balance: string = "-";
    let totalSupply: string = "-";
    let activeTab: "balance" | "transfer" | "mint" = "balance";
    let loading: boolean = false;
    let errorMessage: string = "";
    let successMessage: string = "";

    // Form data
    let recipient: string = "";
    let transferAmount: string = "";
    let txId: string = "";
    let txSecret: string = "";
    let receiverAddress: string = "";

    /**
     * Load contract ABI from file
     */
    async function loadContractABI(): Promise<void> {
        try {
            const response = await fetch("./abi.json");
            if (!response.ok) {
                throw new Error(`Failed to load ABI: ${response.status}`);
            }
            CONTRACT_ABI = await response.json();
            console.log("Contract ABI loaded successfully");
        } catch (error) {
            console.error("Error loading contract ABI:", error);
            throw new Error(
                "Failed to load contract ABI: " + (error as Error).message,
            );
        }
    }

    /**
     * Connect to MetaMask wallet
     */
    async function connectWallet(): Promise<void> {
        try {
            loading = true;

            // Switch to Sepolia network (11155111)
            try {
                await (window as any).ethereum.request({
                    method: "wallet_switchEthereumChain",
                    params: [{ chainId: "0xaa36a7" }],
                });
                console.log("Switched to Sepolia network");
            } catch (switchError: any) {
                // Network not added to MetaMask, add it
                if (switchError.code === 4902) {
                    await (window as any).ethereum.request({
                        method: "wallet_addEthereumChain",
                        params: [
                            {
                                chainId: "0xaa36a7",
                                chainName: "Sepolia Testnet",
                                rpcUrls: [
                                    "https://ethereum-sepolia.therpc.io",
                                ],
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

            const accounts = await provider!.send("eth_requestAccounts", []);
            userAddress = accounts[0];
            signer = await provider!.getSigner();

            // Create contract instance with signer for writes
            contract = new ethers.Contract(
                CONTRACT_ADDRESS,
                CONTRACT_ABI!,
                signer,
            );

            // Initialize cofhejs client
            await cofhejs.initializeWithEthers({
                ethersProvider: provider,
                ethersSigner: signer,
                environment: "TESTNET",
            });
            cofheClient = cofhejs;

            // Get network name
            const network = await provider!.getNetwork();
            networkName = network.name || "Fhenix Network";

            walletConnected = true;

            // Load initial data
            await refreshBalance();

            loading = false;
            showSuccess("Wallet connected successfully");
        } catch (error) {
            loading = false;
            console.error("Error connecting wallet:", error);
            showError("Failed to connect wallet: " + (error as Error).message);
        }
    }

    /**
     * Refresh user balance and total supply
     */
    async function refreshBalance(): Promise<void> {
        if (!provider || !userAddress || !cofheClient) {
            showError("Please connect your wallet first");
            return;
        }

        try {
            // Create read-only contract instance
            const readContract = new ethers.Contract(
                CONTRACT_ADDRESS,
                CONTRACT_ABI!,
                provider,
            );

            // Try to get encrypted balance using cofhejs
            try {
                // Create permission for accessing encrypted balance
                const permission = await cofheClient.generatePermission(
                    CONTRACT_ADDRESS,
                    provider,
                );

                // Get encrypted balance
                const encryptedBalance = await readContract.balanceOfEncrypted(
                    userAddress,
                    permission,
                );

                // Unseal the encrypted balance
                const unsealed = cofheClient.unseal(
                    CONTRACT_ADDRESS,
                    encryptedBalance,
                );
                balance = ethers.formatUnits(unsealed, 18);
            } catch (balanceError) {
                console.log(
                    "Failed to get encrypted balance:",
                    (balanceError as Error).message,
                );
                // Fallback to regular balance call (will fail for encrypted contracts)
                try {
                    const balanceResult =
                        await readContract.balanceOf(userAddress);
                    balance = ethers.formatEther(balanceResult);
                } catch (fallbackError) {
                    console.log(
                        "Balance is encrypted and requires permission",
                    );
                    balance = "Encrypted (Permission Required)";
                }
            }

            // Try to get encrypted total supply
            try {
                // Create permission for accessing encrypted total supply
                const permission = await cofheClient.generatePermission(
                    CONTRACT_ADDRESS,
                    provider,
                );

                // Get encrypted total supply
                const encryptedTotalSupply =
                    await readContract.totalSupplyEncrypted(permission);

                // Unseal the encrypted total supply
                const unsealed = cofheClient.unseal(
                    CONTRACT_ADDRESS,
                    encryptedTotalSupply,
                );
                totalSupply = ethers.formatUnits(unsealed, 18);
            } catch (supplyError) {
                console.log(
                    "Failed to get encrypted total supply:",
                    (supplyError as Error).message,
                );
                // Fallback to regular total supply call (will fail for encrypted contracts)
                try {
                    const totalSupplyResult = await readContract.totalSupply();
                    totalSupply = ethers.formatEther(totalSupplyResult);
                } catch (fallbackError) {
                    console.log(
                        "Total supply is encrypted and requires permission",
                    );
                    totalSupply = "Encrypted (Permission Required)";
                }
            }
        } catch (error) {
            console.error("Error refreshing balance:", error);
            showError(
                "Failed to refresh balance: " + (error as Error).message,
            );
        }
    }

    /**
     * Handle transfer form submission
     */
    async function handleTransfer(): Promise<void> {
        if (!contract) {
            showError("Please connect your wallet first");
            return;
        }

        if (!ethers.isAddress(recipient)) {
            showError("Invalid recipient address");
            return;
        }

        const amountWei = ethers.parseEther(transferAmount);

        try {
            loading = true;
            const tx = await contract.transfer(recipient, amountWei);
            await tx.wait();

            loading = false;
            showSuccess("Transfer completed successfully");
            recipient = "";
            transferAmount = "";
            await refreshBalance();
        } catch (error) {
            loading = false;
            console.error("Error transferring tokens:", error);
            showError("Transfer failed: " + (error as Error).message);
        }
    }

    /**
     * Fill receiver address with current wallet address
     */
    function useCurrentWalletAddress(): void {
        if (!userAddress) {
            showError("Please connect your wallet first");
            return;
        }

        receiverAddress = userAddress;
        showSuccess("Current wallet address filled in");
    }

    /**
     * Handle mint request form submission
     */
    async function handleMintRequest(): Promise<void> {
        if (!contract) {
            showError("Please connect your wallet first");
            return;
        }

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
            loading = true;

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

            loading = false;
            showSuccess(
                "Mint request submitted successfully! The bridge will process your request.",
            );
            txId = "";
            txSecret = "";
            receiverAddress = "";
        } catch (error) {
            loading = false;
            console.error("Error requesting mint:", error);
            showError("Mint request failed: " + (error as Error).message);
        }
    }

    /**
     * Show error message
     */
    function showError(message: string): void {
        errorMessage = message;
        setTimeout(() => (errorMessage = ""), 10000);
    }

    /**
     * Show success message
     */
    function showSuccess(message: string): void {
        successMessage = message;
        setTimeout(() => (successMessage = ""), 5000);
    }

    /**
     * Copy text to clipboard
     */
    async function copyToClipboard(text: string): Promise<void> {
        try {
            await navigator.clipboard.writeText(text);
            showSuccess("Copied to clipboard");
        } catch (error) {
            showError("Failed to copy to clipboard");
        }
    }

    /**
     * Try to auto-connect if previously connected
     */
    async function tryAutoConnect(): Promise<void> {
        try {
            // Check if already connected
            const accounts = await (window as any).ethereum.request({
                method: "eth_accounts",
            });

            if (accounts.length > 0) {
                console.log(
                    "Auto-connecting to previously connected account...",
                );
                await connectWallet();
            } else {
                console.log("No previously connected accounts found");
            }
        } catch (error) {
            console.log(
                "Auto-connect failed, user will need to connect manually:",
                (error as Error).message,
            );
        }
    }

    onMount(async () => {
        console.log("Initializing app...");
        console.log("Ethers available:", typeof ethers !== "undefined");

        // Check if MetaMask is installed
        if (typeof (window as any).ethereum === "undefined") {
            showError("Please install MetaMask to use this application");
            return;
        }

        try {
            // Load contract ABI first
            await loadContractABI();

            // Request accounts
            provider = new ethers.BrowserProvider((window as any).ethereum);

            // Try to auto-connect if previously connected
            await tryAutoConnect();

            console.log("App initialized successfully");
        } catch (error) {
            console.error("Error initializing app:", error);
            showError(
                "Failed to initialize application: " +
                    (error as Error).message,
            );
        }

        // Handle account changes
        if ((window as any).ethereum) {
            (window as any).ethereum.on(
                "accountsChanged",
                (accounts: string[]) => {
                    if (accounts.length === 0) {
                        // User disconnected
                        location.reload();
                    } else if (accounts[0] !== userAddress) {
                        // Account changed
                        location.reload();
                    }
                },
            );

            (window as any).ethereum.on("chainChanged", () => {
                // Network changed
                location.reload();
            });
        }
    });
</script>

<svelte:head>
    <title>Wrapped Monero (WXMR) Interface</title>
</svelte:head>

<div class="container">
    <header>
        <h1>Wrapped Monero (WXMR)</h1>
        <p>Encrypted balances via Fhenix FHE</p>
    </header>

    <div class="wallet-section">
        <h2>Connect Wallet</h2>
        {#if !walletConnected}
            <button class="btn btn-primary" on:click={connectWallet}>
                Connect MetaMask
            </button>
        {:else}
            <div class="wallet-info">
                <p>
                    <strong>Connected:</strong>
                    <span
                        >{userAddress.substring(0, 6) +
                            "..." +
                            userAddress.substring(38)}</span
                    >
                </p>
                <p>
                    <strong>Network:</strong>
                    <span>{networkName}</span>
                </p>
            </div>
        {/if}
    </div>

    <div class="tabs">
        <button
            class="tab-btn"
            class:active={activeTab === "balance"}
            on:click={() => (activeTab = "balance")}
        >
            My Balance
        </button>
        <button
            class="tab-btn"
            class:active={activeTab === "transfer"}
            on:click={() => (activeTab = "transfer")}
        >
            Transfer
        </button>
        <button
            class="tab-btn"
            class:active={activeTab === "mint"}
            on:click={() => (activeTab = "mint")}
        >
            Mint
        </button>
    </div>

    {#if activeTab === "balance"}
        <div class="tab-content active">
            <h3>My WXMR Balance</h3>
            <div class="balance-display">
                <p>
                    <strong>Balance:</strong>
                    <span>{balance}</span> WXMR
                </p>
                <p>
                    <strong>Total Supply:</strong>
                    <span>{totalSupply}</span> WXMR
                </p>
            </div>
            <button class="btn btn-secondary" on:click={refreshBalance}>
                Refresh Balance
            </button>
        </div>
    {/if}

    {#if activeTab === "transfer"}
        <div class="tab-content active">
            <h3>Transfer WXMR</h3>
            <form on:submit|preventDefault={handleTransfer}>
                <div class="form-group">
                    <label for="recipient">Recipient Address:</label>
                    <input
                        type="text"
                        id="recipient"
                        bind:value={recipient}
                        placeholder="0x..."
                        required
                    />
                </div>
                <div class="form-group">
                    <label for="amount">Amount:</label>
                    <input
                        type="number"
                        id="amount"
                        bind:value={transferAmount}
                        placeholder="0.0"
                        min="0"
                        step="0.000001"
                        required
                    />
                </div>
                <button type="submit" class="btn btn-primary">
                    Transfer
                </button>
            </form>
        </div>
    {/if}

    {#if activeTab === "mint"}
        <div class="tab-content active">
            <h3>Request Mint</h3>
            <p>
                Request minting of WXMR tokens by providing Monero transaction
                details.
            </p>

            <div class="bridge-address">
                <h4>Bridge Monero Address:</h4>
                <div class="address-display">
                    <code
                        >74Di3cYaTj7DG5D7ucHEeiSZzrH9kyrFX8ujg2S3ydoZQEkKhpFjGkGLcpenYEHMW1aYNQcy6n75MbDfFwch4657E8WjVhE</code
                    >
                    <button
                        type="button"
                        class="btn btn-secondary copy-btn"
                        on:click={() =>
                            copyToClipboard(
                                "74Di3cYaTj7DG5D7ucHEeiSZzrH9kyrFX8ujg2S3ydoZQEkKhpFjGkGLcpenYEHMW1aYNQcy6n75MbDfFwch4657E8WjVhE",
                            )}
                    >
                        Copy
                    </button>
                </div>
            </div>

            <form on:submit|preventDefault={handleMintRequest}>
                <div class="form-group">
                    <label for="txId">Monero Transaction ID:</label>
                    <input
                        type="text"
                        id="txId"
                        bind:value={txId}
                        placeholder="Monero txid (hex)"
                        required
                    />
                </div>
                <div class="form-group">
                    <label for="txSecret">Transaction Secret Key:</label>
                    <input
                        type="text"
                        id="txSecret"
                        bind:value={txSecret}
                        placeholder="Transaction secret key (hex)"
                        required
                    />
                </div>
                <div class="form-group">
                    <label for="receiverAddress">Receiver Address:</label>
                    <input
                        type="text"
                        id="receiverAddress"
                        bind:value={receiverAddress}
                        placeholder="0x..."
                        required
                    />
                    <button
                        type="button"
                        class="btn btn-secondary"
                        on:click={useCurrentWalletAddress}
                    >
                        Send to current wallet address
                    </button>
                </div>
                <button type="submit" class="btn btn-primary">
                    Request Mint
                </button>
            </form>

            <div class="mint-info">
                <h4>How it works:</h4>
                <ol>
                    <li>Send Monero to the bridge address above</li>
                    <li>
                        Get the transaction ID and secret key from your Monero
                        wallet
                    </li>
                    <li>Submit a mint request with these details</li>
                    <li>The bridge will verify and mint WXMR tokens</li>
                </ol>
            </div>
        </div>
    {/if}

    {#if loading}
        <div class="loading">
            <div class="spinner"></div>
            <p>Processing transaction...</p>
        </div>
    {/if}

    {#if errorMessage}
        <div class="error-message">
            <span>{errorMessage}</span>
            <button on:click={() => (errorMessage = "")}>×</button>
        </div>
    {/if}

    {#if successMessage}
        <div class="success-message">
            <span>{successMessage}</span>
            <button on:click={() => (successMessage = "")}>×</button>
        </div>
    {/if}
</div>
