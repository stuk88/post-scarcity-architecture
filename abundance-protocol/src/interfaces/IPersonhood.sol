// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPersonhood — Pluggable proof-of-personhood gate
/// @notice Multiple providers run in parallel; no single provider is a point of capture.
///         The protocol reads attestations but never overrides or issues them.
interface IPersonhood {
    // ── Events ──

    event PersonAttested(bytes32 indexed id, address indexed provider, uint256 epoch);
    event PersonRevoked(bytes32 indexed id, address indexed provider);
    event ProviderAdded(address indexed provider);
    event ProviderRemoved(address indexed provider);

    // ── Views ──

    /// @notice Returns true if `id` is a verified, unrevoked unique person
    function isUniquePerson(bytes32 id) external view returns (bool);

    /// @notice Epoch when the attestation was last refreshed
    function attestationEpoch(bytes32 id) external view returns (uint256);

    /// @notice Which provider issued the attestation
    function provider(bytes32 id) external view returns (address);

    /// @notice Whether the attestation has been revoked by its provider
    function isRevoked(bytes32 id) external view returns (bool);

    /// @notice Total number of currently verified persons
    function verifiedCount() external view returns (uint256);
}
