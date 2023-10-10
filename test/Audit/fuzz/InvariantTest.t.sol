//INVARIANTS:
// tradersCollateral should always be a non zero && non-negative value
// leverage should always be below the MAX_LEVERAGE
//Positions that aren't liquidatable shouldn't be able to be passed through the liquidate function
//total borrowed amount must be < max utilization* total Liquidity provided
// total liquidity provided * 0.8 == available amount for borroWing

//SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployPerpetualGuardian} from "../../../script/DeployPerpetualGuardian.s.sol";

import {PerpetualGuardian} from "../../../src/PerpetualGuardian.sol";
import {MockV3Aggregator} from "../../mock/MockV3Aggregator.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    PerpetualGuardian perpetualGuardian;
    HelperConfig public helperConfig;

    address public ethDaiPriceFeed;
    address public dai;
    uint256 public deployerKey;

    function setUp() public {
        DeployPerpetualGuardian deployer = new DeployPerpetualGuardian();
        (perpetualGuardian, helperConfig) = deployer.run();
        (ethDaiPriceFeed, dai, deployerKey) = helperConfig.activeNetworkConfig();

        targetContract(address(perpetualGuardian));
    }

    //total borrowed amount must be < max utilization* total Liquidity provided
    // total liquidity provided * 0.8 == available amount for borroWing

    function invariant_borrowedLiquidityMustBeLessThanToTalLiquidityProvided() public {
        uint256 totalBorrowedAmount =
            perpetualGuardian.totalLongPositions.sizeInDai() + perpetualGuardian.totalShortPositions.sizeInDai();
        uint256 availableLiquidity =
            perpetualGuardian.totalAssets() * perpetualGuardian.MAX_UTILIZATION_PERCENTAGE() / 100;

        assert(totalBorrowedAmount <= availableLiquidity);
    }
}
