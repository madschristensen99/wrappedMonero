const { ethers } = require("hardhat");

async function main() {
  // Production RISC Zero verifier (Base Sepolia) - official contract
  const riscZeroVerifier = "0x925d833ec39bfb9d4ba0fcd23f9b7f4a601c2235";
  
  // Image ID - from actual RISC Zero guest program
  const imageId = "0x8c7c3ed469b05e3336233d0d682245566d98f867af2856d0436145ba8f72e423";
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying wxMR with production RISC Zero verifier...");
  console.log("Deployer:", deployer.address);
  console.log("RISC Zero Verifier:", riscZeroVerifier);
  console.log("Image ID:", imageId);
  
  const WxMR = await ethers.getContractFactory("WxMR");
  const wxMR = await WxMR.deploy(
    riscZeroVerifier,
    imageId,
    "Wrapped Monero",
    "wxMR"
  );
  
  await wxMR.waitForDeployment();
  const address = await wxMR.getAddress();
  
  console.log("");
  console.log("🎉 wxMR CONTRACT DEPLOYED WITH PRODUCTION RISC ZERO!");
  console.log("=============================================");
  console.log("Contract Address:", address);
  console.log("RISC Zero Verifier:", riscZeroVerifier);
  console.log("Image ID:", imageId);
  console.log("");
  console.log("⚡ NEXT STEPS:");
  console.log(`export WXMR_CONTRACT=${address}  # For your environment`);
  console.log(`# Then update all config files with this address`);
  
  return address;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });