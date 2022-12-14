//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./utils/EnumerableMap.sol";

/**
 * @author InJoy Labs (https://injoylabs.io/)
 * @title A game about predicting the price of BTC
 */
contract EnJoyPrediction {
    // uint-to-uint enumerable map
    using EnumerableMap for EnumerableMap.U2UMap;

    uint32 private constant MIN_STAKE = 1_000_000; // 1 USDT

    uint32 private constant MAX_STAKE = 5_000_000; // 5 USDT

    uint32 private constant DAY_TIME_OFFSET = 13 * 60 * 60; // 9 p.m. UTC+8

    /// @dev Player's stake info given table
    struct StakeInfo {
        uint32 stakeAmount;
        uint8 prediction;
    }

    /// @dev Table result state
    enum TableResult {
        NULL,
        LONG,
        SHORT,
        DRAW
    }

    /// @dev Table's info given table ID (global storage)
    struct TableInfo {
        TableResult result;
        uint64 startPrice;
        uint80 longPool;
        uint80 shortPool;
        uint24 playerCount;
    }

    event Predict(
        address indexed player,
        uint8 indexed prediction,
        uint32 stakeAmount
    );

    event Claim(address indexed player, uint80 reward);

    /// @dev USDT contract
    IERC20 private immutable _usdt;

    /// @dev Chainlink BTC price feed oracle
    AggregatorV3Interface private immutable _btcPriceFeed;

    /// @dev TableID => TableInfo
    mapping(uint256 => TableInfo) private _tableInfoMap;

    /// @dev Player => (TableID => StakeInfo)
    mapping(address => EnumerableMap.U2UMap) private _stakeInfoMapOf;

    /// @dev Connect USDT contract and BTC oracle
    constructor(IERC20 usdtAddress, AggregatorV3Interface btcAggregator) {
        _usdt = usdtAddress;
        _btcPriceFeed = btcAggregator;
    }

    /**
     * Execution Functions
     * - predict
     * - claim
     * - settle
     */

    /// @dev Predict BTC price with certain amount of USDT
    function predict(bool predictLong, uint32 stakeAmount) public {
        uint256 tableId = _getCurrentTableId();
        // checks
        require(
            stakeAmount <= MAX_STAKE && stakeAmount >= MIN_STAKE,
            "stake out of range"
        );
        require(
            !_stakeInfoMapOf[msg.sender].contains(tableId),
            "already predicted"
        );

        // get current table info
        TableInfo storage tableInfo = _tableInfoMap[tableId];

        // stake USDT to contract
        _usdt.transferFrom(msg.sender, address(this), stakeAmount);

        // update table info
        if (predictLong) tableInfo.longPool += stakeAmount;
        else tableInfo.shortPool += stakeAmount;

        // add stake info to player's profolio
        uint8 prediction = predictLong
            ? uint8(TableResult.LONG)
            : uint8(TableResult.SHORT);
        uint256 serialNumber = _serializeStakeInfo(
            StakeInfo(stakeAmount, prediction)
        );
        _stakeInfoMapOf[msg.sender].set(tableId, serialNumber);

        // increase player count by one
        ++tableInfo.playerCount;

        // emit Predict event
        emit Predict(msg.sender, prediction, stakeAmount);
    }

    /// @dev Claim reward given table IDs
    function claim() public {
        EnumerableMap.U2UMap storage stakeInfoMap = _stakeInfoMapOf[msg.sender];
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
                uint80 pool = tableInfo.longPool + tableInfo.shortPool;
                uint80 shares = tableInfo.result == TableResult.LONG
                    ? tableInfo.longPool
                    : tableInfo.shortPool;
                if (stakeInfo.prediction == uint8(tableInfo.result)) {
                    claimableReward += (stakeInfo.stakeAmount * pool) / shares;
                    stakeInfoMap.remove(tableId);
                }
            }
        }

        // transfer reward to player
        _usdt.transfer(msg.sender, (claimableReward * 99) / 100);

        // emit Claim event
        emit Claim(msg.sender, claimableReward);
    }

    /// @dev Settle the result using Chainlink oracle
    function settle() public {
        uint256 tableId = _getCurrentTableId();
        TableInfo storage stakingTableInfo = _tableInfoMap[tableId - 1];
        TableInfo storage waitingTableInfo = _tableInfoMap[tableId - 2];

        // check if current table has already created
        require(stakingTableInfo.startPrice == 0, "settle too early");

        // fetch BTC price from Chainlink oracle
        (, int256 price, , , ) = _btcPriceFeed.latestRoundData();
        uint64 currPrice = uint64(uint256(price));

        // set the start price of current table
        stakingTableInfo.startPrice = currPrice;

        // settle the result of waiting table
        if (waitingTableInfo.longPool == 0 || waitingTableInfo.shortPool == 0) {
            waitingTableInfo.result = TableResult.DRAW;
        } else {
            uint64 previousStartPrice = waitingTableInfo.startPrice;
            if (currPrice > previousStartPrice) {
                waitingTableInfo.result = TableResult.LONG;
            } else if (currPrice < previousStartPrice) {
                waitingTableInfo.result = TableResult.SHORT;
            } else {
                waitingTableInfo.result = TableResult.DRAW;
            }
        }

        // transfer reward to settler to covering the gas fee
        uint80 reward = (waitingTableInfo.longPool +
            waitingTableInfo.longPool) / 100;
        _usdt.transfer(msg.sender, reward);
    }

    /**
     * Query Functions
     * - getTableInfo
     * - getPlayerStakeInfo
     * - getPlayerUnclaimReward
     */
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

    /// @dev compute unclaimed reward of certain player
    function getPlayerUnclaimReward(address player)
        public
        view
        returns (uint80 claimableReward)
    {
        EnumerableMap.U2UMap storage stakeInfoMap = _stakeInfoMapOf[player];
        uint256 mapSize = stakeInfoMap.length();
        claimableReward = 0;
        for (uint256 i = 0; i < mapSize; ++i) {
            (uint256 tableId, uint256 serialNumber) = stakeInfoMap.at(i);
            StakeInfo memory stakeInfo = _deserializeStakeInfo(serialNumber);
            TableInfo memory tableInfo = _tableInfoMap[tableId];
            if (tableInfo.result == TableResult.DRAW) {
                claimableReward += stakeInfo.stakeAmount;
            } else {
                uint80 pool = tableInfo.longPool + tableInfo.shortPool;
                uint80 shares = tableInfo.result == TableResult.LONG
                    ? tableInfo.longPool
                    : tableInfo.shortPool;
                if (stakeInfo.prediction == uint8(tableInfo.result))
                    claimableReward += (stakeInfo.stakeAmount * pool) / shares;
            }
        }
    }

    /**
     * Internal functions
     */

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
        return (timestamp - DAY_TIME_OFFSET) / (1 days);
    }
}
