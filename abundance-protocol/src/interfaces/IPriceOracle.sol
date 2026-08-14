// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPriceOracle — Price feed for consumption basket items
/// @notice Returns the current price of a basket item in 18-decimal fixed-point.
interface IPriceOracle {
    function getPrice(bytes32 itemId) external view returns (uint256);
}
