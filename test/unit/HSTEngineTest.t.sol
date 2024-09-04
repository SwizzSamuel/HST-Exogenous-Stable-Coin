// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployHST} from "../../script/DeployHST.s.sol";
import {HopesStableToken} from "../../src/HopesStableToken.sol";
import {HSTEngine} from "../../src/HSTEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract HSTEngineTest is Test {
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount);
    DeployHST deployer;

    HopesStableToken HST;
    HSTEngine engine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC_20 = 10 ether;
    uint256 public constant AMOUNT_HST_MINT = 100 ether;

    function setUp() public {
        deployer = new DeployHST();
        (HST, engine, config) = deployer.run();

        (ethUsdPriceFeed,btcUsdPriceFeed,weth, ,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC_20);
    }


    ////////////////////////////
    //// Construction Tests ////
    ////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfArrayLengthIsDifferent() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(HSTEngine.HSTEngine_DifferenceInArrayLength.selector);
        new HSTEngine(tokenAddresses, priceFeedAddresses, address(HST));
    }

    //////////////////////////
    //// Price Feed Tests ////
    //////////////////////////

    function testGetsUsdValue() public {
        uint256 ethAmount = 15e18;
        // From
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getTokenValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //////////////////////////////////
    //// Collateral Deposit Tests ////
    //////////////////////////////////

    function testRevertsIfCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(HSTEngine.HSTEngine_AmountIsZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotApproved() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, 18);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(HSTEngine.HSTEngine_TokenNotAllowedAsCollateral.selector, address(ranToken)));
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier collateralDeposited() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public collateralDeposited {
        (uint256 totalHSTMinted, uint256 totalValueOfCollateral) = engine.getAccountInformation(USER);

        uint256 expectedTotalHSTMinted = 0;
        uint256 expectedTotalValueOfCollateral = engine.getTokenAmountFromUsd(weth, totalValueOfCollateral);

        assertEq(totalHSTMinted, expectedTotalHSTMinted);
        assertEq(AMOUNT_COLLATERAL, expectedTotalValueOfCollateral);
        
    }

    ////////////////////////
    //// HST Mint Tests ////
    ////////////////////////

    modifier collateralDepositedAndHSTMinted() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintHST(weth, AMOUNT_COLLATERAL, AMOUNT_HST_MINT);
        vm.stopPrank();
        _;
    }


    function testMintRevertsIfHealthFactorIsTooLow() public collateralDeposited {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        vm.startPrank(USER);
        uint256 expectedMintAmount = AMOUNT_COLLATERAL * ((uint256(price) * engine.getAddtionalFeePrecision())/engine.getPrecision());
        uint256 expectedHealthfactor = engine.calculateHealthFactor(expectedMintAmount, engine.getTokenValue(weth, AMOUNT_COLLATERAL));
        vm.expectRevert(abi.encodeWithSelector(HSTEngine.HSTEngine_HealthFactorTooLow.selector, expectedHealthfactor));
        engine.mintHST(expectedMintAmount);
        vm.stopPrank();
    }

    function testMintRevertsIfAmountIsZero() public collateralDeposited {
        vm.startPrank(USER);
        uint256 amountToMint = 0;
        vm.expectRevert(abi.encodeWithSelector(HSTEngine.HSTEngine_AmountIsZero.selector, amountToMint));
        engine.mintHST(amountToMint);
        vm.stopPrank();
    }

    function testCanMintAndGetAccountInfo() public collateralDeposited {
        vm.startPrank(USER);
        engine.mintHST(AMOUNT_HST_MINT);

        uint256 userBalance = HST.balanceOf(USER);
        assertEq(AMOUNT_HST_MINT, userBalance);
    }

    ////////////////////////
    //// Burn HST Tests ////
    ////////////////////////

    function testBurnRevertsIfAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintHST(weth, AMOUNT_COLLATERAL, AMOUNT_HST_MINT);
        uint256 amountToBurn = 0;
        vm.expectRevert(abi.encodeWithSelector(HSTEngine.HSTEngine_AmountIsZero.selector, amountToBurn));
        engine.burnHST(amountToBurn);
        vm.stopPrank();
    }

    function testRevertsIfBurnsMoreThanUserHas() public collateralDeposited {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.burnHST(1);
    }

    function testCanBurnHST() public collateralDepositedAndHSTMinted {
        vm.startPrank(USER);
        HST.approve(address(engine), AMOUNT_HST_MINT);
        engine.burnHST(AMOUNT_HST_MINT);
        vm.stopPrank();

        uint256 userBalance = HST.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    /////////////////////////////////
    //// Redeem Collateral Tests ////
    ////////////////////////////////

    function testRevertsIfRedeemedCollateralIsZero() public collateralDeposited {
        vm.startPrank(USER);
        uint256 collateralToDeposit = 0;
        vm.expectRevert(abi.encodeWithSelector(HSTEngine.HSTEngine_AmountIsZero.selector, collateralToDeposit));
        engine.redeemCollateral(weth, collateralToDeposit);
        vm.stopPrank();
    }

    function testCollateralRedeemedAndGetInfo() public {
        ERC20Mock(weth).approve(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 userBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalance, AMOUNT_COLLATERAL);
    }

    function testRevertEmitsCorrectArgs() public {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    } 
}