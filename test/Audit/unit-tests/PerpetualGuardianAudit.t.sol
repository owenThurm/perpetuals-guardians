// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {PerpetualGuardian} from "../../../src/PerpetualGuardian.sol";
import {DeployPerpetualGuardian} from "../../../script/DeployPerpetualGuardian.s.sol";
import {MockV3Aggregator} from "../../mock/MockV3Aggregator.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract PerpetualGuardianAuditTest is StdCheats, Test {
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

   

    // modifier addTrader() {
    //     vm.startPrank(trader1);
    //     DAI.increaseAllowance(address(perpetualGuardian), 1_000);
    //     perpetualGuardian.openPosition(5_000, 1_000, false);
    //     vm.stopPrank();
    //     vm.startPrank(trader2);
    //     DAI.increaseAllowance(address(perpetualGuardian), 1_000);
    //     perpetualGuardian.openPosition(5_000, 1_000, true);
    //     vm.stopPrank();
    //     _;
    // }

     modifier depositLP() {
        vm.startPrank(lP1);
        ERC20Mock(dai).approve(address(perpetualGuardian), 10_000);
        perpetualGuardian.addLiquidity(10_000);
        vm.stopPrank();
        
        vm.startPrank(lP2);
        ERC20Mock(dai).approve(address(perpetualGuardian), 10_000);
        perpetualGuardian.addLiquidity(20_000);
        vm.stopPrank();
        _;
    }

    // ----------- PRICE TESTS -----------------
    
    function testGetDaiValueOfEth() public {  // ✅
 
        uint256 ethAmount = 10e18;
        // 10e18 * ETH_DAI_PRICE = 10000e8
        uint256 expectedEthInDai = 10000e18;
        uint256 actualValue = perpetualGuardian.getDaiValue(ethAmount);
        assertEq(expectedEthInDai, actualValue);
    }

    function testGetTokenSizeFromDai() public {  // ✅
        // If we want $100 of WETH @ $1000/WETH, that would be 0.1 WETH
        uint256 ethPrice = perpetualGuardian.getPrice();
        uint256 size = 100;
        uint256 expectedWethValue = 0.1 ether;
        uint256 amountWeth = (size * 1e30)/(ethPrice);
        assert(amountWeth == expectedWethValue);
    }


    // ----------- LIQUIDITY PROVIDER TESTS -----------------

    function testAddAndRemoveLiquidity() public {  // ✅
        vm.startPrank(lP1);
        ERC20Mock(dai).approve(address(perpetualGuardian), 10_000);
        perpetualGuardian.addLiquidity(100);
        assert(perpetualGuardian.balanceOf(lP1) == 100);

        perpetualGuardian.removeLiquidity(10);
        assert(perpetualGuardian.balanceOf(lP1) == 90);
        vm.stopPrank();
    }

    function testTotalAssets() public {}
}
