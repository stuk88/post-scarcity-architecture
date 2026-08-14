// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISortition — Random-panel governance
/// @notice One person, one draw, no token voting. When a decision requires human judgment,
///         the protocol draws a panel at random from the personhood registry. The panel is
///         temporary, rotates out on a fixed timer, and is paid as a funded role. Its
///         supermajority is required to act.
interface ISortition {
    // ── Types ──

    enum PanelState { Active, Resolved, Expired, PendingDraw }

    struct Panel {
        uint256 panelId;
        bytes32[] members;
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 purpose;
        PanelState state;
        uint256 votesFor;
        uint256 votesAgainst;
    }

    // ── Events ──

    event PanelRequested(uint256 indexed panelId, bytes32 indexed purpose, uint256 size);
    event PanelDrawn(uint256 indexed panelId, bytes32 indexed purpose, uint256 size, uint256 seed);
    event VoteCast(uint256 indexed panelId, bytes32 indexed memberId, bool approve);
    event PanelResolved(uint256 indexed panelId, bool approved);
    event PanelExpired(uint256 indexed panelId);
    event PanelKilled(uint256 indexed panelId, bytes32 indexed killerId);

    // ── Mutators ──

    /// @notice Request a new panel draw (phase 1 of 2-phase commit)
    function requestPanel(bytes32 purpose, uint256 size) external returns (uint256 panelId);

    /// @notice Finalize a pending panel draw after seed fulfillment (phase 2 of 2-phase commit)
    function finalizePanel(uint256 panelId) external;

    /// @notice Draw a new panel from the personhood registry using the randomness beacon
    function drawPanel(bytes32 purpose, uint256 size) external returns (uint256 panelId);

    /// @notice Cast a vote on a panel decision
    function vote(uint256 panelId, bytes32 memberId, bool approve) external;

    /// @notice Minority kill switch — terminate a panel decision early
    function killSwitch(uint256 panelId) external;

    /// @notice Mark an expired panel (anyone can call after expiry time)
    function expirePanel(uint256 panelId) external;

    // ── Views ──

    /// @notice Whether the panel has resolved and the result
    function isResolved(uint256 panelId) external view returns (bool resolved, bool approved);

    /// @notice Get full panel record
    function getPanel(uint256 panelId) external view returns (Panel memory);

    /// @notice Whether a member has voted on a specific panel
    function hasVoted(uint256 panelId, bytes32 memberId) external view returns (bool);

    /// @notice Total panels ever drawn
    function panelCount() external view returns (uint256);
}
