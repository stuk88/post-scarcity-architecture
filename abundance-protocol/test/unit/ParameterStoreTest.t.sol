// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ParameterStore} from "../../src/metric/ParameterStore.sol";
import {MetricRegistry} from "../../src/metric/MetricRegistry.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";

contract MockSortitionPS {
    mapping(uint256 => bytes32) internal _purposes;

    function setPurpose(uint256 panelId, bytes32 purpose) external {
        _purposes[panelId] = purpose;
    }

    function isResolved(uint256) external pure returns (bool, bool) {
        return (true, true);
    }

    function getPanel(uint256 panelId) external view returns (ISortition.Panel memory) {
        ISortition.Panel memory p;
        p.panelId = panelId;
        p.purpose = _purposes[panelId];
        p.state = ISortition.PanelState.Resolved;
        return p;
    }
}

contract MockAuditPS {
    function minStake() external pure returns (uint256) {
        return 0;
    }

    function fileClaim(bytes32, bytes32, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract ParameterStoreTest is Test {
    ParameterStore public store;
    MetricRegistry public registry;
    MockSortitionPS public sortition;
    MockAuditPS public audit;

    uint256 constant DECAY_PERIOD = 5000;
    uint256 constant PANEL_ID = 1;

    function setUp() public {
        sortition = new MockSortitionPS();
        audit = new MockAuditPS();
        registry = new MetricRegistry(address(sortition), address(audit), DECAY_PERIOD);
        store = new ParameterStore(address(registry));
    }

    function _createMetric(bytes32 key, uint256 value) internal {
        bytes32 oracleSource = keccak256("oracle");
        bytes32 proposalHash = keccak256(abi.encode("create", key, value, oracleSource));
        sortition.setPurpose(PANEL_ID, proposalHash);
        registry.proposeCreate(key, value, oracleSource, PANEL_ID);
        registry.createMetric(key, value, oracleSource);
    }

    function test_basketCost_delegates() public {
        uint256 expected = 1500e18;
        _createMetric(store.BASKET_COST_KEY(), expected);
        assertEq(store.basketCost(), expected);
    }

    function test_gradientCeiling_delegates() public {
        uint256 expected = 5000e18;
        _createMetric(store.GRADIENT_CEILING_KEY(), expected);
        assertEq(store.gradientCeiling(), expected);
    }

    function test_gradientFloor_delegates() public {
        uint256 expected = 500e18;
        _createMetric(store.GRADIENT_FLOOR_KEY(), expected);
        assertEq(store.gradientFloor(), expected);
    }

    function test_levyRate_delegates() public {
        uint256 expected = 500;
        _createMetric(store.LEVY_RATE_KEY(), expected);
        assertEq(store.levyRate(), expected);
    }

    function test_minAuditStake_delegates() public {
        uint256 expected = 100e18;
        _createMetric(store.MIN_AUDIT_STAKE_KEY(), expected);
        assertEq(store.minAuditStake(), expected);
    }

    function test_poolBudget_delegates() public {
        uint8 tier = 2;
        uint256 expected = 10_000e18;
        bytes32 key = keccak256(abi.encode("POOL_BUDGET", tier));
        _createMetric(key, expected);
        assertEq(store.poolBudget(tier), expected);
    }

    function test_decayPeriod_delegates() public {
        uint256 expected = 7200;
        _createMetric(store.DECAY_PERIOD_KEY(), expected);
        assertEq(store.decayPeriod(), expected);
    }

    function test_panelSize_delegates() public {
        uint256 expected = 15;
        _createMetric(store.PANEL_SIZE_KEY(), expected);
        assertEq(store.panelSize(), expected);
    }

    function test_supermajorityThreshold_delegates() public {
        uint256 expected = 6667;
        _createMetric(store.SUPERMAJORITY_THRESHOLD_KEY(), expected);
        assertEq(store.supermajorityThreshold(), expected);
    }

    function test_emergencyDuration_delegates() public {
        uint256 expected = 50400;
        _createMetric(store.EMERGENCY_DURATION_KEY(), expected);
        assertEq(store.emergencyDuration(), expected);
    }

    // ── Fallback to genesis values ──

    function test_expired_metric_returns_genesis_fallback() public {
        uint256 expected = 1500e18;
        _createMetric(store.BASKET_COST_KEY(), expected);

        vm.roll(block.number + DECAY_PERIOD + 1);

        assertEq(store.basketCost(), 1e18);
    }

    function test_nonexistent_metric_returns_genesis_fallback() public {
        assertEq(store.basketCost(), 1e18);
    }

    function test_genesis_fallback_basketCost() public {
        assertEq(store.basketCost(), 1e18);
    }

    function test_genesis_fallback_gradientCeiling() public {
        assertEq(store.gradientCeiling(), 10e18);
    }

    function test_genesis_fallback_gradientFloor() public {
        assertEq(store.gradientFloor(), 1e18);
    }

    function test_genesis_fallback_levyRate() public {
        assertEq(store.levyRate(), 500);
    }

    function test_genesis_fallback_minAuditStake() public {
        assertEq(store.minAuditStake(), 100e18);
    }

    function test_genesis_fallback_decayPeriod() public {
        assertEq(store.decayPeriod(), 50400);
    }

    function test_genesis_fallback_panelSize() public {
        assertEq(store.panelSize(), 7);
    }

    function test_genesis_fallback_supermajorityThreshold() public {
        assertEq(store.supermajorityThreshold(), 6667);
    }

    function test_genesis_fallback_emergencyDuration() public {
        assertEq(store.emergencyDuration(), 7200);
    }

    function test_genesis_fallback_auditReviewWindow() public {
        assertEq(store.auditReviewWindow(), 604800);
    }

    function test_genesis_fallback_poolBudget_returns_zero() public {
        assertEq(store.poolBudget(1), 0);
    }
}
