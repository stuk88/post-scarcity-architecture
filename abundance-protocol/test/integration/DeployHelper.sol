// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockPersonhood, MockBeacon} from "../mocks/Mocks.sol";
import {MetricRegistry} from "../../src/metric/MetricRegistry.sol";
import {ParameterStore} from "../../src/metric/ParameterStore.sol";
import {Reputation} from "../../src/protocol/Reputation.sol";
import {Sortition} from "../../src/governance/Sortition.sol";
import {BaseAllocation} from "../../src/protocol/BaseAllocation.sol";
import {Treasury} from "../../src/protocol/Treasury.sol";
import {Credit} from "../../src/protocol/Credit.sol";
import {Audit} from "../../src/protocol/Audit.sol";
import {Levy} from "../../src/protocol/Levy.sol";
import {Raffle} from "../../src/protocol/Raffle.sol";
import {CompletionRegistry} from "../../src/protocol/CompletionRegistry.sol";
import {Emergency} from "../../src/governance/Emergency.sol";
import {CappedGradient} from "../../src/protocol/CappedGradient.sol";
import {DecayCycle} from "../../src/governance/DecayCycle.sol";

abstract contract DeployHelper is Test {
    MockPersonhood personhood;
    MockBeacon beacon;
    MetricRegistry metricRegistry;
    ParameterStore parameterStore;
    Reputation reputation;
    Sortition sortition;
    BaseAllocation baseAllocation;
    Treasury treasury;
    Credit credit;
    Audit audit;
    Levy levy;
    Raffle raffle;
    CompletionRegistry completionRegistry;
    Emergency emergency;
    CappedGradient cappedGradient;
    DecayCycle decayCycle;

    uint256 constant BASKET_COST = 1e18;
    uint256 constant GRADIENT_CEILING = 10e18;
    uint256 constant GRADIENT_FLOOR = 1e18;
    uint256 constant LEVY_RATE = 500;
    uint256 constant MIN_AUDIT_STAKE = 100e18;
    uint256 constant DECAY_PERIOD_VALUE = 100_000;
    uint256 constant SUPERMAJORITY = 6667;
    uint256 constant EMERGENCY_DURATION_VAL = 100;
    uint256 constant AUDIT_REVIEW_WINDOW = 7200;
    uint256 constant POOL_BUDGET_MICRO = 500e18;
    uint256 constant METRIC_VALIDITY = 10_000_000;

    struct PrecomputedAddrs {
        address personhood;
        address beacon;
        address metricRegistry;
        address paramStore;
        address reputation;
        address sortition;
        address baseAlloc;
        address treasury;
        address credit;
        address audit;
        address levy;
        address raffle;
        address completion;
        address emergency;
        address gradient;
        address decayCycle;
    }

    PrecomputedAddrs private _pre;

    function _deployProtocol() internal {
        _computeAddresses();
        _deployContracts();
        _verifyAddresses();

        reputation.authorize(address(audit));
        reputation.authorize(address(completionRegistry));
    }

    function _computeAddresses() private {
        address d = address(this);
        uint256 n = vm.getNonce(d);
        _pre.personhood     = vm.computeCreateAddress(d, n);
        _pre.beacon         = vm.computeCreateAddress(d, n + 1);
        _pre.metricRegistry = vm.computeCreateAddress(d, n + 2);
        _pre.paramStore     = vm.computeCreateAddress(d, n + 3);
        _pre.reputation     = vm.computeCreateAddress(d, n + 4);
        _pre.sortition      = vm.computeCreateAddress(d, n + 5);
        _pre.baseAlloc      = vm.computeCreateAddress(d, n + 6);
        _pre.treasury       = vm.computeCreateAddress(d, n + 7);
        _pre.credit         = vm.computeCreateAddress(d, n + 8);
        _pre.audit          = vm.computeCreateAddress(d, n + 9);
        _pre.levy           = vm.computeCreateAddress(d, n + 10);
        _pre.raffle         = vm.computeCreateAddress(d, n + 11);
        _pre.completion     = vm.computeCreateAddress(d, n + 12);
        _pre.emergency      = vm.computeCreateAddress(d, n + 13);
        _pre.gradient       = vm.computeCreateAddress(d, n + 14);
        _pre.decayCycle     = vm.computeCreateAddress(d, n + 15);
    }

    function _deployContracts() private {
        personhood     = new MockPersonhood();
        beacon         = new MockBeacon();
        metricRegistry = new MetricRegistry(_pre.sortition, _pre.audit, METRIC_VALIDITY);

        _seedAllMetrics(address(metricRegistry));

        parameterStore     = new ParameterStore(address(metricRegistry));
        reputation         = new Reputation(address(this));
        sortition          = new Sortition(
            _pre.personhood, _pre.beacon, _pre.paramStore, _pre.treasury
        );
        baseAllocation     = new BaseAllocation(
            _pre.treasury, _pre.paramStore, _pre.personhood, address(this)
        );
        treasury           = new Treasury(
            _pre.credit, _pre.baseAlloc, _pre.paramStore, _pre.personhood,
            _pre.raffle, _pre.audit, _pre.sortition, _pre.levy,
            _pre.completion, _pre.gradient
        );
        credit             = new Credit(
            _pre.treasury, _pre.levy, _pre.audit, _pre.metricRegistry, 1e18
        );
        audit              = new Audit(
            _pre.credit, _pre.personhood, _pre.treasury,
            _pre.reputation, _pre.paramStore
        );
        levy               = new Levy(
            _pre.credit, _pre.treasury, _pre.paramStore, address(this)
        );
        raffle             = new Raffle(
            _pre.personhood, _pre.paramStore, _pre.beacon,
            _pre.sortition, _pre.credit, _pre.treasury
        );
        completionRegistry = new CompletionRegistry(
            _pre.treasury, _pre.reputation, _pre.personhood,
            _pre.paramStore, address(this)
        );
        emergency      = new Emergency(_pre.sortition, _pre.metricRegistry, _pre.paramStore);
        cappedGradient = new CappedGradient(_pre.paramStore);
        decayCycle     = new DecayCycle(_pre.sortition, _pre.paramStore);
    }

    function _verifyAddresses() private view {
        assertEq(address(personhood),         _pre.personhood,     "personhood addr");
        assertEq(address(beacon),             _pre.beacon,         "beacon addr");
        assertEq(address(metricRegistry),     _pre.metricRegistry, "metricRegistry addr");
        assertEq(address(parameterStore),     _pre.paramStore,     "parameterStore addr");
        assertEq(address(reputation),         _pre.reputation,     "reputation addr");
        assertEq(address(sortition),          _pre.sortition,      "sortition addr");
        assertEq(address(baseAllocation),     _pre.baseAlloc,      "baseAllocation addr");
        assertEq(address(treasury),           _pre.treasury,       "treasury addr");
        assertEq(address(credit),             _pre.credit,         "credit addr");
        assertEq(address(audit),              _pre.audit,          "audit addr");
        assertEq(address(levy),               _pre.levy,           "levy addr");
        assertEq(address(raffle),             _pre.raffle,         "raffle addr");
        assertEq(address(completionRegistry), _pre.completion,     "completionRegistry addr");
        assertEq(address(emergency),          _pre.emergency,      "emergency addr");
        assertEq(address(cappedGradient),     _pre.gradient,       "cappedGradient addr");
        assertEq(address(decayCycle),         _pre.decayCycle,     "decayCycle addr");
    }

    /// @dev Write a Metric struct directly into MetricRegistry storage,
    ///      bypassing the governance-gated createMetric flow.
    ///      Storage layout: slot 0 = mapping(bytes32 => Metric) _metrics
    ///                      slot 1 = mapping(bytes32 => bool) _exists
    function _seedMetric(address registry, bytes32 key, uint256 value) internal {
        bytes32 base = keccak256(abi.encode(key, uint256(0)));
        vm.store(registry, base, key);                                             // Metric.key
        vm.store(registry, bytes32(uint256(base) + 1), bytes32(value));           // Metric.value
        vm.store(registry, bytes32(uint256(base) + 2), bytes32(block.number + METRIC_VALIDITY)); // Metric.decayDeadline
        vm.store(registry, bytes32(uint256(base) + 3), bytes32(block.number));    // Metric.lastUpdated
        vm.store(registry, bytes32(uint256(base) + 4), bytes32(0));               // Metric.oracleSource

        bytes32 existsSlot = keccak256(abi.encode(key, uint256(1)));
        vm.store(registry, existsSlot, bytes32(uint256(1)));
    }

    function _seedAllMetrics(address registry) internal {
        _seedMetric(registry, keccak256("BASKET_COST"),              BASKET_COST);
        _seedMetric(registry, keccak256("GRADIENT_CEILING"),         GRADIENT_CEILING);
        _seedMetric(registry, keccak256("GRADIENT_FLOOR"),           GRADIENT_FLOOR);
        _seedMetric(registry, keccak256("LEVY_RATE"),                LEVY_RATE);
        _seedMetric(registry, keccak256("MIN_AUDIT_STAKE"),          MIN_AUDIT_STAKE);
        _seedMetric(registry, keccak256("DECAY_PERIOD"),             DECAY_PERIOD_VALUE);
        _seedMetric(registry, keccak256("PANEL_SIZE"),               5);
        _seedMetric(registry, keccak256("SUPERMAJORITY_THRESHOLD"),  SUPERMAJORITY);
        _seedMetric(registry, keccak256("EMERGENCY_DURATION"),       EMERGENCY_DURATION_VAL);
        _seedMetric(registry, keccak256("AUDIT_REVIEW_WINDOW"),      AUDIT_REVIEW_WINDOW);
        _seedMetric(registry, keccak256(abi.encode("POOL_BUDGET", uint8(0))), POOL_BUDGET_MICRO);
    }

    function _personId(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
