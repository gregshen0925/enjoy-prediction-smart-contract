import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-deploy";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.13",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20_000,
      },
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
  networks: {
    // mainnet
    polygon: {
      url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.POLYGON_API_KEY ?? ""}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    // testnet
    mumbai: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${process.env.POLYGON_MUMBAI_API_KEY ?? ""}`,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    // devnet
    hardhat: {
      mining: {
        auto: true,
        interval: 1000,
      },
      chainId: 1337
    },
  },
  etherscan: {
    apiKey: process.env.POLYGON_API_KEY,
  },
};

export default config;
