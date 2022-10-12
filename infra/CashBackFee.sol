// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IDyosToken.sol";

contract CashBackFee {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    uint256 DISTRIBUTION_FEE = 
    address treasury;
    address governance;
    IERC20Upgradeable wNative;
    IDyosToken govToken;
    constructor (address _treasury,address _wNative,address _govToken){
        governance = msg.sender;
       govToken = IDyosToken(_govToken);
        wNative  = IERC20Upgradeable(_wNative);
        treasury = _treasury;
    }
    
    function cashbackFeeClaim(uint256 _amount) external {
        uint256 accountBalance = govToken.balanceOf(msg.sender);

        govToken.burnDyosFrom(msg.sender,accountBalance);
        
    }



}