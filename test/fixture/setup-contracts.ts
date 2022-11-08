import { deployments } from "hardhat";
import {
    MockUSDT__factory,
    MockV3Aggregator__factory,
    EnJoyPrediction__factory
} from "../../typechain-types";

export const setupContracts = deployments.createFixture(
    async ({ deployments, ethers }, options) => {
        await deployments.fixture(["test"]);
        const signers = await ethers.getSigners();
        const deployer = signers[0];
        const usdtArtifact = await deployments.get("MockUSDT");
        const usdtContract = MockUSDT__factory.connect(usdtArtifact.address, deployer);
        const aggArtifact = await deployments.get("MockV3Aggregator");
        const aggContract = MockV3Aggregator__factory.connect(aggArtifact.address, deployer);
        const enjoyArtifact = await deployments.get("EnJoyPrediction");
        const enjoyContract = EnJoyPrediction__factory.connect(enjoyArtifact.address, deployer);
        const tx = await usdtContract.batchApprove(signers.map(s => s.address), enjoyArtifact.address);
        await tx.wait();
        return {
            signers,
            aggContract,
            enjoyContract,
        }
    }
);
