// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "../interfaces/IDyosToken.sol";

contract TestDyosCaller {
    IDyosToken govToken;

    constructor(address _govToken){
        govToken = IDyosToken(_govToken);
    }

    function mintDyosCaller(uint256 _amount) external {
        govToken.mintDyos(msg.sender,_amount);
    }
}