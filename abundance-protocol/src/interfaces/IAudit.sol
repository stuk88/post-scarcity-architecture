// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAudit — Permissionless bonded auditing with symmetric stakes
/// @notice Any personhood identity can form an audit group and file a bonded claim.
///         Three independent audit groups review. Resolution follows the symmetric-stakes
///         rule: confirmed = bounty paid, unconfirmed = stake returned (good faith),
///         bad-faith = stake slashed. Stakes are in Credit, not native ETH.
interface IAudit {
    // ── Types ──

    enum Resolution { Pending, Confirmed, Unconfirmed, BadFaith, Expired }

    struct Claim {
        bytes32 claimant;
        bytes32 target;
        bytes32 evidenceHash;
        uint256 stake;
        Resolution resolution;
        uint8 reviewsFor;
        uint8 reviewsAgainst;
        uint256 filedAt;
        uint256 resolvedAt;
        uint256 reviewDeadline;
    }

    // ── Events ──

    event ClaimFiled(uint256 indexed claimId, bytes32 indexed claimant, bytes32 indexed target, uint256 stake);
    event ReviewSubmitted(uint256 indexed claimId, bytes32 indexed reviewer, bool upheld);
    event ClaimResolved(uint256 indexed claimId, Resolution resolution);
    event BountyPaid(uint256 indexed claimId, bytes32 indexed claimant, uint256 amount);
    event StakeSlashed(uint256 indexed claimId, bytes32 indexed claimant, uint256 amount);
    event StakeRefunded(uint256 indexed claimId, bytes32 indexed claimant, uint256 amount);
    event ClaimExpired(uint256 indexed claimId, bytes32 indexed claimant, uint256 stakeRefunded);

    // ── Mutators ──

    /// @notice File a bonded claim against a target — stake is in Credit (transferFrom)
    function fileClaim(bytes32 target, bytes32 evidenceHash, uint256 stakeAmount) external returns (uint256 claimId);

    /// @notice Submit an independent review (3 required from 3 different audit groups)
    function review(uint256 claimId, bool upheld) external;

    /// @notice Resolve after 3 reviews are in
    function resolve(uint256 claimId) external;

    /// @notice Expire a claim whose review deadline has passed without 3 reviews — refunds stake
    function expire(uint256 claimId) external;

    // ── Views ──

    /// @notice Get claim details
    function getClaim(uint256 claimId) external view returns (Claim memory);

    /// @notice Minimum stake required (metric-layer parameter)
    function minStake() external view returns (uint256);

    /// @notice Total claims filed
    function claimCount() external view returns (uint256);

    /// @notice Whether a reviewer has already reviewed a specific claim
    function hasReviewed(uint256 claimId, bytes32 reviewerId) external view returns (bool);
}
