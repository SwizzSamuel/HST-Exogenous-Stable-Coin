// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {HopesStableToken} from ".././src/HopesStableToken.sol";
import {HSTEngine} from ".././src/HSTEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployHST is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(HopesStableToken, HSTEngine, HelperConfig) {

        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        HopesStableToken HST = new HopesStableToken();
        HSTEngine engine = new HSTEngine(tokenAddresses, priceFeedAddresses, address(HST));
        HST.transferOwnership(address(engine));
        vm.stopBroadcast();
        return(HST, engine, config);
    }
}