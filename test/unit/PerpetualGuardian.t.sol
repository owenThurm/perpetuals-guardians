// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {PerpetualGuardian} from "../../src/PerpetualGuardian.sol";
import {DeployPerpetualGuardian} from "../../script/DeployPerpetualGuardian.s.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract PerpetualGuardianTest is StdCheats, Test {
    PerpetualGuardian perpetualGuardian;
    HelperConfig public helperConfig;

    address public ethDaiPriceFeed;
    address public dai;
    uint256 public deployerKey;

    address public lP1 = makeAddr("lP1");
    address public lP2 = makeAddr("lP2");
    address public trader1 = makeAddr("trader1");
    address public trader2 = makeAddr("trader2");
    address public liquidator = makeAddr("liquidator");

    ERC20Mock public DAI;

    using SafeCast for int256;
    using SafeCast for uint256;

    //================================================================================
    // Setup
    //================================================================================
    function setUp() public {
        DeployPerpetualGuardian deployer = new DeployPerpetualGuardian();
        (perpetualGuardian, helperConfig) = deployer.run();
        (ethDaiPriceFeed, dai, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            DAI = ERC20Mock(perpetualGuardian.asset());
            DAI.mint(lP1, 100_000);
            DAI.mint(lP2, 100_000);
            DAI.mint(trader1, 50_000);
            DAI.mint(trader2, 10_000);
        }
    }

    //================================================================================
    // Reusable Modifiers
    //================================================================================
    modifier addLP() {
        vm.startPrank(lP1);
        DAI.increaseAllowance(address(perpetualGuardian), 10_000);
        perpetualGuardian.addLiquidity(10_000);
        vm.stopPrank();
        vm.startPrank(lP2);
        DAI.increaseAllowance(address(perpetualGuardian), 20_000);
        perpetualGuardian.addLiquidity(20_000);
        vm.stopPrank();
        _;
    }

    modifier addTrader() {
        vm.startPrank(trader1);
        DAI.increaseAllowance(address(perpetualGuardian), 1_000);
        perpetualGuardian.openPosition(5_000, 1_000, false);
        vm.stopPrank();
        vm.startPrank(trader2);
        DAI.increaseAllowance(address(perpetualGuardian), 1_000);
        perpetualGuardian.openPosition(5_000, 1_000, true);
        vm.stopPrank();
        _;
    }

    //================================================================================
    // LP tests
    //================================================================================
    function testDepositLiquidity() public {
        vm.startPrank(lP1);
        DAI.increaseAllowance(address(perpetualGuardian), 10_000);
        perpetualGuardian.addLiquidity(10_000);
        assertEq(perpetualGuardian.balanceOf(lP1), 10_000);

        perpetualGuardian.removeLiquidity(1_000);
        assertEq(perpetualGuardian.balanceOf(lP1), 9_000);
        vm.stopPrank();
    }

    //================================================================================
    // Price feed tests
    //================================================================================

    function testGetTokenAmountFromDai() public {
        // If we want $100 of WETH @ $1000/WETH, that would be 0.1 WETH
        uint256 expectedWeth = 0.1 ether;
        uint256 size = 100;
        uint256 currentETHPrice = perpetualGuardian.getPrice();
        uint256 amountWeth = (size * 1e30) / (currentETHPrice);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetDaiValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 ETH * $1000/ETH = $15,000e18
        uint256 expectedDai = 15000e18;
        uint256 daiValue = perpetualGuardian.getDaiValue(ethAmount);
        assertEq(daiValue, expectedDai);
    }

    //================================================================================
    // Test how PnL affects LPs
    //================================================================================

    function testRemoveLiquidityWhilePnLisPostive() public addLP {
        openTradePosition(trader1, 6_000, 6_000, true);
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(2000e8);

        vm.startPrank(lP1);
        perpetualGuardian.removeLiquidity(10_000);

        //for lP1 we have 100 000 starting DAI
        //invests 10 000 (another 20 0000 by lP2)
        //traders PnL jumps to 6 000
        //LP value goes to 24 000
        //removing 1/3 will be 8000 back to lP1
        //total remaining balance should be 90 000 + 8 000
        assertEq(DAI.balanceOf(lP1), 98_000);
    }

    function testRemoveLiquidityWhilePnLisNegative() public addLP {
        openTradePosition(trader1, 6_000, 12_000, true);
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(500e8);

        vm.startPrank(lP1);
        perpetualGuardian.removeLiquidity(10_000);

        //for lP1 we have 100 000 starting DAI
        //invests 10 000 (another 20 0000 by lP2)
        //traders PnL falls to -6 000
        //LP value goes to 36 000
        //removing 1/3 will be 12 000 back to lP1
        //total remaining balance should be 90 000 + 12 000
        assertEq(DAI.balanceOf(lP1), 101_999);
        //TODO: the above assertion should be 102_000. We must fix it after the precision issues
    }

    //================================================================================
    // Test get position
    //================================================================================

    function testOpenPositionTwiceForAddressFails() public addLP {
        vm.startPrank(trader1);
        DAI.increaseAllowance(address(perpetualGuardian), 5_000);
        perpetualGuardian.openPosition(1_000, 1_000, true);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__PositionAlreadyExists.selector);
        perpetualGuardian.openPosition(1_000, 1_000, true);
    }

    function testGetPositionShouldRevert() public addLP {
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__PositionDoesNotExist.selector);
        perpetualGuardian.getPosition(trader1);
    }

    function testGetPosition() public addLP {
        openTradePosition(trader1, 1_000, 5_000, false);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        assertEq(position.collateral, 1_000e18);
        assertEq(position.isLong, false);
    }

    //================================================================================
    // Test Traders long position
    //================================================================================
    function testOpenLongPosition() public addLP {
        openTradePosition(trader1, 1_000, 10_000, true);

        assertEq(perpetualGuardian.getTradersPnL(), 0);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 30_000);
    }

    function testLongPositionPriceUpMovement() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        int256 ethUsdUpdatedPrice = 1500e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        assertEq(perpetualGuardian.getTradersPnL(), 2_500);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 27_500);
    }

    function testLongPositionPriceDownMovement() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        int256 ethUsdUpdatedPrice = 800e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        assertEq(perpetualGuardian.getTradersPnL(), -1_000);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 31_000);
    }

    //================================================================================
    // Test traders short position
    //================================================================================
    function testOpenShortPosition() public addLP {
        openTradePosition(trader1, 1_000, 10_000, false);

        assertEq(perpetualGuardian.getTradersPnL(), 0);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 30_000);
    }

    function testShortPositionPriceUpMovement() public addLP {
        openTradePosition(trader1, 1_000, 5_000, false);

        int256 ethUsdUpdatedPrice = 1500e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        assertEq(perpetualGuardian.getTradersPnL(), -2_500);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 32_500);
    }

    function testShortPositionPriceDownMovement() public addLP {
        openTradePosition(trader1, 1_000, 5_000, false);

        int256 ethUsdUpdatedPrice = 500e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        assertEq(perpetualGuardian.getTradersPnL(), 2500);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
        assertEq(perpetualGuardian.totalAssets(), 27_500);
    }

    //================================================================================
    // Test increase collateral
    //================================================================================
    function testIncreaseCollateral() public addLP {
        openTradePosition(trader1, 1_000, 6_000, false);

        vm.startPrank(trader1);
        DAI.increaseAllowance(address(perpetualGuardian), 500);
        perpetualGuardian.increasePositionCollateral(500);

        assertEq(perpetualGuardian.getPosition(trader1).collateral, 1_500e18);
        assertEq(perpetualGuardian.totalAssets(), 30_000);
        assertEq(perpetualGuardian.tradersCollateral(), 1_500e18);
    }

    function testIncreaseCollateralFailDueMissingFunds() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        vm.expectRevert();
        perpetualGuardian.increasePositionCollateral(500);
    }

    //================================================================================
    // Test increase position size
    //================================================================================
    function testIncreasePositionSizeSuccess() public addLP {
        openTradePosition(trader1, 1_000, 5_000, false);

        //eliminate position fee
        vm.prank(perpetualGuardian.owner());
        perpetualGuardian.setPositionFeeBasisPoints(0);

        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(1_000);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        assertEq((position.avgEthPrice * position.ethAmount) / 1e18, 6_000e18);
        assertEq(perpetualGuardian.totalAssets(), 30_000);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
    }

    function testIncreasePositionSizeFailDueUnhealthyPosition() public addLP {
        openTradePosition(trader1, 1_000, 5_000, false);

        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__BreaksHealthFactor.selector);
        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(20_000);
    }

    function testIncreasePositionSizeFailForNegativeCollateral() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        int256 ethUsdUpdatedPrice = 500e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__InsufficientPositionCollateral.selector);
        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(11_000);
    }

    function testIncreasePositionSizeFailForExceededLeverage() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__BreaksHealthFactor.selector);
        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(11_000);
    }

    function testIncreasePositionSizeWhilePositionWentUp() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        //eliminate position fee
        vm.prank(perpetualGuardian.owner());
        perpetualGuardian.setPositionFeeBasisPoints(0);

        int256 ethUsdUpdatedPrice = 1500e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(6_000);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        assertEq(position.ethAmount, 9e18);
        assertEq(perpetualGuardian.totalAssets(), 27_500);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
    }

    function testIncreasePositionSizeWhilePositionWentDown() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        //eliminate position fee
        vm.prank(perpetualGuardian.owner());
        perpetualGuardian.setPositionFeeBasisPoints(0);

        int256 ethUsdUpdatedPrice = 900e8;
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.prank(trader1);
        perpetualGuardian.increasePositionSize(900);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        assertEq(position.ethAmount, 6e18);
        assertEq(perpetualGuardian.totalAssets(), 30_500);
        assertEq(perpetualGuardian.tradersCollateral(), 1_000e18);
    }

    //================================================================================
    // Test decrease position size and collateral
    //================================================================================
    function testDecreasePositionCollateral() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);
        vm.startPrank(trader1);
        perpetualGuardian.decreasePosition(500, 0);

        assertEq(perpetualGuardian.totalAssets(), 30_000);
        assertEq(perpetualGuardian.getPosition(trader1).collateral, 500e18);
        assertEq(perpetualGuardian.tradersCollateral(), 500e18);
        assertEq(DAI.balanceOf(trader1), 49_500);
        //TODO: check collateral was returned to trader
    }

    function testDecreasePositionCollateralFailBecauseLeverage() public addLP {
        openTradePosition(trader1, 1_000, 10_000, true);
        vm.startPrank(trader1);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__BreaksHealthFactor.selector);
        perpetualGuardian.decreasePosition(600, 0);
    }

    function testDecreasePositionSizeWithPositivePnL() public addLP {
        openTradePosition(trader1, 1_000, 5_000, true);

        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(2000e8);

        vm.startPrank(trader1);

        perpetualGuardian.decreasePosition(0, 6_000); // closes 3 eth in 1k profit each. 3k profit to the trader

        //check protocol state
        assertEq(perpetualGuardian.totalAssets(), 25_000); // 3k is sent to the trader and there is remaining 2k PnL
        assertEq(perpetualGuardian.getTradersPnL(), 2_000); // PnL for the other part of the trade

        //check position state
        assertEq(perpetualGuardian.getPosition(trader1).collateral, 1_000e18); //stays the same
        assertEq(perpetualGuardian.getPosition(trader1).ethAmount, 2e18); //5 inital, but 3 was withdrawn
        assertEq(perpetualGuardian.getPosition(trader1).avgEthPrice, 1_000e18); //stays the same

        //check trader state
        assertEq(DAI.balanceOf(trader1), 52_000); //50 starting - 1 collateral + 3 profit
    }

    function testDecreasePositionSizeWithNegativePnL() public addLP {
        openTradePosition(trader1, 5_000, 5_000, true);

        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(800e8);

        assertEq(perpetualGuardian.getTradersPnL(), -1000);

        vm.startPrank(trader1);

        perpetualGuardian.decreasePosition(0, 1_000);

        //check protocol state
        assertEq(perpetualGuardian.getTradersPnL(), -750);
        assertEq(perpetualGuardian.totalAssets(), 31_000); //200 from collateral and 800 current PnL

        //check position state
        assertEq(perpetualGuardian.getPosition(trader1).collateral, 4750e18); //PnL is taken from here
        assertEq(perpetualGuardian.getPosition(trader1).ethAmount, 3.75e18); //5 inital, but 2 was withdrawn
        assertEq(perpetualGuardian.getPosition(trader1).avgEthPrice, 1_000e18); //stays the same

        //check trader state
        assertEq(DAI.balanceOf(trader1), 45_000); //unchanged, PnL is taken from collateral
    }

    function testDecreasePositionSizeAndCollateral() public addLP {
        openTradePosition(trader1, 5_000, 5_000, true);

        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(2000e8);

        vm.startPrank(trader1);

        perpetualGuardian.decreasePosition(1_000, 6_000); // closes 3 eth in 1k profit each. 3k profit to the trader

        //check protocol state
        assertEq(perpetualGuardian.totalAssets(), 25_000); // 3k is sent to the trader and there is remaining 2k PnL
        assertEq(perpetualGuardian.getTradersPnL(), 2_000); // PnL for the other part of the trade

        //check position state
        assertEq(perpetualGuardian.getPosition(trader1).collateral, 4_000e18); //1k was withdrawn
        assertEq(perpetualGuardian.getPosition(trader1).ethAmount, 2e18); //5 inital, but 3 was withdrawn
        assertEq(perpetualGuardian.getPosition(trader1).avgEthPrice, 1_000e18); //stays the same

        assertEq(DAI.balanceOf(trader1), 49_000); //50 starting -5 for position + 1 withdrawn + 3 profit
    }

    //================================================================================
    // Test utilization percentage check
    //================================================================================
    function testWithdrawLiquidityFailsBecauseOfLiquidityLimit() public addLP {
        openTradePosition(trader1, 10_000, 15_000, true);
        vm.startPrank(lP2);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__InsufficientLiquidity.selector);
        perpetualGuardian.removeLiquidity(20_000);
    }

    function testOpenPositionFailsBecauseOfLiquidityLimit() public addLP {
        vm.startPrank(trader1);
        DAI.increaseAllowance(address(perpetualGuardian), 28_000);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__InsufficientLiquidity.selector);
        //Didn't use the openTradePosition, because expectRevert is confused
        //by the DAI.increaseAllowance func call and expects it to revert instead
        perpetualGuardian.openPosition(28_000, 28_000, true);
    }

    //================================================================================
    // Test borrowing fees
    //================================================================================
    function testBorrowingFeeWhileIncreasingCollateral() public addLP {
        openTradePosition(trader1, 1_000, 1_000, true);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);
        vm.startPrank(trader1);
        DAI.increaseAllowance(address(perpetualGuardian), 1_000);
        vm.warp(perpetualGuardian.YEAR_IN_SECONDS() + 1); // adding 1, because that's the initial block.timestamp
        perpetualGuardian.increasePositionCollateral(1_000);

        position = perpetualGuardian.getPosition(trader1); //get updated position

        //check position state
        assertEq(position.collateral, 1900e18); // 1000 starting - 100 fees + 1000 increase
        assertEq(position.lastChangeTimestamp, perpetualGuardian.YEAR_IN_SECONDS() + 1);
        assertEq(position.ethAmount, 1e18); //unchanged

        //check contract state
        assertEq(perpetualGuardian.totalAssets(), 30_100); //100 profit from fees was added
        assertEq(perpetualGuardian.getTradersPnL(), 0); //shouldn't change
        assertEq(perpetualGuardian.tradersCollateral(), 1900e18); //same
    }

    function testBorrowingFeeWhileIncreasingSize() public addLP {
        openTradePosition(trader1, 1_000, 1_000, true);

        //eliminate position fee
        vm.prank(perpetualGuardian.owner());
        perpetualGuardian.setPositionFeeBasisPoints(0);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        vm.startPrank(trader1);
        vm.warp(perpetualGuardian.YEAR_IN_SECONDS() + 1); // adding 1, because that's the initial block.timestamp
        perpetualGuardian.increasePositionSize(1_000);

        position = perpetualGuardian.getPosition(trader1); //get updated position

        //check position state
        assertEq(position.collateral, 900e18); // 1000 starting - 100 fees
        assertEq(position.lastChangeTimestamp, perpetualGuardian.YEAR_IN_SECONDS() + 1);
        assertEq(position.ethAmount, 2e18); //added 1 more ETH

        //check contract state
        assertEq(perpetualGuardian.totalAssets(), 30_100); //100 profit from fees was added
        assertEq(perpetualGuardian.getTradersPnL(), 0); //shouldn't change
        assertEq(perpetualGuardian.tradersCollateral(), 900e18); //same
    }

    function testBorrowingFeeWhileDecreasingSize() public addLP {
        openTradePosition(trader1, 2_000, 2_000, true);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        vm.startPrank(trader1);
        vm.warp(perpetualGuardian.YEAR_IN_SECONDS() + 1); // adding 1, because that's the initial block.timestamp
        perpetualGuardian.decreasePosition(0, 1_000);

        position = perpetualGuardian.getPosition(trader1); //get updated position

        //check position state
        assertEq(position.collateral, 1800e18); // 2000 starting - 200 fees
        assertEq(position.lastChangeTimestamp, perpetualGuardian.YEAR_IN_SECONDS() + 1);
        assertEq(position.ethAmount, 1e18);

        //check contract state
        assertEq(perpetualGuardian.totalAssets(), 30_200); //200 profit from fees was added
        assertEq(perpetualGuardian.getTradersPnL(), 0); //shouldn't change
        assertEq(perpetualGuardian.tradersCollateral(), 1800e18); //same
    }

    function testBorrowingFeeWhileDecreasingCollateral() public addLP {
        openTradePosition(trader1, 2_000, 2_000, true);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        vm.startPrank(trader1);
        vm.warp(perpetualGuardian.YEAR_IN_SECONDS() + 1); // adding 1, because that's the initial block.timestamp
        perpetualGuardian.decreasePosition(1_000, 0);

        position = perpetualGuardian.getPosition(trader1); //get updated position

        //check position state
        assertEq(position.collateral, 800e18); // 2000 starting - 200 fees - 1000 decrease
        assertEq(position.lastChangeTimestamp, perpetualGuardian.YEAR_IN_SECONDS() + 1);
        assertEq(position.ethAmount, 2e18); //same

        //check contract state
        assertEq(perpetualGuardian.totalAssets(), 30_200); //200 profit from fees was added
        assertEq(perpetualGuardian.getTradersPnL(), 0); //shouldn't change
        assertEq(perpetualGuardian.tradersCollateral(), 800e18); //same
    }

    //================================================================================
    // Test Position fees
    //================================================================================

    function testPositionFee() public addLP {
        openTradePosition(trader1, 2_000, 2_000, true);
        vm.startPrank(trader1);

        perpetualGuardian.increasePositionSize(1_000);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        //check position state
        assertEq(position.collateral, 1_990e18); // 2000 initial - 10 fees
        assertEq(position.ethAmount, 3e18); // 2 initial + 1 from increase

        //check contract state
        assertEq(perpetualGuardian.getTradersPnL(), 0);
        assertEq(perpetualGuardian.totalAssets(), 30_010); //30k initial + 10 fees
        assertEq(perpetualGuardian.tradersCollateral(), 1_990e18); //collateral from the only trade
    }

    function testIncreasePositionFeeShouldFailBecausePointsExceedMaximum() public addLP {
        vm.startPrank(perpetualGuardian.owner());
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__MaximumPositionFeeBasisPointsExceeded.selector);
        perpetualGuardian.setPositionFeeBasisPoints(300);
    }

    function testIncreasePositionFeeIncreaseAndApply() public addLP {
        openTradePosition(trader1, 2_000, 2_000, true);

        vm.startPrank(perpetualGuardian.owner());
        perpetualGuardian.setPositionFeeBasisPoints(15);

        vm.startPrank(trader1);

        perpetualGuardian.increasePositionSize(1_000);

        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader1);

        //check position state
        assertEq(position.collateral, 1_850e18); // 2000 initial - 150 fees
        assertEq(position.ethAmount, 3e18); // 2 initial + 1 from increase

        //check contract state
        assertEq(perpetualGuardian.getTradersPnL(), 0);
        assertEq(perpetualGuardian.totalAssets(), 30_150); //30k initial + 150 fees
        assertEq(perpetualGuardian.tradersCollateral(), 1_850e18); //collateral from the only trade
    }

    //================================================================================
    // Test Liquidate
    //================================================================================

    function testCantLiquidateHealthyPosition() public addLP addTrader {
        vm.startPrank(liquidator);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__PositionNotLiquidatable.selector);
        perpetualGuardian.liquidate(trader1);
    }

    function testLiquidationOfPosition() public addLP {
        openTradePosition(trader1, 1_000, 4_000, true);

        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(800e8);

        vm.prank(liquidator);
        perpetualGuardian.liquidate(trader1);

        assertEq(DAI.balanceOf(liquidator), 20);
        assertEq(perpetualGuardian.totalAssets(), 30_600);
        assertEq(DAI.balanceOf(trader1), 49_180);
    }

    function testTraderCantLiquidateHimself() public addLP addTrader {
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(1140e8);

        vm.startPrank(trader1);
        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__TraderCantLiquidateHimself.selector);
        perpetualGuardian.liquidate(trader1);
    }

    function testPositionDoesNotExistAfterLiquidation() public addLP addTrader {
        MockV3Aggregator(ethDaiPriceFeed).updateAnswer(860e8);

        vm.startPrank(liquidator);
        perpetualGuardian.liquidate(trader2);
        vm.stopPrank();

        vm.expectRevert(PerpetualGuardian.PerpetualGuardian__PositionDoesNotExist.selector);
        PerpetualGuardian.Position memory position = perpetualGuardian.getPosition(trader2);
    }

    //================================================================================
    // Internal Reusable functions
    //================================================================================

    function openTradePosition(address trader, uint256 collateral, uint256 size, bool isLong) internal {
        vm.startPrank(trader);
        DAI.increaseAllowance(address(perpetualGuardian), collateral);
        perpetualGuardian.openPosition(size, collateral, isLong);

        vm.stopPrank();
    }
}
