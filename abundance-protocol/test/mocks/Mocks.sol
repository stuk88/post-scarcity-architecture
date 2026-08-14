// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPersonhood} from "../../src/interfaces/IPersonhood.sol";
import {IRandomnessBeacon} from "../../src/interfaces/IRandomnessBeacon.sol";
import {IParameterStore} from "../../src/interfaces/IParameterStore.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";
import {IMetricRegistry} from "../../src/interfaces/IMetricRegistry.sol";

contract MockPersonhood is IPersonhood {
    mapping(bytes32 => bool) internal _verified;
    uint256 internal _count;

    function addPerson(bytes32 id) external {
        if (!_verified[id]) {
            _verified[id] = true;
            _count++;
        }
    }

    function removePerson(bytes32 id) external {
        if (_verified[id]) {
            _verified[id] = false;
            _count--;
        }
    }

    function isUniquePerson(bytes32 id) external view returns (bool) {
        return _verified[id];
    }

    function attestationEpoch(bytes32) external pure returns (uint256) {
        return 1;
    }

    function provider(bytes32) external view returns (address) {
        return address(this);
    }

    function isRevoked(bytes32) external pure returns (bool) {
        return false;
    }

    function verifiedCount() external view returns (uint256) {
        return _count;
    }
}

contract MockBeacon is IRandomnessBeacon {
    uint256 internal _nextId;
    mapping(uint256 => uint256) internal _seeds;
    mapping(uint256 => bool) internal _fulfilled;
    mapping(uint256 => uint256) internal _requestBlocks;
    uint256 public baseSeed = 12_345;

    function setBaseSeed(uint256 seed) external {
        baseSeed = seed;
    }

    function requestSeed() external returns (uint256 requestId) {
        requestId = _nextId++;
        _seeds[requestId] = uint256(keccak256(abi.encodePacked(baseSeed, requestId)));
        _fulfilled[requestId] = true;
        _requestBlocks[requestId] = block.number;
        emit SeedRequested(requestId, msg.sender);
        emit SeedFulfilled(requestId, _seeds[requestId]);
    }

    function fulfillSeed(uint256 requestId, uint256 seed) external {
        _seeds[requestId] = seed;
        _fulfilled[requestId] = true;
        emit SeedFulfilled(requestId, seed);
    }

    function getSeed(uint256 requestId) external view returns (uint256) {
        return _seeds[requestId];
    }

    function isFulfilled(uint256 requestId) external view returns (bool) {
        return _fulfilled[requestId];
    }

    function requestBlock(uint256 requestId) external view returns (uint256) {
        return _requestBlocks[requestId];
    }
}

contract MockParameterStore is IParameterStore {
    uint256 internal _basketCost = 1e18;
    uint256 internal _gradientCeiling = 10e18;
    uint256 internal _gradientFloor = 1e18;
    uint256 internal _levyRate = 500;
    uint256 internal _minAuditStake = 100e18;
    uint256 internal _decayPeriod = 1000;
    uint256 internal _panelSize = 7;
    uint256 internal _supermajorityThreshold = 6667;
    uint256 internal _emergencyDuration = 100;
    uint256 internal _auditReviewWindow = 7200;
    mapping(uint8 => uint256) internal _poolBudgets;

    function setBasketCost(uint256 v) external {
        _basketCost = v;
    }

    function setGradientCeiling(uint256 v) external {
        _gradientCeiling = v;
    }

    function setGradientFloor(uint256 v) external {
        _gradientFloor = v;
    }

    function setLevyRate(uint256 v) external {
        _levyRate = v;
    }

    function setMinAuditStake(uint256 v) external {
        _minAuditStake = v;
    }

    function setPoolBudget(uint8 tier, uint256 v) external {
        _poolBudgets[tier] = v;
    }

    function setSupermajorityThreshold(uint256 v) external {
        _supermajorityThreshold = v;
    }

    function setEmergencyDuration(uint256 v) external {
        _emergencyDuration = v;
    }

    function setDecayPeriod(uint256 v) external {
        _decayPeriod = v;
    }

    function setPanelSize(uint256 v) external {
        _panelSize = v;
    }

    uint256 internal _bountyMultiplier = 20000;

    function setAuditReviewWindow(uint256 v) external {
        _auditReviewWindow = v;
    }

    function setBountyMultiplier(uint256 v) external {
        _bountyMultiplier = v;
    }

    function basketCost() external view returns (uint256) {
        return _basketCost;
    }

    function gradientCeiling() external view returns (uint256) {
        return _gradientCeiling;
    }

    function gradientFloor() external view returns (uint256) {
        return _gradientFloor;
    }

    function levyRate() external view returns (uint256) {
        return _levyRate;
    }

    function minAuditStake() external view returns (uint256) {
        return _minAuditStake;
    }

    function poolBudget(uint8 tier) external view returns (uint256) {
        return _poolBudgets[tier];
    }

    function decayPeriod() external view returns (uint256) {
        return _decayPeriod;
    }

    function panelSize() external view returns (uint256) {
        return _panelSize;
    }

    function supermajorityThreshold() external view returns (uint256) {
        return _supermajorityThreshold;
    }

    function emergencyDuration() external view returns (uint256) {
        return _emergencyDuration;
    }

    function auditReviewWindow() external view returns (uint256) {
        return _auditReviewWindow;
    }

    function bountyMultiplier() external view returns (uint256) {
        return _bountyMultiplier;
    }
}

contract MockTreasury is ITreasury {
    uint256 public rolesFunded;

    function streamBaseAllocation(bytes32) external {}

    function fundRafflePool(uint8) external {}

    function payBounty(uint256, uint256) external {}

    function releaseProjectTranche(uint256, bytes32, uint256) external {}

    function fundRole(bytes32, uint256) external {
        rolesFunded++;
    }

    function collectLevy(bytes32, uint256) external {}

    function totalCirculating() external pure returns (uint256) {
        return 0;
    }

    function periodLevyCollected() external pure returns (uint256) {
        return 0;
    }

    function currentPeriod() external pure returns (uint256) {
        return 0;
    }
}

contract MockSortition {
    mapping(uint256 => bool) internal _resolved;
    mapping(uint256 => bool) internal _approved;
    mapping(uint256 => bytes32) internal _purposes;

    function setResolution(uint256 panelId, bool resolved, bool approved) external {
        _resolved[panelId] = resolved;
        _approved[panelId] = approved;
    }

    function setPurpose(uint256 panelId, bytes32 purpose) external {
        _purposes[panelId] = purpose;
    }

    function isResolved(uint256 panelId) external view returns (bool, bool) {
        return (_resolved[panelId], _approved[panelId]);
    }

    function getPanel(uint256 panelId) external view returns (ISortition.Panel memory) {
        ISortition.Panel memory p;
        p.panelId = panelId;
        p.purpose = _purposes[panelId];
        p.state = _resolved[panelId] ? ISortition.PanelState.Resolved : ISortition.PanelState.Active;
        return p;
    }

    function requestPanel(bytes32, uint256) external returns (uint256) {
        return 0;
    }

    function finalizePanel(uint256) external {}
}

contract MockMetricRegistry {
    mapping(bytes32 => uint256) internal _values;
    mapping(bytes32 => bool) internal _exists;

    function setMetric(bytes32 key, uint256 value) external {
        _values[key] = value;
        _exists[key] = true;
    }

    function getMetric(bytes32 key) external view returns (uint256) {
        require(_exists[key], "Metric not found");
        return _values[key];
    }

    function isExpired(bytes32) external pure returns (bool) {
        return false;
    }

    function getMetricRecord(bytes32 key) external view returns (IMetricRegistry.Metric memory) {
        IMetricRegistry.Metric memory m;
        m.key = key;
        m.value = _values[key];
        return m;
    }
}
