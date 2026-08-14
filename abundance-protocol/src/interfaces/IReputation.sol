// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IReputation — Soulbound multidimensional reputation
/// @notice Non-transferable, bound to a personhood identity. Tracks accuracy, volume,
///         novelty, and reliability as separate axes. Cannot be bought, sold, lent, or
///         delegated. The protocol's only accumulating asset.
///         Storage: custom mappings (not ERC-721/1155 soulbound).
interface IReputation {
    // ── Types ──

    struct Score {
        uint256 accuracy;
        uint256 volume;
        uint256 novelty;
        uint256 reliability;
    }

    // ── Events ──

    event DimensionUpdated(bytes32 indexed personId, bytes32 indexed dimension, int256 delta, uint256 newValue);
    event ScoreReset(bytes32 indexed personId, bytes32 reason);

    // ── Mutators ──

    /// @notice Update a single reputation dimension — only callable by protocol contracts
    ///         (CompletionRegistry, Audit, Raffle outcomes)
    function updateDimension(bytes32 personId, bytes32 dimension, int256 delta) external;

    // ── Views ──

    /// @notice Get the full reputation score for a person
    function getScore(bytes32 personId) external view returns (Score memory);

    /// @notice Get a single dimension value
    function getDimension(bytes32 personId, bytes32 dimension) external view returns (uint256);

    /// @notice Composite score (weighted sum — weights set by metric layer)
    function compositeScore(bytes32 personId) external view returns (uint256);
}
