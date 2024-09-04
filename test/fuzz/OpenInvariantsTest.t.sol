// SPDX-License-Identifier: MIT

// Have our invariant aka properties

// Some of our invariants includes:

// 1. The sum of HST should never be greater that the total value of the collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {HSTEngine} from "../../src/HSTEngine.sol";
import {HopesStableToken} from "../../src/HopesStableToken.sol";
import {DeployHST} from "../../script/DeployHST.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantsTest is StdInvariant, Test {

    DeployHST deployer;

    HSTEngine engine;
    HopesStableToken HST;
    HelperConfig config;

    address weth;
    address wbtc;


    function setUp() public {
        deployer = new DeployHST();
        (HST, engine, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(engine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalStableCoin() public {
        uint256 totalSupply = HST.totalSupply();

        uint256 wethBalance = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(address(engine));

        uint256 usdValueOfWeth = engine.getTokenValue(weth, wethBalance);
        uint256 usdValueOfWbtc = engine.getTokenValue(wbtc, wbtcBalance);

        assert(totalSupply <= (usdValueOfWbtc + usdValueOfWeth));
    }
}

