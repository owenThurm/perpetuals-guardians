//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {console} from "forge-std/Test.sol";

import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";

contract PerpetualGuardian is ERC4626, Ownable {
    //================================================================================
    // Custom Errors
    //================================================================================
    error PerpetualGuardian__MaximumLeverageExceeded();
    error PerpetualGuardian__InsufficientPositionCollateral();
    error PerpetualGuardian__InsufficientPositionSize();
    error PerpetualGuardian__InsufficientLiquidity();
    error PerpetualGuardian__PositionAlreadyExists();
    error PerpetualGuardian__PositionDoesNotExist();
    error PerpetualGuardian__UsupportedOperation();
    error PerpetualGuardian__MaximumPositionFeeBasisPointsExceeded();
    error PerpetualGuardian__PositionNotLiquidatable();
    error PerpetualGuardian__BreaksHealthFactor();
    error PerpetualGuardian__TraderCantLiquidateHimself();

    //================================================================================
    // Custom Structs
    //================================================================================
    struct Position {
        uint256 collateral;
        uint256 avgEthPrice;
        uint256 ethAmount;
        bool isLong;
        uint256 lastChangeTimestamp;
    }

    struct PositionsSummary {
        uint256 sizeInDai;
        uint256 sizeInETH;
    }

    //================================================================================
    // Constants
    //================================================================================
    uint256 public constant MAX_LEVERAGE = 15;
    uint256 public constant MAX_UTILIZATION_PERCENTAGE = 80;
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e6;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant BORROWING_FEE_RATE = 315_360_000;
    uint256 public constant YEAR_IN_SECONDS = 31_536_000;
    uint256 public constant LIQUIDATION_BONUS = 10; //10%

    //================================================================================
    // Libraries
    //================================================================================
    using PriceConverter for uint256;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for ERC20;

    //================================================================================
    // State Variables
    //================================================================================
    ERC20 public DAI;
    AggregatorV3Interface private s_ethDaiPriceFeed;

    PositionsSummary totalLongPositions;
    PositionsSummary totalShortPositions;

    mapping(address => Position) positions;
    uint256 public tradersCollateral;
    uint256 private positionFeeBasisPoints;

    //================================================================================
    // Events
    //================================================================================
    event PositionOpened(
        address indexed user,
        bool isLong,
        uint256 collateral,
        uint256 size,
        uint256 ethAmount,
        uint256 avgEthPrice
    );

    event PositionIncreased(
        address indexed user,
        uint256 collateralIncreased,
        uint256 sizeIncreased
    );

    event PositionDecreased(
        address indexed user,
        uint256 collateralDecreased,
        uint256 sizeDecreased
    );

    event LiquidityAdded(address indexed user, uint256 addedLiquidity);

    event LiquidityRemoved(address indexed user, uint256 withdrawnLiqudity);

    //================================================================================
    // Modifiers
    //================================================================================
    modifier checkForAvailableLiquidity() {
        _;
        uint256 totalOpenInterest = (totalLongPositions.sizeInDai +
            totalShortPositions.sizeInDai) / PRECISION;

        uint256 availableLiquidity = (totalAssets() *
            MAX_UTILIZATION_PERCENTAGE) / 100;

        if (totalOpenInterest > availableLiquidity) {
            revert PerpetualGuardian__InsufficientLiquidity();
        }
    }

    //================================================================================
    // Constructor
    //================================================================================
    constructor(
        ERC20 _token,
        string memory _name,
        string memory _symbol,
        address priceFeed
    ) ERC4626(_token) ERC20(_name, _symbol) {
        DAI = ERC20(_token);
        s_ethDaiPriceFeed = AggregatorV3Interface(priceFeed);
        positionFeeBasisPoints = 1;
    }

    //================================================================================
    // Liquidity Providers functionality
    //================================================================================
    function addLiquidity(uint256 amount) public {
        super.deposit(amount, msg.sender);

        emit LiquidityAdded(msg.sender, amount);
    }

    function removeLiquidity(uint256 amount) public checkForAvailableLiquidity {
        super.redeem(amount, msg.sender, msg.sender);

        emit LiquidityRemoved(msg.sender, amount);
    }

    //================================================================================
    // Override ERC4626
    //================================================================================
    function totalAssets() public view virtual override returns (uint256) {
        int256 tradersPnL = getTradersPnL();
        if (tradersPnL > 0) {
            return
                super.totalAssets() -
                tradersPnL.toUint256() -
                (tradersCollateral / PRECISION);
        }
        tradersPnL = -tradersPnL;
        return
            super.totalAssets() +
            tradersPnL.toUint256() -
            (tradersCollateral / PRECISION);
    }

    //disable function
    function redeem(
        uint256,
        /*shares*/ address,
        /*receiver*/ address /*owner*/
    ) public override returns (uint256) {
        revert PerpetualGuardian__UsupportedOperation();
    }

    //disable function
    function withdraw(
        uint256,
        /*shares*/ address,
        /*receiver*/ address /*owner*/
    ) public override returns (uint256) {
        revert PerpetualGuardian__UsupportedOperation();
    }

    //disable function
    function mint(
        uint256,
        /*shares*/ address /*receiver*/
    ) public override returns (uint256) {
        revert PerpetualGuardian__UsupportedOperation();
    }

    //disable function
    function deposit(
        uint256,
        /*shares*/ address /*receiver*/
    ) public override returns (uint256) {
        revert PerpetualGuardian__UsupportedOperation();
    }

    //================================================================================
    // Traders functionality
    //================================================================================
    function openPosition(
        uint256 size,
        uint256 collateral,
        bool isLong
    ) public checkForAvailableLiquidity {
        if (collateral <= 0) {
            revert PerpetualGuardian__InsufficientPositionCollateral();
        }
        if (size <= 0) {
            revert PerpetualGuardian__InsufficientPositionSize();
        }

        if (positions[msg.sender].collateral != 0) {
            revert PerpetualGuardian__PositionAlreadyExists();
        }

        uint256 currentETHPrice = getPrice();

        //create position
        Position memory position = Position({
            avgEthPrice: currentETHPrice * ADDITIONAL_FEED_PRECISION,
            collateral: collateral * PRECISION,
            ethAmount: (size * 1e30) / (currentETHPrice),
            isLong: isLong,
            lastChangeTimestamp: block.timestamp
        });
        _checkPositionHealth(position, currentETHPrice);
        DAI.safeTransferFrom(msg.sender, address(this), collateral);

        //contract state
        tradersCollateral += position.collateral;
        positions[msg.sender] = position;
        _increasePositionsSummary(size * PRECISION, position.ethAmount, isLong);

        emit PositionOpened(
            msg.sender,
            position.isLong,
            size,
            collateral,
            position.ethAmount,
            position.avgEthPrice
        );
    }

    function decreasePosition(
        uint256 collateralAmount,
        uint256 sizeAmount
    ) public {
        Position memory position = getPosition(msg.sender);
        _applyBorrowingFee(position);
        uint256 currentETHPrice = getPrice();
        uint256 ethToRemove = (sizeAmount * 1e30) / (currentETHPrice);

        int256 positionPnL = _calculatePositionPnL(position, currentETHPrice);

        if (positionPnL > 0) {
            //transfer proportional DAI to him
            uint256 pnlToRealize = (positionPnL.toUint256() * ethToRemove) /
                position.ethAmount;
            DAI.safeTransfer(msg.sender, pnlToRealize / PRECISION);
        } else {
            //remove from his colalteral
            positionPnL = -positionPnL;
            uint256 pnlToRealize = (positionPnL.toUint256() * ethToRemove) /
                position.ethAmount;
            position.collateral -= pnlToRealize;
            tradersCollateral -= pnlToRealize;
        }

        //update position
        position.collateral -= collateralAmount * PRECISION;
        position.ethAmount -= ethToRemove;
        _checkPositionHealth(position, currentETHPrice);

        _decreasePositionsSummary(
            (ethToRemove * position.avgEthPrice) / PRECISION,
            ethToRemove,
            position.isLong
        );
        tradersCollateral -= collateralAmount * PRECISION;
        //return withdrawn collateral
        DAI.safeTransfer(msg.sender, collateralAmount);
        positions[msg.sender] = position;

        emit PositionDecreased(msg.sender, collateralAmount, sizeAmount);
    }

    function increasePositionCollateral(
        uint256 amount
    ) public checkForAvailableLiquidity {
        DAI.safeTransferFrom(msg.sender, address(this), amount);
        uint256 currentETHPrice = getPrice();
        Position memory position = getPosition(msg.sender);

        _applyBorrowingFee(position);

        position.collateral += amount * PRECISION;
        tradersCollateral += amount * PRECISION;

        _checkPositionHealth(position, currentETHPrice);
        positions[msg.sender] = position;

        emit PositionIncreased(msg.sender, amount, 0);
    }

    function increasePositionSize(
        uint256 additionalDai
    ) public checkForAvailableLiquidity {
        Position memory position = getPosition(msg.sender);
        _applyBorrowingFee(position);
        _applyPositionFee(position, additionalDai);
        uint256 currentETHPrice = getPrice();
        uint256 newEthTokens = (additionalDai * 1e30) / currentETHPrice;

        uint256 avgEthPrice = ((position.ethAmount * position.avgEthPrice) +
            (additionalDai * 1e36)) / (position.ethAmount + newEthTokens);

        position.ethAmount += newEthTokens;
        position.avgEthPrice = avgEthPrice;
        _checkPositionHealth(position, currentETHPrice);

        positions[msg.sender] = position;
        _increasePositionsSummary(
            additionalDai * PRECISION,
            newEthTokens,
            position.isLong
        );

        emit PositionIncreased(msg.sender, 0, additionalDai);
    }

    //================================================================================
    // Liquidity Providers functionality
    //================================================================================

    function setPositionFeeBasisPoints(
        uint256 newBasisPoints
    ) public onlyOwner {
        if (newBasisPoints > 200) {
            revert PerpetualGuardian__MaximumPositionFeeBasisPointsExceeded();
        }

        positionFeeBasisPoints = newBasisPoints;
    }

    //================================================================================
    // Public utility functions
    //================================================================================
    function getPosition(
        address owner
    ) public view returns (Position memory position) {
        Position memory requestedPosition = positions[owner];
        if (requestedPosition.collateral == 0) {
            revert PerpetualGuardian__PositionDoesNotExist();
        }
        return positions[owner];
    }

    function getTradersPnL() public view returns (int256) {
        int256 longPnL = getDaiValue(totalLongPositions.sizeInETH).toInt256() -
            totalLongPositions.sizeInDai.toInt256();

        int256 shortPnL = totalShortPositions.sizeInDai.toInt256() -
            getDaiValue(totalShortPositions.sizeInETH).toInt256();

        return (shortPnL + longPnL) / 1e18;
    }

    //================================================================================
    // Liquidators
    //================================================================================

    function isLiquidatable(address trader) public view returns (bool) {
        Position memory position = getPosition(trader);
        uint256 positionCollateral = position.collateral;
        uint256 currentETHPrice = getPrice();

        //account for PnL
        int256 positionPnL = _calculatePositionPnL(position, currentETHPrice);
        positionCollateral = (positionCollateral.toInt256() + positionPnL)
            .toUint256();

        //account for fees
        uint256 borrowingFees = _calculateBorrowingFee(position);
        positionCollateral -= borrowingFees;

        //calculate leverage
        uint256 leverage = ((position.ethAmount * position.avgEthPrice) /
            positionCollateral) / PRECISION;

        return leverage > MAX_LEVERAGE;
    }

    function liquidate(address trader) public {
        Position memory position = getPosition(trader);
        uint256 currentETHPrice = getPrice();

        if (msg.sender == trader) {
            revert PerpetualGuardian__TraderCantLiquidateHimself();
        }

        if (!isLiquidatable(trader)) {
            revert PerpetualGuardian__PositionNotLiquidatable();
        }

        //account for PnL and send to LPs
        int256 positionPnL = _calculatePositionPnL(position, currentETHPrice);
        position.collateral = (position.collateral.toInt256() + positionPnL)
            .toUint256();
        tradersCollateral -= (-positionPnL).toUint256();

        //account for borrowingFee and send to LPs
        _applyBorrowingFee(position);

        //account for liquidatorFee and send to liquidator
        uint256 liquidatorFee = (position.collateral * LIQUIDATION_BONUS) / 100;
        position.collateral -= liquidatorFee;
        DAI.safeTransfer(msg.sender, liquidatorFee / PRECISION);

        //send remaining collateral to trader
        DAI.safeTransfer(trader, position.collateral / PRECISION);

        _decreasePositionsSummary(
            (position.ethAmount * position.avgEthPrice) / PRECISION,
            position.ethAmount,
            position.isLong
        );
        delete positions[trader];
    }

    //================================================================================
    // Price feed logic
    //================================================================================
    function getDaiValue(uint256 amount) public view returns (uint256) {
        uint256 daiValue = amount.getConversionRateinDai(s_ethDaiPriceFeed);
        return (daiValue);
    }

    function getPrice() public view returns (uint256) {
        return PriceConverter.getPrice(s_ethDaiPriceFeed);
    }

    //================================================================================
    // Internal functions
    //================================================================================

    function _increasePositionsSummary(
        uint256 sizeInDai,
        uint256 sizeInEth,
        bool isLong
    ) internal {
        if (isLong) {
            totalLongPositions.sizeInDai += sizeInDai;
            totalLongPositions.sizeInETH += sizeInEth;
        } else {
            totalShortPositions.sizeInDai += sizeInDai;
            totalShortPositions.sizeInETH += sizeInEth;
        }
    }

    //TODO: Merge this logic with _increasePositionsSummary
    function _decreasePositionsSummary(
        uint256 sizeInDai,
        uint256 sizeInEth,
        bool isLong
    ) internal {
        if (isLong) {
            totalLongPositions.sizeInDai -= sizeInDai;
            totalLongPositions.sizeInETH -= sizeInEth;
        } else {
            totalShortPositions.sizeInDai -= sizeInDai;
            totalShortPositions.sizeInETH -= sizeInEth;
        }
    }

    function _calculateBorrowingFee(
        Position memory position
    ) internal view returns (uint256) {
        uint256 positionDaiSize = (position.avgEthPrice * position.ethAmount) /
            1e18;

        uint256 secondsPassedSinceLastUpdate = block.timestamp -
            position.lastChangeTimestamp;

        //result will be in 1e18
        uint256 borrowingFee = ((positionDaiSize *
            secondsPassedSinceLastUpdate *
            PRECISION) / BORROWING_FEE_RATE) / PRECISION;

        return borrowingFee;
    }

    function _applyBorrowingFee(Position memory position) internal {
        uint256 borrowingFees = _calculateBorrowingFee(position);
        position.collateral -= borrowingFees;
        position.lastChangeTimestamp = block.timestamp;

        tradersCollateral -= borrowingFees;
    }

    function _applyPositionFee(
        Position memory position,
        uint256 sizeIncrease
    ) internal {
        uint256 positionFee = (sizeIncrease *
            PRECISION *
            positionFeeBasisPoints) / 100;

        tradersCollateral -= positionFee;
        position.collateral -= positionFee;
    }

    function _checkPositionHealth(
        Position memory position,
        uint256 currentEthPrice
    ) internal pure {
        int256 positionPnL = _calculatePositionPnL(position, currentEthPrice);

        if (position.collateral.toInt256() + positionPnL <= 0) {
            revert PerpetualGuardian__InsufficientPositionCollateral();
        }

        uint256 positionCollateral = (position.collateral.toInt256() +
            positionPnL).toUint256();

        uint256 leverage = ((position.ethAmount * position.avgEthPrice) /
            positionCollateral) / PRECISION;

        if (leverage >= MAX_LEVERAGE) {
            revert PerpetualGuardian__BreaksHealthFactor();
        }
    }

    function _calculatePositionPnL(
        Position memory position,
        uint256 currentETHPrice
    ) internal pure returns (int256) {
        int256 currentPositionValue = (position.ethAmount *
            (currentETHPrice * ADDITIONAL_FEED_PRECISION)).toInt256();

        int256 positionValueWhenCreated = (position.ethAmount *
            position.avgEthPrice).toInt256();

        if (position.isLong) {
            return (currentPositionValue - positionValueWhenCreated) / 1e18;
        } else {
            return (positionValueWhenCreated - currentPositionValue) / 1e18;
        }
    }
}
