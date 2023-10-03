// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library PriceConverter {
    function getPrice(AggregatorV3Interface priceFeed) internal view returns (uint256) {
        // Sepolia ETH / USDC Address
        (, int256 answer,,,) = priceFeed.latestRoundData();
        // ETH/USD rate in 18 digit
        return uint256(answer * 1e4);
    }

    function getConversionRateinDai(uint256 ethAmount, AggregatorV3Interface priceFeed)
        internal
        view
        returns (uint256)
    {
        // 1eth
        uint256 ethPrice = getPrice(priceFeed);
        uint256 ethAmountInDai = (ethPrice * ethAmount) / 1e12;
        // 12 + 18 - 12 = 18
        // the actual ETH/USD conversion rate, after adjusting the extra 0s.
        return ethAmountInDai;
    }
}
