import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { btcAggregatorMap, usdtAddressMap } from "../misc/params";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  if (!(chainId in btcAggregatorMap)) {
    console.log("unsupported chain");
    return;
  }
  const usdtAddress = usdtAddressMap[chainId];
  const btcAggregator = btcAggregatorMap[chainId];
  await deploy("EnJoyPrediction", {
    from: deployer,
    log: true,
    args: [
      usdtAddress,
      btcAggregator,
    ]
  });
};
export default func;
func.tags = ['main']