// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IMetricRegistry — Governed parameter definitions with decay timers
/// @notice Metrics are on-chain parameters: what is measured, at what threshold, with
///         what weight. Updatable only by sortition assembly supermajority. Every metric
///         carries a decay timer — if not re-ratified within its decay period, it expires.
interface IMetricRegistry {
    // ── Types ──

    struct Metric {
        bytes32 key;
        uint256 value;
        uint256 decayDeadline;
        uint256 lastUpdated;
        bytes32 oracleSource;
    }

    // ── Events ──

    event MetricUpdated(bytes32 indexed key, uint256 oldValue, uint256 newValue, uint256 panelId);
    event MetricReratified(bytes32 indexed key, uint256 newDeadline);
    event MetricExpired(bytes32 indexed key);
    event MetricCreated(bytes32 indexed key, uint256 value, bytes32 oracleSource, uint256 decayDeadline);
    event DivergenceClaimFiled(bytes32 indexed key, bytes32 evidenceHash, uint256 claimId);
    event DivergenceEscalated(bytes32 indexed key, uint256 claimId);

    // ── Mutators ──

    /// @notice Update metric value (sortition supermajority only)
    function updateMetric(bytes32 key, uint256 newValue) external;

    /// @notice Re-ratify a metric (resets its decay timer)
    function reratify(bytes32 key) external;

    /// @notice File a metric-divergence claim (routes to the Audit contract)
    function fileDivergenceClaim(bytes32 key, bytes32 evidenceHash) external;

    /// @notice Create a new metric (sortition supermajority only)
    function createMetric(bytes32 key, uint256 value, bytes32 oracleSource) external;

    // ── Views ──

    /// @notice Get current metric value (reverts if expired)
    function getMetric(bytes32 key) external view returns (uint256);

    /// @notice Whether the metric has expired (past its decay deadline)
    function isExpired(bytes32 key) external view returns (bool);

    /// @notice Get full metric record
    function getMetricRecord(bytes32 key) external view returns (Metric memory);
}
