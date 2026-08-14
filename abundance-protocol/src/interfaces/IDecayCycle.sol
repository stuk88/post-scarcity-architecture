// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDecayCycle — 10-year constitutional re-founding schedule
/// @notice The protocol layer has no upgrade key. It changes only through the decay cycle:
///         every 10 years, every metric-layer parameter expires unless re-ratified, and the
///         founding document itself is reviewed by a fresh sortition assembly. A true
///         protocol-layer change (new core contracts + state migration) is possible only here.
interface IDecayCycle {
    // ── Types ──

    enum CyclePhase { Normal, ReviewWindow, Migration }

    // ── Events ──

    event CycleStarted(uint256 indexed cycleNumber, uint256 startsAt, uint256 reviewWindowAt);
    event ReviewWindowOpened(uint256 indexed cycleNumber);
    event MigrationApproved(uint256 indexed cycleNumber, uint256 panelId, address newProtocol);
    event MigrationExecuted(uint256 indexed cycleNumber, address oldProtocol, address newProtocol);
    event CycleRenewed(uint256 indexed cycleNumber);

    // ── Mutators ──

    /// @notice Open the review window when the cycle timer expires (anyone can call)
    function openReviewWindow() external;

    /// @notice Approve a migration to new protocol contracts (sortition supermajority)
    function approveMigration(uint256 panelId, address newProtocol) external;

    /// @notice Execute an approved migration (requires the approving panel's ID as proof)
    function executeMigration(uint256 panelId) external;

    /// @notice Renew the current cycle (re-ratify without migration)
    function renewCycle(uint256 panelId) external;

    // ── Views ──

    /// @notice Current cycle number
    function currentCycle() external view returns (uint256);

    /// @notice Current phase of the cycle
    function currentPhase() external view returns (CyclePhase);

    /// @notice Block number when the review window opens
    function reviewWindowBlock() external view returns (uint256);

    /// @notice Whether a migration has been approved but not yet executed
    function pendingMigration() external view returns (bool);

    /// @notice Address of the approved new protocol (zero if none)
    function approvedNewProtocol() external view returns (address);
}
