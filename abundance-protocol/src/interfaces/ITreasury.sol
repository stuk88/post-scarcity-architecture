// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITreasury — Levy revenue holder and Credit issuance authority
/// @notice There is no transferTo(address). The Treasury cannot be drained because
///         it exposes no function that drains it. Every outflow is bounded by the rules
///         of the function that emits it.
interface ITreasury {
    // ── Events ──

    event BaseAllocationStreamed(bytes32 indexed personId, uint256 amount);
    event RafflePoolFunded(uint8 indexed tier, uint256 amount);
    event BountyPaid(uint256 indexed claimId, uint256 amount);
    event ProjectTrancheReleased(uint256 indexed projectId, bytes32 indexed orgId, uint256 amount);
    event RoleFunded(bytes32 indexed personId, uint256 indexed roleId, uint256 amount);
    event LevyCollected(bytes32 indexed orgId, uint256 attestedOutput, uint256 levyAmount);
    event PeriodRolled(uint256 indexed newPeriod);

    // ── Mutators ──

    /// @notice Open/continue a streaming base allocation for a verified person
    function streamBaseAllocation(bytes32 personId) external;

    /// @notice Fund a raffle pool tier for the current period
    function fundRafflePool(uint8 tier) external;

    /// @notice Pay a confirmed audit bounty, scaled to harm exposed
    function payBounty(uint256 claimId, uint256 stakeAmount) external;

    /// @notice Release a milestone tranche for a grant project
    function releaseProjectTranche(uint256 projectId, bytes32 orgId, uint256 trancheAmount) external;

    /// @notice Fund a sortition/audit role for the duration of its term
    function fundRole(bytes32 personId, uint256 roleId) external;

    /// @notice Collect levy from an organisation (inflow — burns Credit, records revenue)
    function collectLevy(bytes32 orgId, uint256 attestedOutput) external;

    // ── Views ──

    /// @notice Total Credit currently in circulation
    function totalCirculating() external view returns (uint256);

    /// @notice Total levy collected in the current period
    function periodLevyCollected() external view returns (uint256);

    /// @notice Current period number
    function currentPeriod() external view returns (uint256);
}
