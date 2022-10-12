// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./IERC20.sol";

interface IDyosToken is IERC20 {
    function mintDyos(address _to, uint256 _amount) external;
    function burnDyosFrom(address _account,uint256 _amount) external;
    function setGovernance(address _governance) external;
    function addMinter(address _minter) external;
    function removeMinter(address _minter) external;
}
