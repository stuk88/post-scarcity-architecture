// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IParameterStore — Read-only parameter access for protocol contracts
/// @notice Thin facade over MetricRegistry providing typed getters for the parameters
///         that protocol contracts need. Protocol contracts read from here, never from
///         MetricRegistry directly — this keeps the coupling surface minimal.
interface IParameterStore {
    // ── Views ──

    /// @notice Basket cost (for Credit peg and base allocation rate), 18 decimals
    function basketCost() external view returns (uint256);

    /// @notice Capped gradient ceiling (maximum payout), 18 decimals
    function gradientCeiling() external view returns (uint256);

    /// @notice Capped gradient floor (minimum payout), 18 decimals
    function gradientFloor() external view returns (uint256);

    /// @notice Levy rate in basis points (e.g. 500 = 5%)
    function levyRate() external view returns (uint256);

    /// @notice Minimum audit stake in Credit, 18 decimals
    function minAuditStake() external view returns (uint256);

    /// @notice Raffle pool budget per tier for the current period, 18 decimals
    function poolBudget(uint8 tier) external view returns (uint256);

    /// @notice Decay period in blocks
    function decayPeriod() external view returns (uint256);

    /// @notice Sortition panel size
    function panelSize() external view returns (uint256);

    /// @notice Supermajority threshold in basis points (e.g. 6667 = 66.67%)
    function supermajorityThreshold() external view returns (uint256);

    /// @notice Emergency auto-expiry duration in blocks
    function emergencyDuration() external view returns (uint256);

    /// @notice Audit review window in seconds (claim expires if <3 reviews within this window)
    function auditReviewWindow() external view returns (uint256);

    /// @notice Bounty multiplier in basis points (e.g. 20000 = 2x the stake)
    function bountyMultiplier() external view returns (uint256);
}
