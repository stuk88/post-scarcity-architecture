// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEmergency — Pre-authorized circuit breakers with auto-expiry
/// @notice Triggers are oracle thresholds set during peacetime. Activation auto-expires;
///         renewal requires a fresh sortition supermajority; a minority kill switch can
///         terminate early. Emergency powers increase transparency — every action is
///         logged on-chain. The emergency layer can pause a flow and redirect a budget.
///         It can never rewrite the protocol.
interface IEmergency {
    // ── Types ──

    enum TriggerState { Inactive, Active, Expired }

    struct Trigger {
        bytes32 triggerId;
        bytes32 metricKey;
        uint256 threshold;
        bytes32 responseAction;
        uint256 duration;
        uint256 activatedAt;
        TriggerState state;
    }

    // ── Events ──

    event TriggerRegistered(bytes32 indexed triggerId, bytes32 metricKey, uint256 threshold, uint256 duration);
    event TriggerActivated(bytes32 indexed triggerId, uint256 activatedAt, uint256 expiresAt);
    event TriggerExpired(bytes32 indexed triggerId);
    event TriggerRenewed(bytes32 indexed triggerId, uint256 panelId, uint256 newExpiresAt);
    event TriggerTerminated(bytes32 indexed triggerId, uint256 panelId);
    event ScarcityBreakerActivated(bytes32 indexed goodId, uint256 priceChannel);
    event ScarcityBreakerDeactivated(bytes32 indexed goodId);
    event ScarcityBreakerNormalized(bytes32 indexed goodId, uint256 normalizedValue);

    // ── Mutators ──

    /// @notice Activate a pre-set emergency trigger (checks oracle threshold)
    function activate(bytes32 triggerId) external;

    /// @notice Check and process auto-expiry (anyone can call)
    function checkExpiry(bytes32 triggerId) external;

    /// @notice Renew an active emergency (requires fresh sortition supermajority)
    function renew(bytes32 triggerId, uint256 panelId) external;

    /// @notice Minority kill switch — terminate an emergency early
    function terminateEarly(bytes32 triggerId, uint256 panelId) external;

    /// @notice Activate a scarcity circuit breaker for a specific good (requires panel approval)
    function activateScarcityBreaker(bytes32 goodId, uint256 priceChannel, bytes32 metricKey, uint256 normalizationThreshold, uint256 panelId) external;

    /// @notice Deactivate a scarcity breaker when ratio normalises (requires panel approval)
    function deactivateScarcityBreaker(bytes32 goodId, uint256 panelId) external;

    /// @notice Permissionless auto-close when demand/supply ratio normalizes below threshold
    function normalizeScarcityBreaker(bytes32 goodId) external;

    // ── Views ──

    /// @notice Whether a trigger is currently active
    function isActive(bytes32 triggerId) external view returns (bool);

    /// @notice Get full trigger record
    function getTrigger(bytes32 triggerId) external view returns (Trigger memory);

    /// @notice Whether a scarcity breaker is active for a good
    function isScarcityBreakerActive(bytes32 goodId) external view returns (bool);
}
