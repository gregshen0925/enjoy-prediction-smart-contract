//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @author InJoy Labs
 * @title A game about predicting the price of BTC
 */
contract EnJoyPrediction {
    error StakeAmountOutOfRange();
    error CanNotPredict();
    error SettleTooEarly();
    error NoClaimable();

    struct Settings {
        uint32 minStake;
        uint32 maxStake;
        uint32 timeInterval;
        uint32 timeOffset;
    }

    struct PlayerInfo {
        uint32 stage;
        bool isClaimed;
        uint8 currentPrediction;
        uint8 previousPrediction;
        uint32 currentStake;
        uint32 previousStake;
        uint128 totalClaim;
    }

    struct GlobalInfo {
        uint32 stage;
        uint8 settlement;
        uint56 startPrice;
        uint40 currentStakeForLong;
        uint40 currentStakeForShort;
        uint40 closedStakeForLong;
        uint40 closedStakeForShort;
    }

    Settings public settings;
    GlobalInfo public globalInfo;
    mapping(address => PlayerInfo) public playerInfoMap;

    IERC20 private immutable _usdt;

    AggregatorV3Interface private immutable _btcPriceFeed;

    constructor(
        IERC20 usdtAddress,
        AggregatorV3Interface btcAggregator,
        Settings memory initSettings,
        uint32 initStage
    ) {
        _usdt = usdtAddress;
        _btcPriceFeed = btcAggregator;
        settings = initSettings;
        globalInfo.stage = initStage;
    }

    /// @dev Predict BTC price with certain amount of USDT
    function predict(uint8 prediction, uint32 stakeAmount) public {
        Settings memory s = settings;
        PlayerInfo storage pInfo = playerInfoMap[msg.sender];
        GlobalInfo storage gInfo = globalInfo;
        if (stakeAmount < s.minStake || stakeAmount > s.maxStake)
            revert StakeAmountOutOfRange();
        if (pInfo.stage >= gInfo.stage) 
            revert CanNotPredict();
        uint64 claimableAmount = getClaimableAmount();
        if (claimableAmount > 0) {
            _usdt.transfer(msg.sender, claimableAmount);
            pInfo.totalClaim += claimableAmount;
        }
        pInfo.stage = gInfo.stage;
        pInfo.previousPrediction = pInfo.currentPrediction;
        pInfo.currentPrediction = prediction;
        _usdt.transferFrom(msg.sender, address(this), stakeAmount);
        pInfo.previousStake = pInfo.currentStake;
        pInfo.currentStake = stakeAmount;
        if (prediction == 1) {
            gInfo.currentStakeForLong += stakeAmount;
        } else {
            gInfo.currentStakeForShort += stakeAmount;
        }
    }

    /// @dev Claim reward if predict correctly
    function claim() public {
        uint64 claimableAmount = getClaimableAmount();
        PlayerInfo storage pInfo = playerInfoMap[msg.sender];
        if (claimableAmount > 0) {
            _usdt.transfer(msg.sender, claimableAmount);
            pInfo.totalClaim += claimableAmount;
            pInfo.stage = globalInfo.stage + 1;
        } else {
            revert NoClaimable();
        }
    }

    /// @dev Settle the result using Chainlink oracle
    function settle() public {
        if (block.timestamp < getNextSettlingTimestamp())
            revert SettleTooEarly();
        (, int256 price, , , ) = _btcPriceFeed.latestRoundData();
        uint56 currPrice = uint56(uint256(price));
        GlobalInfo storage gInfo = globalInfo;
        gInfo.stage++;
        uint40 totalStake = gInfo.currentStakeForLong + gInfo.currentStakeForShort; 
        gInfo.closedStakeForLong = gInfo.currentStakeForLong;
        gInfo.closedStakeForShort = gInfo.currentStakeForShort;
        // long win
        if (currPrice > gInfo.startPrice) {
            gInfo.settlement = 1;
        }
        // short win
        else if (currPrice < gInfo.startPrice) {
            gInfo.settlement = 2;
        }
        // draw
        else {
            gInfo.settlement = 0;
        }
        uint40 halfRemainUSDT = (
            uint40(_usdt.balanceOf(address(this))) - totalStake
            ) / 2;
        gInfo.currentStakeForLong = halfRemainUSDT;
        gInfo.currentStakeForShort = halfRemainUSDT;
        gInfo.startPrice = currPrice;
    }

    /// @dev Compute claimable USDT amount
    function getClaimableAmount() public view returns (uint64) {
        PlayerInfo memory pInfo = playerInfoMap[msg.sender];
        GlobalInfo memory gInfo = globalInfo;

        if (pInfo.stage == gInfo.stage) {
            if (gInfo.settlement == 0) {
                return pInfo.currentStake;
            } else if (gInfo.settlement == pInfo.currentPrediction) {
                uint40 numerator = gInfo.closedStakeForLong + gInfo.closedStakeForShort;
                uint40 denominator = gInfo.settlement == 1 ?
                    gInfo.closedStakeForLong:
                    gInfo.closedStakeForShort;
                return (uint64(pInfo.currentStake) * numerator) / denominator;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    /// @dev Map global stage to next settling timestamp
    function getNextSettlingTimestamp() public view returns (uint256) {
        Settings memory s = settings;
        return ((globalInfo.stage + 1) * s.timeInterval) + s.timeOffset;
    }
}
