// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {IMetricRegistry} from "../interfaces/IMetricRegistry.sol";

contract ParameterStore is IParameterStore {
    IMetricRegistry public immutable registry;

    mapping(bytes32 => uint256) internal _genesisValues;

    bytes32 public constant BASKET_COST_KEY = keccak256("BASKET_COST");
    bytes32 public constant GRADIENT_CEILING_KEY = keccak256("GRADIENT_CEILING");
    bytes32 public constant GRADIENT_FLOOR_KEY = keccak256("GRADIENT_FLOOR");
    bytes32 public constant LEVY_RATE_KEY = keccak256("LEVY_RATE");
    bytes32 public constant MIN_AUDIT_STAKE_KEY = keccak256("MIN_AUDIT_STAKE");
    bytes32 public constant DECAY_PERIOD_KEY = keccak256("DECAY_PERIOD");
    bytes32 public constant PANEL_SIZE_KEY = keccak256("PANEL_SIZE");
    bytes32 public constant SUPERMAJORITY_THRESHOLD_KEY = keccak256("SUPERMAJORITY_THRESHOLD");
    bytes32 public constant EMERGENCY_DURATION_KEY = keccak256("EMERGENCY_DURATION");
    bytes32 public constant AUDIT_REVIEW_WINDOW_KEY = keccak256("AUDIT_REVIEW_WINDOW");
    bytes32 public constant BOUNTY_MULTIPLIER_KEY = keccak256("BOUNTY_MULTIPLIER");

    constructor(address _registry) {
        require(_registry != address(0), "ParameterStore: zero registry");
        registry = IMetricRegistry(_registry);

        _genesisValues[BASKET_COST_KEY] = 1e18;
        _genesisValues[GRADIENT_CEILING_KEY] = 10e18;
        _genesisValues[GRADIENT_FLOOR_KEY] = 1e18;
        _genesisValues[LEVY_RATE_KEY] = 500;
        _genesisValues[MIN_AUDIT_STAKE_KEY] = 100e18;
        _genesisValues[DECAY_PERIOD_KEY] = 50400;
        _genesisValues[PANEL_SIZE_KEY] = 7;
        _genesisValues[SUPERMAJORITY_THRESHOLD_KEY] = 6667;
        _genesisValues[EMERGENCY_DURATION_KEY] = 7200;
        _genesisValues[AUDIT_REVIEW_WINDOW_KEY] = 604800;
        _genesisValues[BOUNTY_MULTIPLIER_KEY] = 20000;
    }

    function _getWithFallback(bytes32 key) internal view returns (uint256) {
        try registry.getMetric(key) returns (uint256 value) {
            return value;
        } catch {
            return _genesisValues[key];
        }
    }

    function basketCost() external view returns (uint256) {
        return _getWithFallback(BASKET_COST_KEY);
    }

    function gradientCeiling() external view returns (uint256) {
        return _getWithFallback(GRADIENT_CEILING_KEY);
    }

    function gradientFloor() external view returns (uint256) {
        return _getWithFallback(GRADIENT_FLOOR_KEY);
    }

    function levyRate() external view returns (uint256) {
        return _getWithFallback(LEVY_RATE_KEY);
    }

    function minAuditStake() external view returns (uint256) {
        return _getWithFallback(MIN_AUDIT_STAKE_KEY);
    }

    function poolBudget(uint8 tier) external view returns (uint256) {
        bytes32 key = keccak256(abi.encode("POOL_BUDGET", tier));
        return _getWithFallback(key);
    }

    function decayPeriod() external view returns (uint256) {
        return _getWithFallback(DECAY_PERIOD_KEY);
    }

    function panelSize() external view returns (uint256) {
        return _getWithFallback(PANEL_SIZE_KEY);
    }

    function supermajorityThreshold() external view returns (uint256) {
        return _getWithFallback(SUPERMAJORITY_THRESHOLD_KEY);
    }

    function emergencyDuration() external view returns (uint256) {
        return _getWithFallback(EMERGENCY_DURATION_KEY);
    }

    function auditReviewWindow() external view returns (uint256) {
        return _getWithFallback(AUDIT_REVIEW_WINDOW_KEY);
    }

    function bountyMultiplier() external view returns (uint256) {
        return _getWithFallback(BOUNTY_MULTIPLIER_KEY);
    }
}
