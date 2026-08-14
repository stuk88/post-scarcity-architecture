// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IRandomnessBeacon — VRF wrapper for manipulation-resistant draws
/// @notice Seed is not controllable by any last revealer. Entry closes before the seed
///         is knowable, the entry set is frozen, and the draw is a single transaction
///         over that frozen set. Wraps Chainlink VRF or drand-style commit-reveal beacons.
interface IRandomnessBeacon {
    // ── Events ──

    event SeedRequested(uint256 indexed requestId, address indexed requester);
    event SeedFulfilled(uint256 indexed requestId, uint256 seed);

    // ── Mutators ──

    /// @notice Request a random seed (committed, not yet revealed)
    function requestSeed() external returns (uint256 requestId);

    /// @notice Fulfill a seed — callback from VRF provider (only callable by provider)
    function fulfillSeed(uint256 requestId, uint256 seed) external;

    // ── Views ──

    /// @notice Get the fulfilled seed value
    function getSeed(uint256 requestId) external view returns (uint256);

    /// @notice Whether the seed has been fulfilled
    function isFulfilled(uint256 requestId) external view returns (bool);

    /// @notice The block at which the seed was requested
    function requestBlock(uint256 requestId) external view returns (uint256);
}
