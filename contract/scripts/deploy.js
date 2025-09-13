const { ethers } = require("hardhat");

async function main() {
  // Mock RiscZero verifier address for hackathon
  const mockVerifier = "0x1234567890123456789012345678901234567890";
  
  // Mock image ID - in production this comes from RISC Zero guest compilation
  const mockImageId = "0x0000000000000000000000000000000000000000000000000000000000000000";
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  
  const WxMR = await ethers.getContractFactory("WxMR");
  const wxMR = await WxMR.deploy(
    mockVerifier,
    mockImageId,
    "Wrapped Monero",
    "wxMR"
  );
  
  await wxMR.deployed();
  
  console.log("wxMR deployed to:", wxMR.address);
  console.log("Verifier:", await wxMR.verifier());
  console.log("ImageID:", await wxMR.imageId());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });