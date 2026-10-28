// Hardhat configuration: compiler version and networks.
// Private values (RPC URL, private key) are read from .env, never written here.
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const { SEPOLIA_RPC_URL, DEPLOYER_PRIVATE_KEY } = process.env;

module.exports = {
  solidity: "0.8.24",
  networks: {
    // Local blockchain started with `npx hardhat node`
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    // Public test network (free test ETH from a faucet)
    sepolia: {
      url: SEPOLIA_RPC_URL || "",
      accounts: DEPLOYER_PRIVATE_KEY ? [DEPLOYER_PRIVATE_KEY] : [],
    },
  },
};
