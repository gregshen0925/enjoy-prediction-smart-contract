//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./utils/EnumerableMap.sol";

/**
 * @author InJoy Labs
 * @title A game about predicting the price of BTC
 */
contract EnJoyPrediction {
    using EnumerableMap for EnumerableMap.UintToUintMap;

    error StakeOutOfRange();
    error AlreadyPredicted();
    error SettleTooEarly();

    uint32 private constant MIN_STAKE = 1_000_000; // 1 USDT

    uint32 private constant MAX_STAKE = 5_000_000; // 5 USDT

    uint32 private constant DAY_TIME_OFFSET = 11 * 60 * 60; // 7 p.m. UTC+8

    struct StakeInfo {
        uint32 stakeAmount;
        uint8 prediction;
    }

    enum TableResult {
        NULL,
        LONG,
        SHORT,
        DRAW
    }

    struct TableInfo {
        TableResult result;
        uint80 startPrice;
        uint80 stakeForLong;
        uint80 stakeForShort;
    }

    IERC20 private immutable _usdt;

    AggregatorV3Interface private immutable _btcPriceFeed;

    mapping(address => EnumerableMap.UintToUintMap) private _stakeInfoMapOf;

    mapping(uint256 => TableInfo) private _tableInfoMap;

    constructor(IERC20 usdtAddress, AggregatorV3Interface btcAggregator) {
        _usdt = usdtAddress;
        _btcPriceFeed = btcAggregator;
    }

    /**
     * Execution Functions
     */

    /// @dev Predict BTC price with certain amount of USDT
    function predict(bool predictLong, uint32 stakeAmount) public {
        uint256 tableId = _getCurrentTableId();
        // checks
        if (stakeAmount > MAX_STAKE || stakeAmount < MIN_STAKE)
            revert StakeOutOfRange();
        if (_stakeInfoMapOf[msg.sender].contains(tableId))
            revert AlreadyPredicted();

        // get current table info
        TableInfo storage tableInfo = _tableInfoMap[tableId];

        // stake USDT to contract
        _usdt.transferFrom(msg.sender, address(this), stakeAmount);

        // update table info
        if (predictLong) tableInfo.stakeForLong += stakeAmount;
        else tableInfo.stakeForShort += stakeAmount;

        // add stake info to player's profolio
        uint256 serialNumber = _serializeStakeInfo(
            StakeInfo(
                stakeAmount,
                predictLong ? uint8(TableResult.LONG) : uint8(TableResult.SHORT)
            )
        );
        _stakeInfoMapOf[msg.sender].set(tableId, serialNumber);
    }

    /// @dev Claim reward given table IDs
    function claim() public {
        EnumerableMap.UintToUintMap storage stakeInfoMap = _stakeInfoMapOf[
            msg.sender
        ];
        uint256 mapSize = stakeInfoMap.length();
        uint80 claimableReward = 0;
        for (uint256 i = 0; i < mapSize; ++i) {
            (uint256 tableId, uint256 serialNumber) = stakeInfoMap.at(i);
            StakeInfo memory stakeInfo = _deserializeStakeInfo(serialNumber);
            TableInfo memory tableInfo = _tableInfoMap[tableId];
            if (tableInfo.result == TableResult.DRAW) {
                claimableReward += stakeInfo.stakeAmount;
                stakeInfoMap.remove(tableId);
            } else {
                uint80 totalStake = tableInfo.stakeForLong +
                    tableInfo.stakeForShort;
                uint80 shareStake = tableInfo.result == TableResult.LONG
                    ? tableInfo.stakeForLong
                    : tableInfo.stakeForShort;
                if (stakeInfo.prediction == uint8(tableInfo.result)) {
                    claimableReward +=
                        (stakeInfo.stakeAmount * totalStake) /
                        shareStake;
                    stakeInfoMap.remove(tableId);
                }
            }
        }

        // transfer reward to player
        _usdt.transfer(msg.sender, claimableReward);
    }

    /// @dev Settle the result using Chainlink oracle
    function settle() public {
        uint256 tableId = _getCurrentTableId();
        TableInfo storage currentTableInfo = _tableInfoMap[tableId];
        TableInfo storage waitingTableInfo = _tableInfoMap[tableId - 2];

        // check if current table has already created
        if (currentTableInfo.result != TableResult.NULL)
            revert SettleTooEarly();

        // fetch BTC price from Chainlink oracle
        (, int256 price, , , ) = _btcPriceFeed.latestRoundData();
        uint80 currPrice = uint80(uint256(price));

        // set the start price of current table
        currentTableInfo.startPrice = currPrice;

        // settle the result of waiting table
        uint80 previousStartPrice = waitingTableInfo.startPrice;
        if (currPrice > previousStartPrice) {
            waitingTableInfo.result = TableResult.LONG;
        } else if (currPrice < previousStartPrice) {
            waitingTableInfo.result = TableResult.SHORT;
        } else {
            waitingTableInfo.result = TableResult.DRAW;
        }
    }

    /**
     * Query Functions
     */

    /// @dev compute unclaimed reward of certain player
    function getPlayerUnclaimReward(address player)
        public
        view
        returns (uint80 claimableReward)
    {
        EnumerableMap.UintToUintMap storage stakeInfoMap = _stakeInfoMapOf[
            player
        ];
        uint256 mapSize = stakeInfoMap.length();
        claimableReward = 0;
        for (uint256 i = 0; i < mapSize; ++i) {
            (uint256 tableId, uint256 serialNumber) = stakeInfoMap.at(i);
            StakeInfo memory stakeInfo = _deserializeStakeInfo(serialNumber);
            TableInfo memory tableInfo = _tableInfoMap[tableId];
            if (tableInfo.result == TableResult.DRAW) {
                claimableReward += stakeInfo.stakeAmount;
            } else {
                uint80 totalStake = tableInfo.stakeForLong +
                    tableInfo.stakeForShort;
                uint80 shareStake = tableInfo.result == TableResult.LONG
                    ? tableInfo.stakeForLong
                    : tableInfo.stakeForShort;
                if (stakeInfo.prediction == uint8(tableInfo.result))
                    claimableReward +=
                        (stakeInfo.stakeAmount * totalStake) /
                        shareStake;
            }
        }
    }

    /// @dev get current stake for long and short
    function getTableInfo(uint256 timestamp)
        public
        view
        returns (TableInfo memory)
    {
        uint256 tableId = _getTableId(timestamp);
        return _tableInfoMap[tableId];
    }

    /// @dev get current stake info of certain player
    function getPlayerStakeInfo(address player, uint256 timestamp)
        public
        view
        returns (StakeInfo memory)
    {
        uint256 tableId = _getTableId(timestamp);
        (bool ifPredicted, uint256 serialNumber) = _stakeInfoMapOf[player]
            .tryGet(tableId);
        // return stake info if predicted
        if (ifPredicted) {
            return _deserializeStakeInfo(serialNumber);
        } else {
            return StakeInfo(0, 0);
        }
    }

    /// @dev deserialize uint256 to StakeInfo struct
    function _deserializeStakeInfo(uint256 serialNumber)
        private
        pure
        returns (StakeInfo memory stakeInfo)
    {
        stakeInfo.prediction = uint8(serialNumber);
        serialNumber >>= 8;
        stakeInfo.stakeAmount = uint32(serialNumber);
    }

    /// @dev serialize StakeInfo struct into uint256
    function _serializeStakeInfo(StakeInfo memory stakeInfo)
        private
        pure
        returns (uint256 serialNumber)
    {
        serialNumber = uint256(stakeInfo.stakeAmount);
        serialNumber = (serialNumber << 8) | stakeInfo.prediction;
    }

    /// @dev get current table ID = cumulative days from timestamp 0
    function _getCurrentTableId() private view returns (uint256) {
        return _getTableId(block.timestamp);
    }

    /// @dev get table ID given timestamp
    function _getTableId(uint256 timestamp) private pure returns (uint256) {
        return timestamp - DAY_TIME_OFFSET / (1 days);
    }
}
