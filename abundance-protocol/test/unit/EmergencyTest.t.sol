// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Emergency} from "../../src/governance/Emergency.sol";
import {IEmergency} from "../../src/interfaces/IEmergency.sol";
import {MockSortition, MockMetricRegistry, MockParameterStore} from "../mocks/Mocks.sol";

contract EmergencyTest is Test {
    Emergency public emergency;
    MockSortition public mockSortition;
    MockMetricRegistry public mockMetrics;
    MockParameterStore public paramStore;

    bytes32 constant TRIGGER_ID = bytes32("trigger1");
    bytes32 constant METRIC_KEY = bytes32("inflation_rate");
    uint256 constant THRESHOLD = 500;
    bytes32 constant RESPONSE_ACTION = bytes32("pause_minting");
    uint256 constant DURATION = 50;

    function setUp() public {
        mockSortition = new MockSortition();
        mockMetrics = new MockMetricRegistry();
        paramStore = new MockParameterStore();

        emergency = new Emergency(address(mockSortition), address(mockMetrics), address(paramStore));

        emergency.registerTrigger(TRIGGER_ID, METRIC_KEY, THRESHOLD, RESPONSE_ACTION, DURATION);
        emergency.finalizeSetup();
    }

    function _activateTrigger() internal {
        mockMetrics.setMetric(METRIC_KEY, THRESHOLD);
        emergency.activate(TRIGGER_ID);
    }

    // ── Registration ──

    function testRegisterTrigger() public {
        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertEq(t.triggerId, TRIGGER_ID);
        assertEq(t.metricKey, METRIC_KEY);
        assertEq(t.threshold, THRESHOLD);
        assertEq(t.responseAction, RESPONSE_ACTION);
        assertEq(t.duration, DURATION);
        assertTrue(t.state == IEmergency.TriggerState.Inactive);
    }

    function testRegisterRevertsAfterFinalize() public {
        vm.expectRevert(Emergency.AlreadyInitialized.selector);
        emergency.registerTrigger(bytes32("t2"), METRIC_KEY, 100, RESPONSE_ACTION, 10);
    }

    function testFinalizeRevertsIfAlreadyFinalized() public {
        vm.expectRevert(Emergency.AlreadyInitialized.selector);
        emergency.finalizeSetup();
    }

    // ── Deployer ACL ──

    function testRegisterTriggerRevertsForNonDeployer() public {
        Emergency fresh = new Emergency(address(mockSortition), address(mockMetrics), address(paramStore));

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(Emergency.NotDeployer.selector);
        fresh.registerTrigger(bytes32("t"), METRIC_KEY, 100, RESPONSE_ACTION, 10);
    }

    function testFinalizeSetupRevertsForNonDeployer() public {
        Emergency fresh = new Emergency(address(mockSortition), address(mockMetrics), address(paramStore));

        vm.prank(makeAddr("attacker"));
        vm.expectRevert(Emergency.NotDeployer.selector);
        fresh.finalizeSetup();
    }

    // ── Activation ──

    function testActivate() public {
        mockMetrics.setMetric(METRIC_KEY, THRESHOLD);
        emergency.activate(TRIGGER_ID);

        assertTrue(emergency.isActive(TRIGGER_ID));
        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertTrue(t.state == IEmergency.TriggerState.Active);
        assertEq(t.activatedAt, block.number);
    }

    function testActivateRevertsUnderThreshold() public {
        mockMetrics.setMetric(METRIC_KEY, THRESHOLD - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Emergency.ThresholdNotCrossed.selector, TRIGGER_ID, THRESHOLD - 1, THRESHOLD
            )
        );
        emergency.activate(TRIGGER_ID);
    }

    function testActivateRevertsIfAlreadyActive() public {
        _activateTrigger();
        vm.expectRevert(abi.encodeWithSelector(Emergency.TriggerNotInactive.selector, TRIGGER_ID));
        emergency.activate(TRIGGER_ID);
    }

    function testActivateRevertsIfTriggerNotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(Emergency.TriggerNotFound.selector, bytes32("nonexistent"))
        );
        emergency.activate(bytes32("nonexistent"));
    }

    // ── Expiry ──

    function testCheckExpiry() public {
        _activateTrigger();
        vm.roll(block.number + DURATION);
        emergency.checkExpiry(TRIGGER_ID);

        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertTrue(t.state == IEmergency.TriggerState.Expired);
    }

    function testCheckExpiryRevertsBeforeDuration() public {
        _activateTrigger();
        vm.roll(block.number + DURATION - 1);
        vm.expectRevert(abi.encodeWithSelector(Emergency.TriggerNotExpired.selector, TRIGGER_ID));
        emergency.checkExpiry(TRIGGER_ID);
    }

    function testIsActiveReturnsFalseAfterDuration() public {
        _activateTrigger();
        assertTrue(emergency.isActive(TRIGGER_ID));

        vm.roll(block.number + DURATION);
        assertFalse(emergency.isActive(TRIGGER_ID));
    }

    function testIsActiveReturnsFalseWithoutCheckExpiry() public {
        _activateTrigger();
        vm.roll(block.number + DURATION + 100);
        assertFalse(emergency.isActive(TRIGGER_ID));
    }

    // ── Renew ──

    function testRenew() public {
        _activateTrigger();
        uint256 activationBlock = block.number;

        uint256 panelId = 42;
        bytes32 purpose = keccak256(abi.encode("emergency.renew", TRIGGER_ID));
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, purpose);

        vm.roll(activationBlock + DURATION / 2);
        emergency.renew(TRIGGER_ID, panelId);

        assertTrue(emergency.isActive(TRIGGER_ID));
        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertEq(t.activatedAt, block.number);
    }

    function testRenewRevertsWithoutSupermajority() public {
        _activateTrigger();

        uint256 panelId = 42;
        mockSortition.setResolution(panelId, true, false);
        mockSortition.setPurpose(
            panelId, keccak256(abi.encode("emergency.renew", TRIGGER_ID))
        );

        vm.expectRevert(abi.encodeWithSelector(Emergency.PanelNotApproved.selector, panelId));
        emergency.renew(TRIGGER_ID, panelId);
    }

    function testRenewRevertsWithWrongPurpose() public {
        _activateTrigger();

        uint256 panelId = 42;
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, bytes32("wrong_purpose"));

        vm.expectRevert(Emergency.WrongPanelPurpose.selector);
        emergency.renew(TRIGGER_ID, panelId);
    }

    function testRenewRevertsPanelReuse() public {
        _activateTrigger();

        uint256 panelId = 42;
        bytes32 purpose = keccak256(abi.encode("emergency.renew", TRIGGER_ID));
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, purpose);

        emergency.renew(TRIGGER_ID, panelId);

        vm.expectRevert(
            abi.encodeWithSelector(Emergency.PanelAlreadyUsed.selector, TRIGGER_ID, panelId)
        );
        emergency.renew(TRIGGER_ID, panelId);
    }

    // ── Terminate Early ──

    function testTerminateEarly() public {
        _activateTrigger();

        uint256 panelId = 99;
        bytes32 purpose = keccak256(abi.encode("emergency.terminate", TRIGGER_ID));
        mockSortition.setResolution(panelId, true, false);
        mockSortition.setPurpose(panelId, purpose);

        emergency.terminateEarly(TRIGGER_ID, panelId);

        assertFalse(emergency.isActive(TRIGGER_ID));
        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertTrue(t.state == IEmergency.TriggerState.Inactive);
    }

    function testTerminateEarlyRevertsIfPanelApproved() public {
        _activateTrigger();

        uint256 panelId = 99;
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(
            panelId, keccak256(abi.encode("emergency.terminate", TRIGGER_ID))
        );

        vm.expectRevert(abi.encodeWithSelector(Emergency.PanelNotRejected.selector, panelId));
        emergency.terminateEarly(TRIGGER_ID, panelId);
    }

    function testTerminateEarlyRevertsWithWrongPurpose() public {
        _activateTrigger();

        uint256 panelId = 99;
        mockSortition.setResolution(panelId, true, false);
        mockSortition.setPurpose(panelId, bytes32("wrong"));

        vm.expectRevert(Emergency.WrongPanelPurpose.selector);
        emergency.terminateEarly(TRIGGER_ID, panelId);
    }

    // ── Scarcity Breaker ──

    function testActivateScarcityBreaker() public {
        bytes32 goodId = bytes32("wheat");
        uint256 priceChannel = 200;
        uint256 panelId = 500;

        bytes32 purpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, purpose);

        emergency.activateScarcityBreaker(goodId, priceChannel, panelId);
        assertTrue(emergency.isScarcityBreakerActive(goodId));
    }

    function testDeactivateScarcityBreaker() public {
        bytes32 goodId = bytes32("wheat");
        uint256 activatePanelId = 500;
        uint256 deactivatePanelId = 501;

        bytes32 activatePurpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        mockSortition.setResolution(activatePanelId, true, true);
        mockSortition.setPurpose(activatePanelId, activatePurpose);
        emergency.activateScarcityBreaker(goodId, 200, activatePanelId);

        bytes32 deactivatePurpose = keccak256(abi.encode("scarcityBreaker.deactivate", goodId));
        mockSortition.setResolution(deactivatePanelId, true, true);
        mockSortition.setPurpose(deactivatePanelId, deactivatePurpose);

        emergency.deactivateScarcityBreaker(goodId, deactivatePanelId);
        assertFalse(emergency.isScarcityBreakerActive(goodId));
    }

    function testActivateScarcityBreakerRevertsIfAlreadyActive() public {
        bytes32 goodId = bytes32("wheat");
        uint256 panelId1 = 500;
        uint256 panelId2 = 501;

        bytes32 purpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        mockSortition.setResolution(panelId1, true, true);
        mockSortition.setPurpose(panelId1, purpose);
        emergency.activateScarcityBreaker(goodId, 200, panelId1);

        mockSortition.setResolution(panelId2, true, true);
        mockSortition.setPurpose(panelId2, purpose);

        vm.expectRevert(
            abi.encodeWithSelector(Emergency.ScarcityBreakerAlreadyActive.selector, goodId)
        );
        emergency.activateScarcityBreaker(goodId, 300, panelId2);
    }

    function testDeactivateScarcityBreakerRevertsIfNotActive() public {
        bytes32 goodId = bytes32("wheat");
        uint256 panelId = 500;

        bytes32 purpose = keccak256(abi.encode("scarcityBreaker.deactivate", goodId));
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, purpose);

        vm.expectRevert(
            abi.encodeWithSelector(Emergency.ScarcityBreakerNotActive.selector, goodId)
        );
        emergency.deactivateScarcityBreaker(goodId, panelId);
    }

    function testActivateScarcityBreakerRevertsWithoutPanel() public {
        bytes32 goodId = bytes32("wheat");
        uint256 panelId = 500;

        vm.expectRevert(abi.encodeWithSelector(Emergency.PanelNotApproved.selector, panelId));
        emergency.activateScarcityBreaker(goodId, 200, panelId);
    }

    function testActivateScarcityBreakerRevertsWithWrongPurpose() public {
        bytes32 goodId = bytes32("wheat");
        uint256 panelId = 500;

        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, bytes32("wrong"));

        vm.expectRevert(Emergency.WrongPanelPurpose.selector);
        emergency.activateScarcityBreaker(goodId, 200, panelId);
    }

    function testDeactivateScarcityBreakerRevertsWithoutPanel() public {
        bytes32 goodId = bytes32("wheat");

        uint256 activatePanelId = 500;
        bytes32 activatePurpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        mockSortition.setResolution(activatePanelId, true, true);
        mockSortition.setPurpose(activatePanelId, activatePurpose);
        emergency.activateScarcityBreaker(goodId, 200, activatePanelId);

        uint256 deactivatePanelId = 501;

        vm.expectRevert(abi.encodeWithSelector(Emergency.PanelNotApproved.selector, deactivatePanelId));
        emergency.deactivateScarcityBreaker(goodId, deactivatePanelId);
    }

    function testDeactivateScarcityBreakerRevertsWithWrongPurpose() public {
        bytes32 goodId = bytes32("wheat");

        uint256 activatePanelId = 500;
        bytes32 activatePurpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        mockSortition.setResolution(activatePanelId, true, true);
        mockSortition.setPurpose(activatePanelId, activatePurpose);
        emergency.activateScarcityBreaker(goodId, 200, activatePanelId);

        uint256 deactivatePanelId = 501;
        mockSortition.setResolution(deactivatePanelId, true, true);
        mockSortition.setPurpose(deactivatePanelId, bytes32("wrong"));

        vm.expectRevert(Emergency.WrongPanelPurpose.selector);
        emergency.deactivateScarcityBreaker(goodId, deactivatePanelId);
    }

    // ── Invariants ──

    function testInvariantEmergencyAutoExpires() public {
        _activateTrigger();
        assertTrue(emergency.isActive(TRIGGER_ID));

        vm.roll(block.number + DURATION);
        assertFalse(emergency.isActive(TRIGGER_ID));
    }

    function testInvariantEmergencyCannotRewriteProtocol() public {
        _activateTrigger();

        IEmergency.Trigger memory t = emergency.getTrigger(TRIGGER_ID);
        assertTrue(t.state == IEmergency.TriggerState.Active);
        assertEq(t.responseAction, RESPONSE_ACTION);
    }
}
