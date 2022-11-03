import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { settingsMap, usdtAddressMap, btcAggregatorMap } from "../misc/params";

const initStartTime = 1665745200;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;
  const { deployer } = await hre.getNamedAccounts();
  const chainId = await hre.getChainId();
  if (!(chainId in settingsMap)) {
    console.log("unsupported chain");
    return;
  }
  const settings = settingsMap[chainId];
  const usdtAddress = usdtAddressMap[chainId];
  const btcAggregator = btcAggregatorMap[chainId];
  const initStage = (chainId === '137')?
    Math.floor((initStartTime - settings.timeOffset)/settings.timeInterval):
    Math.floor((new Date().valueOf()/1000 - settings.timeOffset)/settings.timeInterval);
  await deploy("EnJoyPrediction", {
    from: deployer,
    log: true,
    args: [
      usdtAddress,
      btcAggregator,
      settings,
      initStage,
    ]
  });
};
export default func;
func.tags = ['main', 'test']