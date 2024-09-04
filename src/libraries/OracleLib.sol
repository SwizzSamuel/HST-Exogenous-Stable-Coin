// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
* @title OracleLib
* @author Samuel Swizz
* @notice This library is used to check the chainlink Oracle for stale data
* @notice If a pricefeed is stale, the function will revert, and render the HSTEngine unusable. The HSTEngine will freeze if prices become stale.
* @notice If the Chainlink network blows up, any monety locked on the protocol will be frozen.
*/

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {

    error OracleLib_PriceFeedIsStale();

    uint256 private constant TIME_OUT = 3 hours;

    function staleCheckRoundData(AggregatorV3Interface priceFeed) external view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = priceFeed.latestRoundData();
        uint256 interval = block.timestamp - updatedAt;
        if(interval > TIME_OUT) {
            revert OracleLib_PriceFeedIsStale();
        }
    }
}