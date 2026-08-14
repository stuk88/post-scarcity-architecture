// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {DecayCycle} from "../../src/governance/DecayCycle.sol";
import {IDecayCycle} from "../../src/interfaces/IDecayCycle.sol";
import {MockSortition, MockParameterStore} from "../mocks/Mocks.sol";

contract DecayCycleTest is Test {
    DecayCycle public cycle;
    MockSortition public mockSortition;
    MockParameterStore public paramStore;

    uint256 constant DECAY_PERIOD = 1000;
    address constant NEW_PROTOCOL = address(0xBEEF);

    function setUp() public {
        mockSortition = new MockSortition();
        paramStore = new MockParameterStore();
        paramStore.setDecayPeriod(DECAY_PERIOD);

        cycle = new DecayCycle(address(mockSortition), address(paramStore));
    }

    function _openReview() internal {
        vm.roll(block.number + DECAY_PERIOD);
        cycle.openReviewWindow();
    }

    function _setupApprovedPanel(uint256 panelId, bytes32 purpose) internal {
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, purpose);
    }

    function _setupRejectedPanel(uint256 panelId, bytes32 purpose) internal {
        mockSortition.setResolution(panelId, true, false);
        mockSortition.setPurpose(panelId, purpose);
    }

    function _approveMigration(uint256 approvalPanelId) internal {
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), NEW_PROTOCOL));
        _setupApprovedPanel(approvalPanelId, purpose);
        cycle.approveMigration(approvalPanelId, NEW_PROTOCOL);
    }

    function _setupConfirmationPanel(uint256 confirmPanelId, uint256 cycleNum) internal {
        bytes32 purpose = keccak256(abi.encode("confirmMigration", cycleNum, NEW_PROTOCOL));
        _setupApprovedPanel(confirmPanelId, purpose);
    }

    // ── Constructor Validation ──

    function testConstructorRevertsZeroSortition() public {
        paramStore = new MockParameterStore();
        paramStore.setDecayPeriod(DECAY_PERIOD);
        vm.expectRevert(DecayCycle.ZeroAddress.selector);
        new DecayCycle(address(0), address(paramStore));
    }

    function testConstructorRevertsZeroParams() public {
        mockSortition = new MockSortition();
        vm.expectRevert(DecayCycle.ZeroAddress.selector);
        new DecayCycle(address(mockSortition), address(0));
    }

    // ── Initial State ──

    function testInitialState() public view {
        assertEq(cycle.currentCycle(), 0);
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.Normal);
        assertEq(cycle.reviewWindowBlock(), DECAY_PERIOD + 1);
        assertFalse(cycle.pendingMigration());
        assertEq(cycle.approvedNewProtocol(), address(0));
    }

    // ── Open Review Window ──

    function testOpenReviewWindow() public {
        vm.roll(block.number + DECAY_PERIOD);
        cycle.openReviewWindow();
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.ReviewWindow);
    }

    function testOpenReviewWindowRevertsBeforeTimer() public {
        vm.expectRevert(DecayCycle.CycleNotExpired.selector);
        cycle.openReviewWindow();
    }

    function testOpenReviewWindowRevertsInWrongPhase() public {
        _openReview();
        vm.expectRevert(
            abi.encodeWithSelector(
                DecayCycle.NotInPhase.selector,
                IDecayCycle.CyclePhase.Normal,
                IDecayCycle.CyclePhase.ReviewWindow
            )
        );
        cycle.openReviewWindow();
    }

    function testOpenReviewWindowAnyoneCanCall() public {
        vm.roll(block.number + DECAY_PERIOD);
        vm.prank(address(0xCAFE));
        cycle.openReviewWindow();
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.ReviewWindow);
    }

    // ── Approve Migration ──

    function testApproveMigration() public {
        _openReview();

        uint256 panelId = 1;
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), NEW_PROTOCOL));
        _setupApprovedPanel(panelId, purpose);

        cycle.approveMigration(panelId, NEW_PROTOCOL);

        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.Migration);
        assertTrue(cycle.pendingMigration());
        assertEq(cycle.approvedNewProtocol(), NEW_PROTOCOL);
    }

    function testApproveMigrationRevertsOnZeroAddress() public {
        _openReview();

        uint256 panelId = 1;
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), address(0)));
        _setupApprovedPanel(panelId, purpose);

        vm.expectRevert(DecayCycle.ZeroProtocolAddress.selector);
        cycle.approveMigration(panelId, address(0));
    }

    function testApproveMigrationRevertsWithoutSupermajority() public {
        _openReview();

        uint256 panelId = 1;
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), NEW_PROTOCOL));
        _setupRejectedPanel(panelId, purpose);

        vm.expectRevert(abi.encodeWithSelector(DecayCycle.PanelNotApproved.selector, panelId));
        cycle.approveMigration(panelId, NEW_PROTOCOL);
    }

    function testApproveMigrationRevertsWrongPurpose() public {
        _openReview();

        uint256 panelId = 1;
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, bytes32("wrong"));

        vm.expectRevert(DecayCycle.WrongPanelPurpose.selector);
        cycle.approveMigration(panelId, NEW_PROTOCOL);
    }

    function testApproveMigrationRevertsInNormalPhase() public {
        uint256 panelId = 1;
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), NEW_PROTOCOL));
        _setupApprovedPanel(panelId, purpose);

        vm.expectRevert(
            abi.encodeWithSelector(
                DecayCycle.NotInPhase.selector,
                IDecayCycle.CyclePhase.ReviewWindow,
                IDecayCycle.CyclePhase.Normal
            )
        );
        cycle.approveMigration(panelId, NEW_PROTOCOL);
    }

    // ── Execute Migration ──

    function testExecuteMigration() public {
        _openReview();

        uint256 approvalPanel = 1;
        _approveMigration(approvalPanel);

        uint256 confirmPanel = 2;
        _setupConfirmationPanel(confirmPanel, 0);

        cycle.executeMigration(confirmPanel);

        assertEq(cycle.currentCycle(), 1);
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.Normal);
        assertFalse(cycle.pendingMigration());
        assertEq(cycle.approvedNewProtocol(), address(0));
    }

    function testExecuteMigrationRevertsSamePanelAsApproval() public {
        _openReview();

        uint256 approvalPanel = 1;
        _approveMigration(approvalPanel);

        vm.expectRevert(
            abi.encodeWithSelector(DecayCycle.SamePanelAsApproval.selector, approvalPanel)
        );
        cycle.executeMigration(approvalPanel);
    }

    function testExecuteMigrationRevertsWrongPurpose() public {
        _openReview();

        uint256 approvalPanel = 1;
        _approveMigration(approvalPanel);

        uint256 wrongPanel = 2;
        mockSortition.setResolution(wrongPanel, true, true);
        mockSortition.setPurpose(wrongPanel, bytes32("wrong"));

        vm.expectRevert(DecayCycle.WrongPanelPurpose.selector);
        cycle.executeMigration(wrongPanel);
    }

    function testExecuteMigrationRevertsNotApproved() public {
        _openReview();

        uint256 approvalPanel = 1;
        _approveMigration(approvalPanel);

        uint256 confirmPanel = 2;
        bytes32 purpose = keccak256(abi.encode("confirmMigration", uint256(0), NEW_PROTOCOL));
        mockSortition.setResolution(confirmPanel, true, false);
        mockSortition.setPurpose(confirmPanel, purpose);

        vm.expectRevert(abi.encodeWithSelector(DecayCycle.PanelNotApproved.selector, confirmPanel));
        cycle.executeMigration(confirmPanel);
    }

    function testExecuteMigrationRevertsInWrongPhase() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DecayCycle.NotInPhase.selector,
                IDecayCycle.CyclePhase.Migration,
                IDecayCycle.CyclePhase.Normal
            )
        );
        cycle.executeMigration(1);
    }

    // ── Renew Cycle ──

    function testRenewCycle() public {
        _openReview();

        uint256 panelId = 5;
        bytes32 purpose = keccak256(abi.encode("renewCycle", uint256(0)));
        _setupApprovedPanel(panelId, purpose);

        cycle.renewCycle(panelId);

        assertEq(cycle.currentCycle(), 1);
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.Normal);
        assertEq(cycle.reviewWindowBlock(), block.number + DECAY_PERIOD);
    }

    function testRenewCycleRevertsWithoutSupermajority() public {
        _openReview();

        uint256 panelId = 5;
        bytes32 purpose = keccak256(abi.encode("renewCycle", uint256(0)));
        _setupRejectedPanel(panelId, purpose);

        vm.expectRevert(abi.encodeWithSelector(DecayCycle.PanelNotApproved.selector, panelId));
        cycle.renewCycle(panelId);
    }

    function testRenewCycleRevertsWrongPurpose() public {
        _openReview();

        uint256 panelId = 5;
        mockSortition.setResolution(panelId, true, true);
        mockSortition.setPurpose(panelId, bytes32("wrong"));

        vm.expectRevert(DecayCycle.WrongPanelPurpose.selector);
        cycle.renewCycle(panelId);
    }

    function testRenewCycleRevertsInNormalPhase() public {
        uint256 panelId = 5;
        bytes32 purpose = keccak256(abi.encode("renewCycle", uint256(0)));
        _setupApprovedPanel(panelId, purpose);

        vm.expectRevert(
            abi.encodeWithSelector(
                DecayCycle.NotInPhase.selector,
                IDecayCycle.CyclePhase.ReviewWindow,
                IDecayCycle.CyclePhase.Normal
            )
        );
        cycle.renewCycle(panelId);
    }

    // ── Multi-Cycle ──

    function testMultipleCycleRenewals() public {
        for (uint256 c = 0; c < 3; c++) {
            vm.roll(cycle.reviewWindowBlock());
            cycle.openReviewWindow();

            uint256 panelId = 100 + c;
            bytes32 purpose = keccak256(abi.encode("renewCycle", c));
            _setupApprovedPanel(panelId, purpose);
            cycle.renewCycle(panelId);

            assertEq(cycle.currentCycle(), c + 1);
            assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.Normal);
        }
    }

    // ── Invariants ──

    function testInvariantReviewWindowOnlyAfterTimer() public {
        vm.roll(cycle.reviewWindowBlock() - 1);
        vm.expectRevert(DecayCycle.CycleNotExpired.selector);
        cycle.openReviewWindow();

        vm.roll(cycle.reviewWindowBlock());
        cycle.openReviewWindow();
        assertTrue(cycle.currentPhase() == IDecayCycle.CyclePhase.ReviewWindow);
    }

    function testInvariantMigrationRequiresSupermajority() public {
        _openReview();

        uint256 panelId = 1;
        bytes32 purpose = keccak256(abi.encode("migration", uint256(0), NEW_PROTOCOL));

        mockSortition.setResolution(panelId, false, false);
        mockSortition.setPurpose(panelId, purpose);
        vm.expectRevert(abi.encodeWithSelector(DecayCycle.PanelNotApproved.selector, panelId));
        cycle.approveMigration(panelId, NEW_PROTOCOL);

        mockSortition.setResolution(panelId, true, false);
        vm.expectRevert(abi.encodeWithSelector(DecayCycle.PanelNotApproved.selector, panelId));
        cycle.approveMigration(panelId, NEW_PROTOCOL);

        mockSortition.setResolution(panelId, true, true);
        cycle.approveMigration(panelId, NEW_PROTOCOL);
        assertTrue(cycle.pendingMigration());
    }

    function testInvariantNewCycleResetsTimer() public {
        _openReview();

        uint256 panelId = 5;
        bytes32 purpose = keccak256(abi.encode("renewCycle", uint256(0)));
        _setupApprovedPanel(panelId, purpose);
        cycle.renewCycle(panelId);

        uint256 newReviewBlock = cycle.reviewWindowBlock();
        assertEq(newReviewBlock, block.number + DECAY_PERIOD);

        vm.roll(newReviewBlock - 1);
        vm.expectRevert(DecayCycle.CycleNotExpired.selector);
        cycle.openReviewWindow();
    }

    function testInvariantExecutionRequiresSeparatePanel() public {
        _openReview();

        uint256 approvalPanel = 1;
        _approveMigration(approvalPanel);

        vm.expectRevert(
            abi.encodeWithSelector(DecayCycle.SamePanelAsApproval.selector, approvalPanel)
        );
        cycle.executeMigration(approvalPanel);

        uint256 confirmPanel = 2;
        _setupConfirmationPanel(confirmPanel, 0);
        cycle.executeMigration(confirmPanel);
        assertEq(cycle.currentCycle(), 1);
    }
}
