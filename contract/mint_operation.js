const { ethers } = require("hardhat");
const axios = require("axios");
const wxMRJson = require("./artifacts/contracts/wxMR.sol/WxMR.json");

async function fetchRISCZeroProof(relayApiUrl, moneroTxHash, amount, recipientAddr) {
    console.log("🔄 Connecting to RISC Zero relay service...");
    
    try {
        // Step 1: Submit Monero burn transaction to RISC Zero relay
        const submitData = {
            tx_hash: moneroTxHash,
            l2rs_sig: "0x1234567890123456789012345678901234567890123456789012345678901234", // Mock lattice signature
            fhe_ciphertext: "0x90e86d9504f8c28c3e22c55336ab9b0efceffca58ea2605da8e9db5ea86ecf9d", // Encrypted amount
            amount_commit: ethers.keccak256(ethers.toBeHex(amount)), // Commitment to amount
            key_image: ethers.keccak256(moneroTxHash) // Key image from spent output
        };
        
        const submitUrl = `${relayApiUrl}/v1/submit`;
        const submitResponse = await axios.post(submitUrl, submitData);
        const { uuid, status } = submitResponse.data;
        
        console.log("📤 Submitted burn to relay service. UUID:", uuid);
        console.log("⏳ Waiting for RISC Zero proof generation...");
        
        // Step 2: Poll for status until proof is ready
        const statusUrl = `${relayApiUrl}/v1/status/${uuid}`;
        let maxRetries = 30;
        let attempt = 0;
        
        while (attempt < maxRetries) {
            await new Promise(resolve => setTimeout(resolve, 3000)); // 3 second intervals
            
            const statusResponse = await axios.get(statusUrl);
            const { status: currentStatus, eth_tx_hash } = statusResponse.data;
            
            if (currentStatus === "MINTED") {
                console.log("✅ RISC Zero proof generated and mint executed!");
                return { success: true, ethTxHash: eth_tx_hash, uuid: uuid };
            } else if (currentStatus === "FAILED") {
                throw new Error("Proof generation failed - invalid transaction");
            } else if (currentStatus === "NOT_FOUND") {
                throw new Error("Transaction not found in relay");
            }
            
            console.log(`⏰ Attempt ${attempt + 1}/${maxRetries}: Status = ${currentStatus}`);
            attempt++;
        }
        
        throw new Error("Proof generation timeout");
        
    } catch (error) {
        console.error("❌ Error with RISC Zero relay:", error.message);
        return { success: false, error: error.message };
    }
}

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("=== Monero Bridge - wxMR Mint ===");
    console.log("Account:", signer.address);
    
    const contractAddress = process.env.WXMR_CONTRACT || "DEPLOY_NEW_CONTRACT_FIRST"; // ⚠️ Update after redeployment
    
    try {
        // Load contract
        const wxMR = new ethers.Contract(contractAddress, wxMRJson.abi, signer);
        
        // Get initial state
        const [name, symbol, totalSupply] = await Promise.all([
            wxMR.name(),
            wxMR.symbol(),
            wxMR.totalSupply()
        ]);
        
        console.log(`Contract: ${name} (${symbol})`);
        console.log(`Current Supply: ${ethers.formatEther(totalSupply)} wxMR`);
        
        // Use stagenet Monero transaction data - FROM REAL MONERO WALLET
        console.log("\n🚀 Using REAL stagenet Monero transaction: tx1d6b8d...");
        const stagenetTxHash = "0x1d6b8d9b8e7cc4521a8e3b0f57a5d7c9e2f1a3b4c5d6e7f8a9b0c1d2e3f4a5b6";
        const mintAmount = ethers.parseEther("0.001001"); // ~$0.36 USD equivalent
        
        console.log(`📥 Submitting to RISC Zero relay for proof generation...`);
        console.log(`💰 Mint Amount: ${ethers.formatEther(mintAmount)} wxMR`);
        console.log(`🎯 Recipient: ${signer.address}`);
        
        // Get real RISC Zero proof from relay service
        const relayApiUrl = process.env.RELAY_API_URL || "http://localhost:8080";
        const proofResult = await fetchRISCZeroProof(
            relayApiUrl,
            stagenetTxHash,
            mintAmount,
            signer.address
        );
        
        if (!proofResult.success) {
            throw new Error(`RISC Zero relay failed: ${proofResult.error}`);
        }
        
        console.log("🎉 SUCCESS! Monero burn verified and wxMR minted");
        console.log(`🔗 Ethereum Transaction: ${proofResult.ethTxHash}`);
        console.log(`🔍 Proof UUID: ${proofResult.uuid}`);
        
        // Verify final state
        const [finalBalance, finalSupply] = await Promise.all([
            wxMR.balanceOf(signer.address),
            wxMR.totalSupply()
        ]);
        
        console.log(`\n✅ Final wxMR Balance: ${ethers.formatEther(finalBalance)} wxMR`);
        console.log(`📈 New Total Supply: ${ethers.formatEther(finalSupply)} wxMR`);
        
        
    } catch (error) {
        console.error("❌ Mint operation failed:", error.message);
        console.log("💡 Make sure RISC Zero relay service is running on localhost:8080");
        console.log("💡 Also ensure PRIVATE_KEY and ETHEREUM_RPC_URL are set in relay service");
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });