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
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {

    DeployHST deployer;

    HSTEngine engine;
    HopesStableToken HST;
    HelperConfig config;
    
    Handler hander;

    address weth;
    address wbtc;


    function setUp() public {
        deployer = new DeployHST();
        (HST, engine, config) = deployer.run();
        (,,weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        hander = new Handler(engine, HST);
        targetContract(address(hander));
    }

    function invariant_protocolMustHaveMoreValueThanTotalStableCoin() public {
        uint256 totalSupply = HST.totalSupply();

        uint256 wethBalance = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(address(engine));

        uint256 usdValueOfWeth = engine.getTokenValue(weth, wethBalance);
        uint256 usdValueOfWbtc = engine.getTokenValue(wbtc, wbtcBalance);

        assert(totalSupply <= (usdValueOfWbtc + usdValueOfWeth));
        
        console.log("weth value: ", usdValueOfWeth);
        console.log("wbtc value: ", usdValueOfWbtc);
        console.log("Total Supply: ", totalSupply);
        console.log("Times Mint Is Called: ", hander.timesMintIsCalled());
    }
    function invariant_getterFunctionsShouldNeverRevert() public {
        engine.getCollateralTokens();
    }
}

