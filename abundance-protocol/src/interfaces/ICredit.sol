// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ICredit — Non-equity unit of account
/// @notice ERC-20 compatible, basket-pegged, yield-free, no governance weight.
///         A claim on the productive capacity of the zone, not on any organisation within it.
///         Mint authority is restricted to the Treasury. Burn is used by the Levy (contraction).
interface ICredit is IERC20 {
    // ── Events ──

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event BasketRateUpdated(uint256 oldRate, uint256 newRate, address indexed oracle);

    // ── Mutators ──

    /// @notice Mint new Credit — only callable by Treasury
    function mint(address to, uint256 amount) external;

    /// @notice Burn Credit from circulation — used by Levy collection
    function burn(address from, uint256 amount) external;

    /// @notice Update the basket peg target — only callable by the metric-layer oracle
    function updateBasketRate(uint256 newRate) external;

    // ── Views ──

    /// @notice Current basket peg target (1 Credit = 1 basket, scaled to 18 decimals)
    function basketRate() external view returns (uint256);

    /// @notice Cumulative Credit ever minted
    function totalMinted() external view returns (uint256);

    /// @notice Cumulative Credit ever burned
    function totalBurned() external view returns (uint256);
}
