// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* 
* @title HopesStableToken
* @author Samuel Swizz
* Collateral: Exogenous(wBTC and wETH)
* Minting: Algorithmic
* Relative Stability: Pegged to USD
*
*This is he contract meant to be governed by HSTEngine. This contract is just the ERC20 implementation of our stablecoin system.
*/
contract HopesStableToken is ERC20Burnable, Ownable {
    error HopesStableToken_AmountIsZero();
    error HopesStableToken_MinimumAmountExceeded();
    error HopesStableToken_CantSendToZeroAddress();

    constructor() ERC20("HopesStableToken", "HST") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0) {
            revert HopesStableToken_AmountIsZero();
        } else if(balance < _amount) {
            revert HopesStableToken_MinimumAmountExceeded();
        } else {
            super.burn(_amount);
        }
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        if(_to == address(0)) {
            revert HopesStableToken_CantSendToZeroAddress();
        }  else if (_amount <= 0) {
            revert HopesStableToken_AmountIsZero();
        } else {
            _mint(_to, _amount);
            return true;
        }
    }
}
