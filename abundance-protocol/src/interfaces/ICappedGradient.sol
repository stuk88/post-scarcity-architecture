// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICappedGradient — Bounded payout arithmetic
/// @notice Every payout function returns a value between floor and ceiling.
///         The ratio must sit below the corruption threshold and above 1.
///         The gradient is not a guideline — it is a number the function will not
///         return a result outside of.
interface ICappedGradient {
    // ── Events ──

    event BoundsUpdated(uint256 oldFloor, uint256 newFloor, uint256 oldCeiling, uint256 newCeiling);

    // ── Views ──

    /// @notice Clamp a raw payout amount to the gradient bounds
    function clamp(uint256 rawAmount) external view returns (uint256);

    /// @notice Current floor (minimum payout)
    function floor() external view returns (uint256);

    /// @notice Current ceiling (maximum payout)
    function ceiling() external view returns (uint256);

    /// @notice Ratio (ceiling / floor) — must be below corruption threshold
    function ratio() external view returns (uint256);
}
