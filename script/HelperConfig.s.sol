// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC20Mock} from "openzeppelin/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";

// This contract script is to deploy the contracts on different networks and can be used for testing purposes
contract HelperConfig is Script {
    struct NetworkConfig {
        address ethDaiPriceFeed;
        address dai;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_DAI_PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            ethDaiPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            dai: 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.ethDaiPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethDaiPriceFeed = new MockV3Aggregator(DECIMALS, ETH_DAI_PRICE);
        ERC20Mock daiMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            ethDaiPriceFeed: address(ethDaiPriceFeed),
            dai: address(daiMock),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
