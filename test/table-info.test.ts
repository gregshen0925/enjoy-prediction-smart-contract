import { expect } from "chai";
import { network } from "hardhat";
import { setupContracts } from "./fixture/setup-contracts";

const hour = 3600000;
const day = 24 * hour;
const offset = 11 * hour;

const blockDay = 86400;

const getNextSettleTimestamp = (timestamp: number): number => {
    const nextSettleTimestamp = Math.ceil((timestamp - offset) / day) * day + offset;
    return Math.round(nextSettleTimestamp / 1000);
}

describe("Table Info test", function () {
    it("Positive: table info correct after settlement", async function () {
        const { enjoyContract, aggContract } = await setupContracts();
        const settleTimestamp = getNextSettleTimestamp(new Date().valueOf()) + 2;
        await network.provider.send("evm_setNextBlockTimestamp", [settleTimestamp]);
        await network.provider.send("evm_mine");
        await (await enjoyContract.settle()).wait();
        const waitingTableInfo = await enjoyContract.getTableInfo(settleTimestamp - 2 * blockDay);
        expect(waitingTableInfo.result).equal(1);
        expect(waitingTableInfo.startPrice).equal(0);
        const stakingTableInfo = await enjoyContract.getTableInfo(settleTimestamp - blockDay);
        expect(stakingTableInfo.result).equal(0);
        expect(stakingTableInfo.startPrice).equal(0);
        const currentTableInfo = await enjoyContract.getTableInfo(settleTimestamp);
        expect(currentTableInfo.result).equal(0);
        expect(currentTableInfo.startPrice).equal(await aggContract.latestAnswer());
    });
});
