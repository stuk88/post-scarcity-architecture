// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRaffle — Verifiable-random funding allocation
/// @notice Production is funded by random selection from a screened pool, not by investors
///         choosing winners. Draw probability is weighted inversely to the size of the ask
///         relative to the pool median (over-ask penalty).
interface IRaffle {
    // ── Types ──

    enum Tier { Micro, Small, Medium, Large, Megaproject }
    enum PoolState { Open, Frozen, Drawn }

    struct Proposal {
        bytes32 proposerId;
        bytes32 contentHash;
        uint256 requestedAmount;
        Tier tier;
        uint256 milestonesCount;
        uint256 submittedAt;
    }

    // ── Events ──

    event ProposalSubmitted(uint256 indexed proposalId, bytes32 indexed proposerId, Tier tier, uint256 amount);
    event EntriesClosed(Tier indexed tier, uint256 indexed drawPeriod, uint256 entryCount);
    event DrawCompleted(Tier indexed tier, uint256 indexed drawPeriod, uint256[] winnerIds, uint256 seed);
    event SurplusReturned(uint256 indexed proposalId, uint256 amount);
    event MegaprojectApproved(uint256 indexed proposalId, uint256 panelId);

    // ── Mutators ──

    /// @notice Submit a proposal to a tier pool (completeness check, never merit)
    function submit(Proposal calldata proposal) external returns (uint256 proposalId);

    /// @notice Close entries for current draw period — freezes the entry set
    function closeEntries(Tier tier) external;

    /// @notice Execute draw using beacon randomness on the frozen entry set
    function draw(Tier tier) external returns (uint256[] memory winnerIds);

    /// @notice Return unspent grant funds to the pool
    function returnSurplus(uint256 proposalId, uint256 amount) external;

    // ── Views ──

    /// @notice Over-ask penalty weight for a proposal (inverse probability scaling)
    function overAskWeight(uint256 proposalId) external view returns (uint256);

    /// @notice Current pool state for a tier
    function poolState(Tier tier) external view returns (PoolState);

    /// @notice Number of entries in the current period for a tier
    function entryCount(Tier tier) external view returns (uint256);

    /// @notice Get proposal details
    function getProposal(uint256 proposalId) external view returns (Proposal memory);

    /// @notice Current draw period number
    function currentPeriod() external view returns (uint256);
}
