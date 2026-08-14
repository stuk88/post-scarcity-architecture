// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IBaseAllocation — Streaming universal base allocation
/// @notice Per-block accrual bound to a personhood identity. The claim is soulbound:
///         it cannot be sold, assigned, or borrowed against at the protocol level.
interface IBaseAllocation {
    // ── Events ──

    event Registered(bytes32 indexed personId, address indexed recipient);
    event Withdrawn(bytes32 indexed personId, address indexed recipient, uint256 amount);
    event Suspended(bytes32 indexed personId);
    event Resumed(bytes32 indexed personId);
    event RateUpdated(uint256 oldRate, uint256 newRate);

    // ── Mutators ──

    /// @notice Register a verified person for streaming allocation
    function register(bytes32 personId, address recipient) external;

    /// @notice Withdraw accrued Credit to the bound address
    function withdraw(bytes32 personId) external returns (uint256 amount);

    /// @notice Suspend allocation (personhood revoked or expired)
    function suspend(bytes32 personId) external;

    /// @notice Resume allocation after re-attestation
    function resume(bytes32 personId) external;

    // ── Views ──

    /// @notice Accrued but unwithdrawn Credit for a person
    function accrued(bytes32 personId) external view returns (uint256);

    /// @notice Current rate per block (basket formula from metric layer)
    function ratePerBlock() external view returns (uint256);

    /// @notice Whether a person is currently registered and active
    function isActive(bytes32 personId) external view returns (bool);

    /// @notice The recipient address bound to a person's allocation
    function recipientOf(bytes32 personId) external view returns (address);
}
