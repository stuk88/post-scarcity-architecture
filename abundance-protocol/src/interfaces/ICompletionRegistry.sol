// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICompletionRegistry — Soulbound project records
/// @notice Organisations are records, not tokens. They cannot be sold, fractionalised,
///         or merged into a private entity. Milestone tranches are released by contract
///         logic when required attestations are recorded, not by a Treasury signer.
interface ICompletionRegistry {
    // ── Types ──

    enum Outcome { InProgress, Delivered, PartialPivot, HonestFailure, Abandoned, Fraudulent }

    struct Project {
        bytes32 orgId;
        uint256 proposalId;
        uint256 budget;
        uint256 budgetSpent;
        Outcome outcome;
        uint256 milestonesTotal;
        uint256 milestonesCompleted;
        uint256 registeredAt;
        uint256 finalizedAt;
    }

    // ── Events ──

    event ProjectRegistered(uint256 indexed projectId, bytes32 indexed orgId, uint256 proposalId, uint256 budget);
    event MilestoneCompleted(uint256 indexed projectId, uint256 milestoneIndex, bytes32 evidenceHash);
    event TrancheReleased(uint256 indexed projectId, uint256 milestoneIndex, uint256 amount);
    event OutcomeFinalized(uint256 indexed projectId, Outcome outcome);
    event CooldownApplied(bytes32 indexed orgId, uint256 until);
    event FraudBountyActivated(uint256 indexed projectId, bytes32 indexed orgId);

    // ── Mutators ──

    /// @notice Register a new funded project from a raffle win
    function registerProject(bytes32 orgId, uint256 proposalId, uint256 budget, uint256 milestones) external;

    /// @notice Record milestone completion with evidence hash
    function completeMilestone(uint256 projectId, bytes32 evidenceHash) external;

    /// @notice Release a milestone tranche (called by contract logic, not a signer)
    function releaseTranche(uint256 projectId, uint256 milestoneIndex) external;

    /// @notice Finalize the project outcome
    function finalizeOutcome(uint256 projectId, Outcome outcome) external;

    // ── Views ──

    /// @notice Get full project record
    function getProject(uint256 projectId) external view returns (Project memory);

    /// @notice Whether an org is in a cooldown period (post-abandonment)
    function isInCooldown(bytes32 orgId) external view returns (bool);

    /// @notice Whether an org is banned (post-fraud)
    function isBanned(bytes32 orgId) external view returns (bool);

    /// @notice Total projects registered
    function projectCount() external view returns (uint256);
}
