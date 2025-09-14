const { ethers } = require("hardhat");
const wxMRJson = require("./artifacts/contracts/wxMR.sol/WxMR.json");

async function main() {
    const [signer] = await ethers.getSigners();
    console.log("Interacting with contract using account:", signer.address);
    
    const contractAddress = "0x5A8Bde0AE3F9871e509264E9152B77841EfE10c5";
    const wxMR = new ethers.Contract(contractAddress, wxMRJson.abi, signer);
    
    console.log("=== Contract Interaction Test ===");
    
    try {
        // Check contract details
        const name = await wxMR.name();
        const symbol = await wxMR.symbol();
        const totalSupply = await wxMR.totalSupply();
        
        console.log("Contract Name:", name);
        console.log("Symbol:", symbol);
        console.log("Total Supply:", ethers.formatEther(totalSupply), "wxMR");
        
        // Try to query balance (this will likely be 0 initially)
        const balance = await wxMR.balanceOf(signer.address);
        console.log("Your wxMR Balance:", ethers.formatEther(balance), "wxMR");
        
        // Check if we can attempt a mock mint (this might fail but we'll try)
        try {
            console.log("\n=== Attempting Mint Operation ===");
            const tx = await wxMR.mint(signer.address, ethers.parseEther("1.0"));
            console.log("Mint tx hash:", tx.hash);
            await tx.wait();
            console.log("Mint successful!");
            
            // Check new balance
            const newBalance = await wxMR.balanceOf(signer.address);
            console.log("New wxMR Balance:", ethers.formatEther(newBalance), "wxMR");
        } catch (mintError) {
            console.log("Mint failed (expected):", mintError.message);
        }
        
        // Try burn operation (if we have balance)
        if (balance > 0) {
            try {
                console.log("\n=== Attempting Burn Operation ===");
                const burnTx = await wxMR.burn(ethers.parseEther("0.1"));
                console.log("Burn tx hash:", burnTx.hash);
                await burnTx.wait();
                console.log("Burn successful!");
                
                const finalBalance = await wxMR.balanceOf(signer.address);
                console.log("Final wxMR Balance:", ethers.formatEther(finalBalance), "wxMR");
            } catch (burnError) {
                console.log("Burn failed:", burnError.message);
            }
        } else {
            console.log("\nNo wxMR to burn");
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