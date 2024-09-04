// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

/**
* @title HSTEngine
* @author Samuel Swizz
* 
* This the backbone of the HST ecosystem designed to beb as minimal as possible and also have tokens maintain 1 token = $1 peg.
* The stablecoin has the following properties:
* - Exogenous Collateral
* - Dollar Pegged
* - Algorithmic Minting
*
* This project closely resembles DAI if DAI was not governed, had no fees and was backed by wBTC and wETH.
* The HST stablecoin is "OVERCOLLATERIZED", in o event should the value of the collateral be lower or equal to the value of the stablecoin.
*
@notice This contract is the core of the HST ecosystem. It handles all the logic for mining and redeeming HST, as well as depositing and withdrawing collateral.
@notice This contractv is VERY loosely based on the MakerDAO DSS (DAI) system
*/

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {HopesStableToken} from "./HopesStableToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract HSTEngine is ReentrancyGuard {

    /////////////////////
    //// Errors /////////
    /////////////////////

    error HSTEngine_AmountIsZero();
    error HSTEngine_DifferenceInArrayLength();
    error HSTEngine_TokenNotAllowedAsCollateral(address tokenAddress);
    error HSTEngine_TransferFailed();
    error HSTEngine_ZeroValueForCollateral(address user);
    error HSTEngine_HealthFactorTooLow(uint256 userHealthFactor);
    error HSTEngine_FailedToMint();
    error HSTEngine_HealthFactorIsOkay(uint256 userHealthFactor);    
    error HSTEngine_HealthfactorYetToImprove();        

    using OracleLib for AggregatorV3Interface;                      

    HopesStableToken private immutable i_HST;

    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_DIVISOR = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_PriceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits;
    mapping(address user => uint256 amountHSTMinted) private s_amountHSTMinted;

    address[] private s_collateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed redeemedfrom, address indexed redeemedTo, address indexed token, uint256 amount);

    /////////////////////
    //// Modifiers //////
    /////////////////////

    modifier notZero(uint256 amount) {
        if(amount == 0) {
            revert HSTEngine_AmountIsZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if(s_PriceFeed[tokenAddress] == address(0)) {
            revert HSTEngine_TokenNotAllowedAsCollateral(tokenAddress);
        }
        _;
    }
    
    /////////////////////
    //// Functions //////
    /////////////////////

    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses,
        address HSTcontract
    ) {
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert HSTEngine_DifferenceInArrayLength();
        }
        for(uint256 i = 0; i < tokenAddresses.length; i++) {
            s_PriceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_HST = HopesStableToken(HSTcontract);
    }

    //////////////////////////////
    //// External Functions //////
    //////////////////////////////

    /**
     * @dev Deposits collateral and mints HST
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral
     * @param amountHST The amount of HST Stablecoin to mint
     * @notice This function will deposit collateral and mint HST in one transaction
     */
    function depositCollateralAndMintHST(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountHST
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintHST(amountHST);
    }

    /**
    * @dev Deposits collateral for HST
    * @notice Following a CEI pattern
    * @param tokenCollateralAddress The address of the collateral token
    * @param amountCollateral The amount of collateral
    */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
    public 
    notZero(amountCollateral) 
    isAllowedToken(tokenCollateralAddress) 
    nonReentrant{
        s_collateralDeposits[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert HSTEngine_TransferFailed();
        }
    }
    /**
    *
    */

    function redeemCollateralForHST(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountHST
    ) external {
        burnHST(amountHST);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // Redeem Collateral and Burn HST already checks Health factor
    }

    function redeemCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) public notZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);

        _revertIfHealthFactorIsLow(msg.sender);
    }

    /**
    * @dev Mints HST Stablecoin based on deposited collateral
    * @notice Following a CEI pattern
    * @notice Must have more collateral than minimum threshold
    * @param amountHSTToMint The amount of HST Stablecoin to mint
    */
    function mintHST(
        uint256 amountHSTToMint
    ) public notZero(amountHSTToMint) nonReentrant{
        s_amountHSTMinted[msg.sender] += amountHSTToMint;
        // If they mint a stablecoin value worth more than the value of collateral deposited
        _revertIfHealthFactorIsLow(msg.sender);

        bool minted = i_HST.mint(msg.sender, amountHSTToMint);
        if(!minted) {
            revert HSTEngine_FailedToMint();
        }
    }

    function burnHST(uint256 amountHST) public notZero(amountHST) nonReentrant {
        _burnHST(msg.sender, msg.sender, amountHST);

        _revertIfHealthFactorIsLow(msg.sender); // Shouldn't ever get to this line
    }

    /**
    * @dev This function liquidates the position of a user once his HST stablecoin holding is undercollaterized.
    * @param collateral The ERC20 collateral to liquidate from the user
    * @param user The user that has gone below the set Health factor
    * @param debtToCover The amount of HST needed to burn to improve the user's health factor
    * @notice You can partially liquidate a user
    * @notice You will get a liquidation bonus for taking the user's funds.
    * @notice This function only works assuming the system remains 200% overcollateralized
    * @notice A known issue would be if the protocol were 100% overcollateralized or less, then it would be impossible to incentivise liquidation. For EG, if the collateral price plummeted before anyone could be liquidated.
    */
    function liquidate(
        address collateral, 
        address user, 
        uint256 debtToCover
    ) external notZero(debtToCover) nonReentrant {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor > MIN_HEALTH_FACTOR) {
            revert HSTEngine_HealthFactorIsOkay(userHealthFactor);
        }
        // We want to burn their HST Debt and take their collateral
        // Eg: Bad User: $140 worth of Collateral, $100 worth of HST
        // Debt To Cover: $100
        // Collateral to Take: $140
        // Now we need to find the correct value of the collateral. i.e for example the value of wETH that'd give $140

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_DIVISOR;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);

        // uint256 availableHST = s_amountHSTMinted[user];
        _burnHST(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= userHealthFactor) {
            revert HSTEngine_HealthfactorYetToImprove();
        }

         _revertIfHealthFactorIsLow(msg.sender);
    }

    function getHealthFactor() external view returns(uint256) {
        return _healthFactor(msg.sender);
    }

    /////////////////////////////////////////////
    //// Private & Internal View Functions //////
    /////////////////////////////////////////////

    /**
    * @dev Retrieve health factor for a user
    * @notice Returns how close to liquidation a user is
    * @notice If a user goes below 1, they can be liquidated
    * @param user The user being checked
    */

    function _burnHST(address user, address HSTFrom, uint256 amountHST) private {
        s_amountHSTMinted[user] -= amountHST;
        bool success = i_HST.transferFrom(HSTFrom, address(this), amountHST);
        if(!success) {
            revert HSTEngine_TransferFailed();
        }
        i_HST.burn(amountHST);
    }

    function _redeemCollateral(address from, address to, address collateralTokenAddress, uint256 amountCollateral) private {
        s_collateralDeposits[from][collateralTokenAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, collateralTokenAddress, amountCollateral);
        bool success = IERC20(collateralTokenAddress).transferFrom(from, to, amountCollateral);

        if(!success) {
            revert HSTEngine_TransferFailed();
        }
    }
    function _healthFactor(address user) private view returns(uint256) {
        // Total HST Minted
        // Total Collateral Value
        (uint256 totalHSTMinted, uint256 totalValueOfCollateral) = _getAccountInformation(user);
        uint256 collateralAdjusted = (totalValueOfCollateral * LIQUIDATION_THRESHOLD) / LIQUIDATION_DIVISOR;
        return (collateralAdjusted * PRECISION) / totalHSTMinted;
    }

    function _getTokenValue(address token, uint256 amount) private view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckRoundData();
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * amount) / PRECISION;
    }

    function _getAccountInformation(address user) private view returns(uint256 totalHSTMinted, uint256 totalValueOfCollateral) {
        totalHSTMinted = s_amountHSTMinted[user];
        totalValueOfCollateral = getValueOfCollateralInUSD(user);
    }

    function _revertIfHealthFactorIsLow(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor <= MIN_HEALTH_FACTOR) {
            revert HSTEngine_HealthFactorTooLow(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 amountHSTMinted, uint256 totalValueOfCollateral) private pure returns(uint256) {
        if(amountHSTMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (totalValueOfCollateral * LIQUIDATION_THRESHOLD) / LIQUIDATION_DIVISOR;
        return (collateralAdjustedForThreshold * 1e18) / amountHSTMinted;
    }

    /////////////////////////////////////////////
    //// Public & External View Functions ///////
    /////////////////////////////////////////////

    function getTokenAmountFromUsd(address collateral, uint256 usdAmountInWei) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeed[collateral]);
        (, int256 price,,,) = priceFeed.staleCheckRoundData();
        uint256 amountInWei = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEE_PRECISION);
        return amountInWei;
    }

    function getValueOfCollateralInUSD(address User) public view returns(uint256) {
        uint256 collateralvalue = 0;
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposits[User][token];
            collateralvalue += _getTokenValue(token, collateralAmount);
        }
        return collateralvalue;
    }

    function getTokenValue(address token, uint256 amount) external view returns(uint256) {
        return _getTokenValue(token, amount);
    }

    function getAccountInformation(address user) external view returns(uint256 totalHSTMinted, uint256 totalValueOfCollateral) {
        (totalHSTMinted, totalValueOfCollateral) = _getAccountInformation(user);
    }

    function getAddtionalFeePrecision() external view returns(uint256) {
        return ADDITIONAL_FEE_PRECISION;
    }

    function getPrecision() external view returns(uint256) {
        return PRECISION;
    }

    function calculateHealthFactor(uint256 totalHSTMinted, uint256 totalValueOfCollateral) external view returns(uint256) {
        return _calculateHealthFactor(totalHSTMinted, totalValueOfCollateral);
    }

    function getHealthFactor(address user) external view returns(uint256) {
        return _healthFactor(user);
    }

    function getLiquidationThreshold() external view returns(uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationDivisor() external view returns(uint256) {
        return LIQUIDATION_DIVISOR;
    }

    function getMinHealthFactor() external view returns(uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns(address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) external view returns(address) {
        return s_PriceFeed[token];
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns(uint256) {
        return s_collateralDeposits[user][token];
    }
}