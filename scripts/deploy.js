// Deploys the two contracts in the correct order (DRAFT).
//   1. RoleRegistry, with the deployer as the first regulator
//   2. CertificateRegistry, linked to RoleRegistry
// Usage: npx hardhat run scripts/deploy.js --network localhost
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Step 1: RoleRegistry (deployer becomes the regulator)
  const RoleRegistry = await hre.ethers.getContractFactory("RoleRegistry");
  const roles = await RoleRegistry.deploy(deployer.address);
  await roles.waitForDeployment();
  console.log("RoleRegistry deployed to:", await roles.getAddress());

  // Step 2: CertificateRegistry, pointing to RoleRegistry for permission checks
  const CertificateRegistry = await hre.ethers.getContractFactory("CertificateRegistry");
  const certs = await CertificateRegistry.deploy(await roles.getAddress());
  await certs.waitForDeployment();
  console.log("CertificateRegistry deployed to:", await certs.getAddress());

  // TODO (next milestone): register sample producers and buyers,
  // set the Data Checker account, and save addresses to .env
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
