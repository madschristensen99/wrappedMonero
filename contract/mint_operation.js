const { ethers } = require("hardhat");
const wxMRJson = require("./artifacts/contracts/wxMR.sol/WxMR.json");

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("Mint operation using account:", signer.address);
    
    const contractAddress = "0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5";
    const wxMR = new ethers.Contract(contractAddress, wxMRJson.abi, signer);
    
    console.log("=== Mint wxMR Operation ===");
    
    try {
        // Get contract details
        const name = await wxMR.name();
        const symbol = await wxMR.symbol();
        const totalSupply = await wxMR.totalSupply();
        
        console.log("Contract:", name, "(", symbol, ")");
        console.log("Current Total Supply:", ethers.formatEther(totalSupply), "wxMR");
        console.log("Your Address:", signer.address);
        
        // For minting, we need:
        // - seal (bytes): A zk-SNARK proof of the Monero burn
        // - amount (uint256): Amount of wxMR to mint (in wei)
        // - KI_hash (bytes32): Key Image hash from Monero transaction
        // - amount_commit (uint256): Amount commitment from Monero transaction
        
        console.log("\n🔥 Attempting to mint wxMR...")
        console.log("⚠️  This requires zk-SNARK proof of Monero burn transaction");
        
        // For testing, we'll simulate the required parameters
        // In production, these would come from the Monero burn transaction proof
        const mockSeal = "0x1234567890abcdef"; // This should be zk-SNARK proof
        const mintAmount = ethers.parseEther("1.0"); // 1 wxMR
        const mockKIHash = ethers.keccak256(ethers.toUtf8Bytes("mock_key_image"));
        const mockAmountCommit = ethers.parseEther("1.0");
        
        try {
            console.log("Parameters:")
            console.log("- Seal:", mockSeal);
            console.log("- Amount:", ethers.formatEther(mintAmount), "wxMR");
            console.log("- KI Hash:", mockKIHash);
            console.log("- Amount Commit:", ethers.formatEther(mockAmountCommit), "wxMR");
            
            const tx = await wxMR.mint(
                mockSeal,
                mintAmount,
                mockKIHash,
                mockAmountCommit
            );
            
            console.log("📤 Transaction submitted:", tx.hash);
            console.log("⏳ Waiting for confirmation...")
            
            const receipt = await tx.wait();
            console.log("✅ Mint transaction confirmed!");
            console.log("📊 Gas used:", receipt.gasUsed.toString());
            
            // Check new balance
            const newBalance = await wxMR.balanceOf(signer.address);
            console.log("💰 New wxMR Balance:", ethers.formatEther(newBalance), "wxMR");
            
            const newTotalSupply = await wxMR.totalSupply();
            console.log("📈 Total Supply after mint:", ethers.formatEther(newTotalSupply), "wxMR");
            
        } catch (mintError) {
            console.log("❌ Mint failed:", mintError.message);
            console.log("💡 This might be due to invalid zk-SNARK proof or spent key image");
        }
        
    } catch (error) {
        console.error("Contract interaction error:", error);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });