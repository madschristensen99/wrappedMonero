<script lang="ts">
    import { onMount } from "svelte";
    import { ethers } from "ethers";
    import { cofhejs, FheTypes, Encryptable } from "cofhejs/web";
    import type { BrowserProvider, JsonRpcSigner, Contract } from "ethers";

    // Contract ABI will be loaded from abi.json
    let CONTRACT_ABI: any[] | null = null;

    // Actual deployed contract address
    const CONTRACT_ADDRESS: string =
        "0xb087c13f03b0b5a303d919cbf4d732b835afe434";

    let provider: BrowserProvider | null = null;
    let contract: Contract | null = null;
    let userAddress: string = "";
    let cofheClient: any = null;

    // UI state
    let walletConnected: boolean = false;
    let networkName: string = "";
    let balance: string = "-";
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
        const response = await fetch("./abi.json");
        if (!response.ok) {
            throw new Error(`Failed to load ABI: ${response.status}`);
        }
        CONTRACT_ABI = await response.json();
        console.log("Contract ABI loaded successfully");
    }

    /**
     * Connect to MetaMask wallet
     */
    async function connectWallet(): Promise<void> {
        try {
            loading = true;

            // Switch to Sepolia network (11155111)

            await (window as any).ethereum.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: "0xaa36a7" }],
            });
            console.log("Switched to Sepolia network");

            // Create contract instance with signer for writes
            contract = new ethers.Contract(
                CONTRACT_ADDRESS,
                CONTRACT_ABI!,
                // signer,
            );

            console.log("Found address", {userAddress});

            const provider = new ethers.BrowserProvider((window as any).ethereum);
            const signer: JsonRpcSigner = await provider.getSigner();
            // Initialize cofhejs client with ethers
            const result = await cofhejs.initializeWithEthers({
                ethersProvider: provider,
                ethersSigner: signer,
                environment: "TESTNET",
            });
            console.log(result);
            if (!result.success) {
                throw new Error(`Couldn't initialize cofhejs ${result.error}`);
            }
            console.log("cofhejs initialized", {result});
            cofheClient = cofhejs;

            // Get network name
            const network = await provider!.getNetwork();
            networkName = network.name || "Fhenix Network";

            const accounts = await provider.send("eth_requestAccounts", []);
            userAddress = accounts[0];

            walletConnected = true;

            // Load initial data
            await refreshBalance();

            showSuccess("Wallet connected successfully");
        } finally {
            loading = false;
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

        // Create read-only contract instance
        const readContract = new ethers.Contract(
            CONTRACT_ADDRESS,
            CONTRACT_ABI!,
            provider,
        );

        // Get encrypted balance using cofhejs
        const result = await cofhejs.createPermit({
            type: "self",
            issuer: userAddress,
        });
        if (!result.success) {
            throw new Error("Couldn't create permit", result.error.toString());
        }

        console.log("Created permit:", result);

        // Get encrypted balance
        const encryptedBalance = await readContract.balanceOfEncrypted(
            userAddress,
            result,
        );

        console.log("Encrypted balance result:", encryptedBalance);

        // When creating a permit cofhejs will use it automatically, but you can pass it manually as well
        const unsealed = await cofhejs.unseal(
            encryptedBalance,
            FheTypes.Uint64,
            result.data.issuer,
            result.data.getHash()
        );

        console.log("Unsealed balance:", unsealed);
        balance = ethers.formatUnits(unsealed.toString(), 12); // Monero has 12 decimals
    }

    /**
     * Handle transfer form submission
     */
    async function handleTransfer(): Promise<void> {
        // TODO
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
        } finally {
            loading = false;
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
        await navigator.clipboard.writeText(text);
        showSuccess("Copied to clipboard");
    }

    /**
     * Try to auto-connect if previously connected
     */
    async function tryAutoConnect(): Promise<void> {
        // Check if already connected
        const accounts = await (window as any).ethereum.request({
            method: "eth_accounts",
        });

        if (accounts.length == 0) {
            console.log("No previously connected accounts found");
        }
        console.log(
            "Auto-connecting to previously connected account...",
        );
        await connectWallet();
    }

    onMount(async () => {
        console.log("Initializing app...");
        console.log("Ethers available:", typeof ethers !== "undefined");

        // Check if MetaMask is installed
        if (typeof (window as any).ethereum === "undefined") {
            showError("Please install MetaMask to use this application");
            return;
        }

        // Load contract ABI first
        await loadContractABI();

        // Request accounts

        // Try to auto-connect if previously connected
        await tryAutoConnect();

        console.log("App initialized successfully");

        // Handle account changes
        if (!(window as any).ethereum) {
            return;
        }
        (window as any).ethereum.on("accountsChanged",
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
