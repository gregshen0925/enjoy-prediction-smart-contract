import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { ethers } = hre;
  const { deploy } = hre.deployments;
  const chainId = await hre.getChainId();
  if (chainId === '1') return;
  const { deployer } = await hre.getNamedAccounts();
  const decimals = 8;
  await deploy("MockV3Aggregator", {
    from: deployer,
    log: true,
    args: [
      decimals,
      ethers.BigNumber.from(10).pow(decimals).mul(20000)
    ],
  });
};
export default func;