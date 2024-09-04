// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {HSTEngine} from "../../src/HSTEngine.sol";
import {HopesStableToken} from "../../src/HopesStableToken.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
// import {DeployHST} from "../../script/DeployHST.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract Handler is Test {
    HSTEngine engine;
    HopesStableToken HST;

    MockV3Aggregator public ethUsdPricefeed;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;

    address[] public collateralDepositors;

    constructor(HSTEngine _engine, HopesStableToken _HST) {
        engine = _engine;
        HST = _HST;
        // config = _config; 
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPricefeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralBySeed(collateralSeed);
        amount = bound(amount, 1, type(uint96).max);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        collateralDepositors.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralBySeed(collateralSeed);

        vm.startPrank(msg.sender);
        uint256 totalCollateral = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amount = bound(amount, 1, totalCollateral);
        vm.assume(amount != 0);
        require(amount != 0);
        engine.redeemCollateral(address(collateral), amount);

    }

    function mintHST(uint256 amountHST, uint256 addressSeed) public {
        address sender = _getAddressBySeed(addressSeed);
        (uint256 totalHSTMinted, uint256 totalValueOfCollateral) = engine.getAccountInformation(sender);
        int256 maxHSTmint = (int256(totalValueOfCollateral) / 2) - int256(totalHSTMinted);

        vm.assume(maxHSTmint > 0);
        require(maxHSTmint > 0);

        amountHST = bound(amountHST, 0, uint256(maxHSTmint));
        vm.assume(amountHST != 0);
        require(amountHST != 0);

        vm.startPrank(sender);
        engine.mintHST(amountHST);
        vm.stopPrank();

        timesMintIsCalled += 1;
    }

    function updateCollateralPrice(uint96 newPrice) public {
        int256 price = int256(uint256(newPrice));
        ethUsdPricefeed.updateAnswer(price);
    }

    function _getCollateralBySeed(uint256 seed) private view returns(ERC20Mock) {
        if(seed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function _getAddressBySeed(uint256 seed) private view returns(address) {
        require(collateralDepositors.length > 0);
        uint256 seedIndex = seed % collateralDepositors.length;
        return collateralDepositors[seedIndex];
    }

}