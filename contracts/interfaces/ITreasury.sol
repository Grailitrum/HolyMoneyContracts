// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITreasury {
    function epoch() external view returns (uint256);

    function nextEpochPoint() external view returns (uint256);

    function getHolyPrice() external view returns (uint256);

    function buyBHolys(uint256 amount, uint256 targetPrice) external;

    function redeemBHolys(uint256 amount, uint256 targetPrice) external;
}
