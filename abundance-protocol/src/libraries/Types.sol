// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Types — Shared type aliases to prevent bytes32 cross-slot confusion
/// @notice Using raw bytes32 everywhere means a personId can silently go into an orgId
///         slot. These user-defined value types catch that at compile time.

type PersonId is bytes32;
type OrgId is bytes32;
type EvidenceHash is bytes32;
type MetricKey is bytes32;
type TriggerId is bytes32;
type GoodId is bytes32;
