import { expect } from "chai";
import { network, ethers } from "hardhat";
import {
    setupContracts,
    shiftDay,
    TableResult,
} from "./fixture/setup-contracts";

const setBlockTimestamp = async (timestamp: number): Promise<any> => {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
    return await network.provider.send("evm_mine");
}

const usdt = (amount: number): number => amount * 1000000;

const { BigNumber } = ethers;

describe("Simple Flow", function () {
    it("Predict -> settle -> claim", async function () {
        const { signers, usdtContract, enjoyContract, oracleContract, pivotTime, nowTime } = await setupContracts();
        let tableInfo, price;

        // players predict
        await enjoyContract.connect(signers[1]).predict(true, usdt(1));
        await expect(enjoyContract.connect(signers[1]).predict(true, usdt(2)))
            .to.be.revertedWith("already predicted");
        await enjoyContract.connect(signers[4]).predict(false, usdt(4));
        await expect(enjoyContract.connect(signers[7]).predict(true, usdt(9)))
            .to.be.revertedWith("stake out of range");
        tableInfo = await enjoyContract.getTableInfo(nowTime);
        // check current table infos
        expect(tableInfo.result).equal(TableResult.NULL);
        expect(tableInfo.startPrice).equal(0);
        expect(tableInfo.longPool).equal(usdt(1));
        expect(tableInfo.shortPool).equal(usdt(4));
        expect(tableInfo.playerCount).equal(2);

        // settle
        await setBlockTimestamp(pivotTime);
        await (await enjoyContract.settle()).wait();
        price = await oracleContract.latestAnswer();
        // check table infos
        tableInfo = await enjoyContract.getTableInfo(shiftDay(nowTime, -1));
        expect(tableInfo.result).equal(TableResult.DRAW);
        expect(tableInfo.startPrice).equal(0);
        tableInfo = await enjoyContract.getTableInfo(nowTime);
        expect(tableInfo.result).equal(TableResult.NULL);
        expect(tableInfo.startPrice).equal(price);
        await expect(enjoyContract.settle())
            .revertedWith("settle too early");

        // price rise and settle
        await setBlockTimestamp(shiftDay(pivotTime, 0.5));
        await (await oracleContract.updateAnswer(price.add(123))).wait();
        await expect(enjoyContract.connect(signers[3]).settle())
            .to.be.revertedWith("settle too early");
        await setBlockTimestamp(shiftDay(pivotTime, 1));
        await (await enjoyContract.connect(signers[9]).settle()).wait();
        // check table infos
        tableInfo = await enjoyContract.getTableInfo(nowTime);
        expect(tableInfo.result).equal(TableResult.LONG);
        tableInfo = await enjoyContract.getTableInfo(pivotTime);
        price = await oracleContract.latestAnswer();
        expect(tableInfo.result).equal(TableResult.NULL);
        expect(tableInfo.startPrice).equal(price);

        // claim
        expect(await enjoyContract.getPlayerUnclaimReward(signers[1].address))
            .equal(usdt(5));
        expect(await enjoyContract.getPlayerUnclaimReward(signers[4].address))
            .equal(usdt(0));
        await (await enjoyContract.connect(signers[1]).claim()).wait();
        expect(await usdtContract.balanceOf(signers[1].address))
            .equal(BigNumber.from(usdt(5)).mul(99).div(100).add(usdt(99)));
        expect(await usdtContract.balanceOf(signers[4].address)).equal(usdt(96));
    });
});
