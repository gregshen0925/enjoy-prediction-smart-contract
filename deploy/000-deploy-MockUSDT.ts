import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const signers = await hre.ethers.getSigners();
  const users = signers.map(signer => signer.address);
  await deploy("MockUSDT", {
    from: deployer,
    log: true,
    args: [users],
  });
};
export default func;