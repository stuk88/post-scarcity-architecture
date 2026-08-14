// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILevy — Machine-output levy
/// @notice Digital output (on-chain revenue) is levied automatically. Physical output
///         (off-chain, oracle-attested) is levied on attested value. The levy rate is
///         flat and low to weaken evasion incentive. Collected levy is routed to Treasury
///         and burned from circulation (contraction lever).
interface ILevy {
    // ── Types ──

    enum OutputType { Digital, Physical }

    // ── Events ──

    event DigitalLevyCollected(bytes32 indexed orgId, uint256 settledRevenue, uint256 levyAmount);
    event PhysicalLevyCollected(bytes32 indexed orgId, uint256 attestedValue, uint256 levyAmount, bytes32 oracleProof);
    event LevyRateUpdated(uint256 oldRate, uint256 newRate);
    event PeriodRolled(uint256 indexed newPeriod, uint256 previousTotal);

    // ── Mutators ──

    /// @notice Assess and collect levy on digital/on-chain output (automatic)
    function collectDigital(bytes32 orgId, uint256 settledRevenue) external;

    /// @notice Assess levy on oracle-attested physical output
    function collectPhysical(bytes32 orgId, uint256 attestedValue, bytes32 oracleProof) external;

    // ── Views ──

    /// @notice Current levy rate (basis points, metric-layer parameter)
    function currentRate() external view returns (uint256);

    /// @notice Total levied in the current period
    function periodTotal() external view returns (uint256);

    /// @notice Total levied for a specific organisation in the current period
    function orgPeriodTotal(bytes32 orgId) external view returns (uint256);

    /// @notice Current period number
    function currentPeriod() external view returns (uint256);
}
