// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Sortition} from "../../src/governance/Sortition.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";
import {MockPersonhood, MockBeacon, MockParameterStore, MockTreasury} from "../mocks/Mocks.sol";

contract SortitionTest is Test {
    Sortition public sortition;
    MockPersonhood public personhood;
    MockBeacon public beacon;
    MockParameterStore public paramStore;
    MockTreasury public treasury;

    uint256 constant PANEL_SIZE = 5;
    uint256 constant NUM_PERSONS = 10;

    bytes32[] internal _personIds;
    address[] internal _personAddrs;
    mapping(bytes32 => address) internal _addrOf;

    function setUp() public {
        personhood = new MockPersonhood();
        beacon = new MockBeacon();
        paramStore = new MockParameterStore();
        treasury = new MockTreasury();

        sortition = new Sortition(
            address(personhood), address(beacon), address(paramStore), address(treasury)
        );

        _personIds = new bytes32[](NUM_PERSONS);
        _personAddrs = new address[](NUM_PERSONS);

        for (uint256 i = 0; i < NUM_PERSONS; i++) {
            address addr = address(uint160(i + 100));
            bytes32 pid = bytes32(uint256(uint160(addr)));
            _personIds[i] = pid;
            _personAddrs[i] = addr;
            _addrOf[pid] = addr;

            personhood.addPerson(pid);
            vm.prank(addr);
            sortition.registerForSortition(pid);
        }
    }

    function _drawPanel(bytes32 purpose, uint256 size) internal returns (uint256) {
        return sortition.drawPanel(purpose, size);
    }

    function _voteAll(uint256 panelId, bool approve) internal {
        ISortition.Panel memory panel = sortition.getPanel(panelId);
        for (uint256 i = 0; i < panel.members.length; i++) {
            address addr = _addrOf[panel.members[i]];
            vm.prank(addr);
            sortition.vote(panelId, panel.members[i], approve);
        }
    }

    function _votePartial(uint256 panelId, uint256 forCount, uint256 againstCount) internal {
        ISortition.Panel memory panel = sortition.getPanel(panelId);
        uint256 voted = 0;
        for (uint256 i = 0; i < forCount && voted < panel.members.length; i++) {
            vm.prank(_addrOf[panel.members[voted]]);
            sortition.vote(panelId, panel.members[voted], true);
            voted++;
        }
        for (uint256 i = 0; i < againstCount && voted < panel.members.length; i++) {
            vm.prank(_addrOf[panel.members[voted]]);
            sortition.vote(panelId, panel.members[voted], false);
            voted++;
        }
    }

    // ── Registration ──

    function testRegisterForSortition() public {
        assertEq(sortition.registeredCount(), NUM_PERSONS);
    }

    function testRegisterRevertsIfNotVerified() public {
        address caller = address(uint160(999));
        bytes32 fakePerson = bytes32(uint256(uint160(caller)));
        vm.prank(caller);
        vm.expectRevert(Sortition.NotVerifiedPerson.selector);
        sortition.registerForSortition(fakePerson);
    }

    function testRegisterRevertsIfAlreadyRegistered() public {
        vm.prank(_personAddrs[0]);
        vm.expectRevert(Sortition.AlreadyRegistered.selector);
        sortition.registerForSortition(_personIds[0]);
    }

    // ── Panel Drawing ──

    function testDrawPanel() public {
        uint256 panelId = _drawPanel(bytes32("test"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        assertEq(panel.members.length, PANEL_SIZE);
        assertEq(panel.purpose, bytes32("test"));
        assertTrue(panel.state == ISortition.PanelState.Active);
        assertEq(panel.votesFor, 0);
        assertEq(panel.votesAgainst, 0);
        assertEq(sortition.panelCount(), 1);
    }

    function testDrawPanelMembersAreUnique() public {
        uint256 panelId = _drawPanel(bytes32("test"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < panel.members.length; i++) {
            for (uint256 j = i + 1; j < panel.members.length; j++) {
                assertTrue(panel.members[i] != panel.members[j]);
            }
        }
    }

    function testDrawPanelMembersAreVerified() public {
        uint256 panelId = _drawPanel(bytes32("test"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < panel.members.length; i++) {
            assertTrue(personhood.isUniquePerson(panel.members[i]));
        }
    }

    function testDrawPanelFundsRoles() public {
        _drawPanel(bytes32("test"), PANEL_SIZE);
        assertEq(treasury.rolesFunded(), PANEL_SIZE);
    }

    function testDrawPanelRevertsIfSizeZero() public {
        vm.expectRevert(Sortition.PanelSizeZero.selector);
        sortition.drawPanel(bytes32("test"), 0);
    }

    function testDrawPanelRevertsIfNotEnoughPersons() public {
        vm.expectRevert(
            abi.encodeWithSelector(Sortition.NotEnoughRegisteredPersons.selector, 20, NUM_PERSONS)
        );
        sortition.drawPanel(bytes32("test"), 20);
    }

    // ── Voting ──

    function testVoteAndResolveWithSupermajority() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        uint256 forCount = 4;
        uint256 againstCount = 1;
        _votePartial(panelId, forCount, againstCount);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertTrue(resolved);
        assertTrue(approved);
    }

    function testVoteResolveWithoutSupermajority() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);

        uint256 forCount = 3;
        uint256 againstCount = 2;
        _votePartial(panelId, forCount, againstCount);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertTrue(resolved);
        assertFalse(approved);
    }

    function testDuplicateVoteReverts() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        bytes32 member = panel.members[0];
        address addr = _addrOf[member];

        vm.prank(addr);
        sortition.vote(panelId, member, true);

        vm.prank(addr);
        vm.expectRevert(abi.encodeWithSelector(Sortition.AlreadyVoted.selector, panelId, member));
        sortition.vote(panelId, member, true);
    }

    function testVoteByNonMemberReverts() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        bytes32 fakeMember = bytes32(uint256(999));

        vm.expectRevert(
            abi.encodeWithSelector(Sortition.NotPanelMember.selector, panelId, fakeMember)
        );
        sortition.vote(panelId, fakeMember, true);
    }

    function testVoteByWrongAddressReverts() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 member = panel.members[0];

        address wrongAddr = address(0xDEAD);
        vm.prank(wrongAddr);
        vm.expectRevert(Sortition.NotAuthorized.selector);
        sortition.vote(panelId, member, true);
    }

    function testHasVoted() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 member = panel.members[0];

        assertFalse(sortition.hasVoted(panelId, member));

        vm.prank(_addrOf[member]);
        sortition.vote(panelId, member, true);

        assertTrue(sortition.hasVoted(panelId, member));
    }

    // ── Expiry ──

    function testVoteAfterExpiryReverts() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        vm.roll(panel.expiresAt);

        bytes32 member = panel.members[0];
        vm.prank(_addrOf[member]);
        vm.expectRevert(abi.encodeWithSelector(Sortition.PanelNotActive.selector, panelId));
        sortition.vote(panelId, member, true);
    }

    function testExpirePanel() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        vm.roll(panel.expiresAt);
        sortition.expirePanel(panelId);

        ISortition.Panel memory expired = sortition.getPanel(panelId);
        assertTrue(expired.state == ISortition.PanelState.Expired);
    }

    function testExpirePanelRevertsBeforeExpiry() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        vm.expectRevert(abi.encodeWithSelector(Sortition.PanelNotExpired.selector, panelId));
        sortition.expirePanel(panelId);
    }

    function testExpiredPanelIsNotResolved() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        vm.roll(panel.expiresAt);
        sortition.expirePanel(panelId);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertFalse(resolved);
        assertFalse(approved);
    }

    // ── Kill Switch ──

    function testKillSwitchWorks() public {
        uint256 panelId = _drawPanel(bytes32("gov"), 9);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(_addrOf[panel.members[i]]);
            sortition.vote(panelId, panel.members[i], false);
        }

        sortition.killSwitch(panelId);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertTrue(resolved);
        assertFalse(approved);
    }

    function testKillSwitchFailsUnderThreshold() public {
        uint256 panelId = _drawPanel(bytes32("gov"), 9);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < 2; i++) {
            vm.prank(_addrOf[panel.members[i]]);
            sortition.vote(panelId, panel.members[i], false);
        }

        vm.expectRevert(abi.encodeWithSelector(Sortition.NotEnoughVotesForKill.selector, panelId));
        sortition.killSwitch(panelId);
    }

    function testKillSwitchAt33PercentFires() public {
        uint256 panelId = _drawPanel(bytes32("gov"), 9);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(_addrOf[panel.members[i]]);
            sortition.vote(panelId, panel.members[i], false);
        }

        sortition.killSwitch(panelId);

        (bool resolved,) = sortition.isResolved(panelId);
        assertTrue(resolved);
    }

    function testKillSwitchPreventsVoting() public {
        uint256 panelId = _drawPanel(bytes32("gov"), 9);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(_addrOf[panel.members[i]]);
            sortition.vote(panelId, panel.members[i], false);
        }
        sortition.killSwitch(panelId);

        vm.prank(_addrOf[panel.members[4]]);
        vm.expectRevert(abi.encodeWithSelector(Sortition.PanelNotActive.selector, panelId));
        sortition.vote(panelId, panel.members[4], true);
    }

    // ── Invariants ──

    function testInvariantNoTokenWeightedGovernance() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        for (uint256 i = 0; i < panel.members.length; i++) {
            vm.deal(_addrOf[panel.members[i]], (i + 1) * 100 ether);
        }

        _voteAll(panelId, true);

        ISortition.Panel memory resolved = sortition.getPanel(panelId);
        assertEq(resolved.votesFor, panel.members.length);
        assertEq(resolved.votesAgainst, 0);
    }

    function testInvariantOnePersonOneVote() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        bytes32 member = panel.members[0];
        vm.prank(_addrOf[member]);
        sortition.vote(panelId, member, true);

        vm.prank(_addrOf[member]);
        vm.expectRevert();
        sortition.vote(panelId, member, false);
    }

    function testInvariantPanelExpiresAfterTimer() public {
        uint256 duration = paramStore.emergencyDuration();
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        ISortition.Panel memory panel = sortition.getPanel(panelId);

        assertEq(panel.expiresAt, panel.createdAt + duration);

        vm.roll(panel.expiresAt);
        bytes32 member = panel.members[0];
        vm.prank(_addrOf[member]);
        vm.expectRevert();
        sortition.vote(panelId, member, true);
    }

    // ── Identity Hijacking Prevention (C-4) ──

    function testRegisterRevertsIfSenderDoesNotMatchPersonId() public {
        address attacker = address(uint160(500));
        address victim = address(uint160(501));
        bytes32 victimId = bytes32(uint256(uint160(victim)));
        personhood.addPerson(victimId);

        vm.prank(attacker);
        vm.expectRevert(Sortition.NotAuthorized.selector);
        sortition.registerForSortition(victimId);
    }

    // ── Two-Phase Panel Draw (C-1) ──

    function testRequestAndFinalizePanel() public {
        uint256 panelId = sortition.requestPanel(bytes32("test"), PANEL_SIZE);
        ISortition.Panel memory pending = sortition.getPanel(panelId);
        assertTrue(pending.state == ISortition.PanelState.PendingDraw);
        assertEq(pending.members.length, 0);

        sortition.finalizePanel(panelId);
        ISortition.Panel memory active = sortition.getPanel(panelId);
        assertTrue(active.state == ISortition.PanelState.Active);
        assertEq(active.members.length, PANEL_SIZE);
    }

    function testFinalizePanelRevertsIfNotPendingDraw() public {
        uint256 panelId = _drawPanel(bytes32("test"), PANEL_SIZE);
        vm.expectRevert(abi.encodeWithSelector(Sortition.PanelNotPendingDraw.selector, panelId));
        sortition.finalizePanel(panelId);
    }

    // ── Stored Approval (C-5) ──

    function testIsResolvedReturnsStoredApproval() public {
        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        _votePartial(panelId, 4, 1);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertTrue(resolved);
        assertTrue(approved);

        paramStore.setSupermajorityThreshold(9999);

        (bool resolved2, bool approved2) = sortition.isResolved(panelId);
        assertTrue(resolved2);
        assertTrue(approved2);
    }

    function testSupermajorityBoundary() public {
        paramStore.setSupermajorityThreshold(6667);

        uint256 panelId = _drawPanel(bytes32("gov"), PANEL_SIZE);
        _votePartial(panelId, 3, 2);

        (, bool approved) = sortition.isResolved(panelId);
        assertFalse(approved);

        uint256 panelId2 = _drawPanel(bytes32("gov2"), PANEL_SIZE);
        _votePartial(panelId2, 4, 1);

        (, bool approved2) = sortition.isResolved(panelId2);
        assertTrue(approved2);
    }
}
