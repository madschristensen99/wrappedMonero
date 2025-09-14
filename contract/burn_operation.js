const { ethers } = require("hardhat");
const wxMRJson = require("./artifacts/contracts/wxMR.sol/WxMR.json");

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("Burn operation using account:", signer.address);
    
    const contractAddress = "0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5";
    const wxMR = new ethers.Contract(contractAddress, wxMRJson.abi, signer);
    
    console.log("=== Burn wxMR Operation ===");
    
    try {
        // Get contract details
        const name = await wxMR.name();
        const symbol = await wxMR.symbol();
        const totalSupply = await wxMR.totalSupply();
        
        console.log("Contract:", name, "(", symbol, ")");
        console.log("Current Total Supply:", ethers.formatEther(totalSupply), "wxMR");
        
        // Check current balance
        const balance = await wxMR.balanceOf(signer.address);
        console.log("Your wxMR Balance:", ethers.formatEther(balance), "wxMR");
        
        if (balance === 0n) {
            console.log("❌ No wxMR tokens to burn");
            console.log("💡 You need to mint wxMR first before burning");
            return;
        }
        
        console.log("\n🔥 Attempting to burn wxMR...")
        
        // For burning, we just need the amount to burn
        const burnAmount = balance > ethers.parseEther("0.5") 
            ? ethers.parseEther("0.5") 
            : balance; // Burn 0.5 wxMR or full balance if less
        
        console.log("Parameters:")
        console.log("- Amount to burn:", ethers.formatEther(burnAmount), "wxMR");
        
        try {
            const tx = await wxMR.burn(burnAmount);
            
            console.log("📤 Transaction submitted:", tx.hash);
            console.log("⏳ Waiting for confirmation...")
            
            const receipt = await tx.wait();
            console.log("✅ Burn transaction confirmed!");
            console.log("📊 Gas used:", receipt.gasUsed.toString());
            
            // Check new balance
            const newBalance = await wxMR.balanceOf(signer.address);
            console.log("💰 Remaining wxMR Balance:", ethers.formatEther(newBalance), "wxMR");
            
            const newTotalSupply = await wxMR.totalSupply();
            console.log("📉 Total Supply after burn:", ethers.formatEther(newTotalSupply), "wxMR");
            
        } catch (burnError) {
            console.log("❌ Burn failed:", burnError.message);
            console.log("💡 This might be due to insufficient balance or reverted transaction");
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