// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {PerpetualGuardian} from "../src/PerpetualGuardian.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {console} from "forge-std/Test.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployPerpetualGuardian is Script {
    function run() external returns (PerpetualGuardian, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address ethDaiPriceFeed, address dai, uint256 deployerKey) = config.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        PerpetualGuardian perpetualGuardian = new PerpetualGuardian(
            ERC20(dai),
            "gDAI",
            "Guardian DAI",
            ethDaiPriceFeed
        );
        vm.stopBroadcast();

        return (perpetualGuardian, config);
    }
}
