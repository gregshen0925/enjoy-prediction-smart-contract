import { deployments } from "hardhat";
import {
    MockUSDT__factory,
    MockV3Aggregator__factory,
    EnJoyPrediction__factory
} from "../../typechain-types";

const HOUR = 3600;
const DAY = 24 * HOUR;
const OFFSET = 11 * HOUR;

const getNextSettleTimestamp = (realTimestamp: number): number => {
    const timestamp = Math.round(realTimestamp / 1000);
    return Math.ceil((timestamp - OFFSET) / DAY) * DAY + OFFSET;
}

export const shiftDay = (timestamp: number, shift: number): number => {
    return Math.round(timestamp + shift * DAY);
}

export enum TableResult {
    NULL,
    LONG,
    SHORT,
    DRAW,
}

export const setupContracts = deployments.createFixture(
    async ({ deployments, ethers }, options) => {
        await deployments.fixture(["local"]);
        const signers = await ethers.getSigners();
        const deployer = signers[0];
        const usdtArtifact = await deployments.get("MockUSDT");
        const usdtContract = MockUSDT__factory.connect(usdtArtifact.address, deployer);
        const oracleArtifact = await deployments.get("MockV3Aggregator");
        const oracleContract = MockV3Aggregator__factory.connect(oracleArtifact.address, deployer);
        const enjoyArtifact = await deployments.get("EnJoyPrediction");
        const enjoyContract = EnJoyPrediction__factory.connect(enjoyArtifact.address, deployer);
        const tx = await usdtContract.batchApprove(signers.map(s => s.address), enjoyArtifact.address);
        await tx.wait();
        const pivotTime = getNextSettleTimestamp(new Date().valueOf());
        const nowTime = Math.floor(new Date().valueOf() / 1000);
        return {
            signers,
            usdtContract,
            oracleContract,
            enjoyContract,
            pivotTime,
            nowTime,
        }
    }
);
