// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MetricRegistry} from "../../src/metric/MetricRegistry.sol";
import {IMetricRegistry} from "../../src/interfaces/IMetricRegistry.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";

contract MockSortition {
    mapping(uint256 => bool) internal _resolved;
    mapping(uint256 => bool) internal _approved;
    mapping(uint256 => bytes32) internal _purposes;

    function mockPanel(uint256 panelId, bool resolved, bool approved) external {
        _resolved[panelId] = resolved;
        _approved[panelId] = approved;
    }

    function mockPurpose(uint256 panelId, bytes32 purpose) external {
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
}

contract MockAudit {
    uint256 public constant MOCK_MIN_STAKE = 100e18;
    uint256 public claimCounter;

    bytes32 public lastTarget;
    bytes32 public lastEvidenceHash;
    uint256 public lastStakeAmount;

    function minStake() external pure returns (uint256) {
        return MOCK_MIN_STAKE;
    }

    function fileClaim(bytes32 target, bytes32 evidenceHash, uint256 stakeAmount) external returns (uint256) {
        lastTarget = target;
        lastEvidenceHash = evidenceHash;
        lastStakeAmount = stakeAmount;
        claimCounter++;
        return claimCounter;
    }
}

contract MetricRegistryTest is Test {
    MetricRegistry public registry;
    MockSortition public sortition;
    MockAudit public audit;

    uint256 constant DECAY_PERIOD = 1000;
    uint256 constant PANEL_ID = 1;

    bytes32 constant KEY = keccak256("TEST_METRIC");
    bytes32 constant ORACLE = keccak256("ORACLE_1");
    uint256 constant VALUE = 42e18;

    function setUp() public {
        sortition = new MockSortition();
        audit = new MockAudit();
        registry = new MetricRegistry(address(sortition), address(audit), DECAY_PERIOD);
    }

    function _approvePanel(uint256 panelId) internal {
        sortition.mockPanel(panelId, true, true);
    }

    function _approvePanelForPurpose(uint256 panelId, bytes32 purpose) internal {
        sortition.mockPanel(panelId, true, true);
        sortition.mockPurpose(panelId, purpose);
    }

    function _rejectPanel(uint256 panelId) internal {
        sortition.mockPanel(panelId, true, false);
    }

    function _pendingPanel(uint256 panelId) internal {
        sortition.mockPanel(panelId, false, false);
    }

    function _proposeAndCreateMetric(bytes32 key, uint256 value, bytes32 oracleSource, uint256 panelId) internal {
        bytes32 proposalHash = keccak256(abi.encode("create", key, value, oracleSource));
        _approvePanelForPurpose(panelId, proposalHash);
        registry.proposeCreate(key, value, oracleSource, panelId);
        registry.createMetric(key, value, oracleSource);
    }

    // ── createMetric ──

    function test_createMetric_succeeds() public {
        bytes32 proposalHash = keccak256(abi.encode("create", KEY, VALUE, ORACLE));
        _approvePanelForPurpose(PANEL_ID, proposalHash);
        registry.proposeCreate(KEY, VALUE, ORACLE, PANEL_ID);
        registry.createMetric(KEY, VALUE, ORACLE);

        uint256 result = registry.getMetric(KEY);
        assertEq(result, VALUE);

        IMetricRegistry.Metric memory m = registry.getMetricRecord(KEY);
        assertEq(m.key, KEY);
        assertEq(m.value, VALUE);
        assertEq(m.oracleSource, ORACLE);
        assertEq(m.decayDeadline, block.number + DECAY_PERIOD);
        assertEq(m.lastUpdated, block.number);
    }

    function test_createMetric_reverts_without_proposal() public {
        vm.expectRevert();
        registry.createMetric(KEY, VALUE, ORACLE);
    }

    function test_createMetric_reverts_panel_not_resolved() public {
        _pendingPanel(PANEL_ID);
        registry.proposeCreate(KEY, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.PanelNotResolved.selector, PANEL_ID));
        registry.createMetric(KEY, VALUE, ORACLE);
    }

    function test_createMetric_reverts_panel_not_approved() public {
        _rejectPanel(PANEL_ID);
        registry.proposeCreate(KEY, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.PanelNotApproved.selector, PANEL_ID));
        registry.createMetric(KEY, VALUE, ORACLE);
    }

    function test_createMetric_reverts_already_exists() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("create", KEY, VALUE, ORACLE));
        _approvePanelForPurpose(panel2, proposalHash);
        registry.proposeCreate(KEY, VALUE, ORACLE, panel2);

        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricAlreadyExists.selector, KEY));
        registry.createMetric(KEY, VALUE, ORACLE);
    }

    // ── getMetric ──

    function test_getMetric_returns_value() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);
        assertEq(registry.getMetric(KEY), VALUE);
    }

    function test_getMetric_reverts_expired() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        vm.roll(block.number + DECAY_PERIOD + 1);

        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricExpiredError.selector, KEY));
        registry.getMetric(KEY);
    }

    function test_getMetric_reverts_not_found() public {
        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricNotFound.selector, KEY));
        registry.getMetric(KEY);
    }

    // ── updateMetric ──

    function test_updateMetric_succeeds() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        uint256 newValue = 99e18;
        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("update", KEY, newValue));
        _approvePanelForPurpose(panel2, proposalHash);
        registry.proposeUpdate(KEY, newValue, panel2);

        vm.roll(block.number + 10);
        uint256 updateBlock = block.number;
        registry.updateMetric(KEY, newValue);

        assertEq(registry.getMetric(KEY), newValue);

        IMetricRegistry.Metric memory m = registry.getMetricRecord(KEY);
        assertEq(m.value, newValue);
        assertEq(m.lastUpdated, updateBlock);
        assertEq(m.decayDeadline, updateBlock + DECAY_PERIOD);
    }

    function test_updateMetric_reverts_without_sortition() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert();
        registry.updateMetric(KEY, 99e18);
    }

    function test_updateMetric_reverts_not_found() public {
        uint256 newValue = 99e18;
        _approvePanel(PANEL_ID);
        registry.proposeUpdate(KEY, newValue, PANEL_ID);

        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricNotFound.selector, KEY));
        registry.updateMetric(KEY, newValue);
    }

    // ── reratify ──

    function test_reratify_resets_decay_timer() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        uint256 originalDeadline = registry.getMetricRecord(KEY).decayDeadline;

        vm.roll(block.number + DECAY_PERIOD - 10);
        uint256 reratifyBlock = block.number;

        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("reratify", KEY));
        _approvePanelForPurpose(panel2, proposalHash);
        registry.proposeReratify(KEY, panel2);
        registry.reratify(KEY);

        IMetricRegistry.Metric memory m = registry.getMetricRecord(KEY);
        uint256 newDeadline = reratifyBlock + DECAY_PERIOD;
        assertEq(m.decayDeadline, newDeadline);
        assertGt(newDeadline, originalDeadline);
        assertEq(m.lastUpdated, reratifyBlock);
    }

    function test_reratify_reverts_without_sortition() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert();
        registry.reratify(KEY);
    }

    function test_reratify_makes_expired_metric_readable_again() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        vm.roll(block.number + DECAY_PERIOD + 1);
        assertTrue(registry.isExpired(KEY));

        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("reratify", KEY));
        _approvePanelForPurpose(panel2, proposalHash);
        registry.proposeReratify(KEY, panel2);
        registry.reratify(KEY);

        assertFalse(registry.isExpired(KEY));
        assertEq(registry.getMetric(KEY), VALUE);
    }

    // ── isExpired ──

    function test_isExpired_returns_false_before_deadline() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);
        assertFalse(registry.isExpired(KEY));
    }

    function test_isExpired_returns_true_after_deadline() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);
        vm.roll(block.number + DECAY_PERIOD + 1);
        assertTrue(registry.isExpired(KEY));
    }

    // ── fileDivergenceClaim ──

    function test_fileDivergenceClaim_routes_to_audit() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        bytes32 evidence = keccak256("evidence_data");
        registry.fileDivergenceClaim(KEY, evidence);

        assertEq(audit.lastTarget(), KEY);
        assertEq(audit.lastEvidenceHash(), evidence);
        assertEq(audit.lastStakeAmount(), audit.MOCK_MIN_STAKE());
        assertEq(audit.claimCounter(), 1);
    }

    function test_fileDivergenceClaim_reverts_not_found() public {
        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricNotFound.selector, KEY));
        registry.fileDivergenceClaim(KEY, keccak256("evidence"));
    }

    // ── Full lifecycle ──

    function test_metric_lifecycle_create_read_update_expire_reratify() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);
        assertEq(registry.getMetric(KEY), VALUE);

        uint256 newValue = 100e18;
        uint256 panel2 = 2;
        bytes32 updateHash = keccak256(abi.encode("update", KEY, newValue));
        _approvePanelForPurpose(panel2, updateHash);
        registry.proposeUpdate(KEY, newValue, panel2);
        registry.updateMetric(KEY, newValue);
        assertEq(registry.getMetric(KEY), newValue);

        vm.roll(block.number + DECAY_PERIOD + 1);
        assertTrue(registry.isExpired(KEY));
        vm.expectRevert(abi.encodeWithSelector(MetricRegistry.MetricExpiredError.selector, KEY));
        registry.getMetric(KEY);

        uint256 panel3 = 3;
        bytes32 reratifyHash = keccak256(abi.encode("reratify", KEY));
        _approvePanelForPurpose(panel3, reratifyHash);
        registry.proposeReratify(KEY, panel3);
        registry.reratify(KEY);

        assertFalse(registry.isExpired(KEY));
        assertEq(registry.getMetric(KEY), newValue);
    }

    // ── Proposal consumed after use ──

    function test_proposal_consumed_after_execution() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        bytes32 key2 = keccak256("SECOND");
        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("create", key2, VALUE, ORACLE));
        _approvePanelForPurpose(panel2, proposalHash);
        registry.proposeCreate(key2, VALUE, ORACLE, panel2);
        registry.createMetric(key2, VALUE, ORACLE);

        vm.expectRevert();
        registry.createMetric(key2, VALUE, ORACLE);
    }

    // ── Panel purpose verification ──

    function test_consumeProposal_reverts_wrong_purpose() public {
        sortition.mockPanel(PANEL_ID, true, true);
        sortition.mockPurpose(PANEL_ID, keccak256("WRONG_PURPOSE"));
        registry.proposeCreate(KEY, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert(MetricRegistry.WrongPanelPurpose.selector);
        registry.createMetric(KEY, VALUE, ORACLE);
    }

    function test_consumeProposal_reverts_reused_panel_different_proposal() public {
        _proposeAndCreateMetric(KEY, VALUE, ORACLE, PANEL_ID);

        bytes32 key2 = keccak256("SECOND");
        registry.proposeCreate(key2, VALUE, ORACLE, PANEL_ID);

        vm.expectRevert(MetricRegistry.WrongPanelPurpose.selector);
        registry.createMetric(key2, VALUE, ORACLE);
    }
}
