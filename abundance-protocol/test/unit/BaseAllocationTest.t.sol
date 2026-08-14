// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseAllocation} from "../../src/protocol/BaseAllocation.sol";
import {IBaseAllocation} from "../../src/interfaces/IBaseAllocation.sol";
import {MockParameterStore, MockPersonhood} from "../mocks/Mocks.sol";

contract BaseAllocationTest is Test {
    BaseAllocation baseAlloc;
    MockParameterStore paramStore;
    MockPersonhood personhood;

    address treasury = makeAddr("treasury");
    address governance = makeAddr("governance");
    address recipient = makeAddr("recipient");
    address alice;
    bytes32 personId;

    uint256 constant RATE = 1e18;

    function setUp() public {
        alice = makeAddr("alice");
        personId = bytes32(uint256(uint160(alice)));

        paramStore = new MockParameterStore();
        paramStore.setBasketCost(RATE);

        personhood = new MockPersonhood();
        personhood.addPerson(personId);

        baseAlloc = new BaseAllocation(treasury, address(paramStore), address(personhood), governance);
    }

    // ── Register ──

    function test_Register() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        assertTrue(baseAlloc.isActive(personId));
        assertEq(baseAlloc.recipientOf(personId), recipient);
    }

    function test_RegisterRevertsNotOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert("BaseAllocation: not owner");
        baseAlloc.register(personId, recipient);
    }

    function test_RegisterRevertsUnverified() public {
        address unverified = makeAddr("unverified");
        bytes32 unverifiedId = bytes32(uint256(uint160(unverified)));
        vm.prank(unverified);
        vm.expectRevert("BaseAllocation: not verified");
        baseAlloc.register(unverifiedId, recipient);
    }

    function test_RegisterRevertsZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert("BaseAllocation: zero recipient");
        baseAlloc.register(personId, address(0));
    }

    function test_RegisterRevertsDuplicate() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(alice);
        vm.expectRevert("BaseAllocation: already registered");
        baseAlloc.register(personId, recipient);
    }

    function test_RegisterEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IBaseAllocation.Registered(personId, recipient);
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
    }

    // ── Accrual ──

    function test_AccrualOverBlocks() public {
        uint256 startBlock = block.number;
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.roll(startBlock + 100);
        uint256 expected = 100 * RATE;
        assertEq(baseAlloc.accrued(personId), expected);
    }

    function test_AccrualZeroWhenNotActive() public view {
        assertEq(baseAlloc.accrued(personId), 0);
    }

    function test_AccrualReflectsRateChange() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
        uint256 startBlock = block.number;

        vm.roll(startBlock + 50);
        assertEq(baseAlloc.accrued(personId), 50 * RATE);

        paramStore.setBasketCost(2e18);
        assertEq(baseAlloc.accrued(personId), 50 * 2e18);
    }

    // ── Withdraw ──

    function test_WithdrawByTreasury() public {
        uint256 startBlock = block.number;
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.roll(startBlock + 100);

        vm.prank(treasury);
        uint256 amount = baseAlloc.withdraw(personId);

        assertEq(amount, 100 * RATE);
        assertEq(baseAlloc.accrued(personId), 0);
    }

    function test_WithdrawRevertsFromNonTreasury() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
        vm.roll(block.number + 10);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert("BaseAllocation: only treasury");
        baseAlloc.withdraw(personId);
    }

    function test_WithdrawRevertsWhenNotActive() public {
        vm.prank(treasury);
        vm.expectRevert("BaseAllocation: not active");
        baseAlloc.withdraw(personId);
    }

    function test_WithdrawResetsAccrual() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
        vm.roll(block.number + 50);

        vm.prank(treasury);
        baseAlloc.withdraw(personId);

        assertEq(baseAlloc.accrued(personId), 0);

        vm.roll(block.number + 25);
        assertEq(baseAlloc.accrued(personId), 25 * RATE);
    }

    function test_WithdrawEmitsEvent() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
        vm.roll(block.number + 10);

        vm.prank(treasury);
        vm.expectEmit(true, true, false, true);
        emit IBaseAllocation.Withdrawn(personId, recipient, 10 * RATE);
        baseAlloc.withdraw(personId);
    }

    // ── Suspend / Resume ──

    function test_Suspend() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);
        assertTrue(baseAlloc.isActive(personId));

        vm.prank(governance);
        baseAlloc.suspend(personId);

        assertFalse(baseAlloc.isActive(personId));
        assertEq(baseAlloc.accrued(personId), 0);
    }

    function test_SuspendRevertsNonGovernance() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(makeAddr("attacker"));
        vm.expectRevert("BaseAllocation: only governance");
        baseAlloc.suspend(personId);
    }

    function test_SuspendRevertsWhenNotActive() public {
        vm.prank(governance);
        vm.expectRevert("BaseAllocation: not active");
        baseAlloc.suspend(personId);
    }

    function test_Resume() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(governance);
        baseAlloc.suspend(personId);
        assertFalse(baseAlloc.isActive(personId));

        vm.prank(governance);
        baseAlloc.resume(personId);
        assertTrue(baseAlloc.isActive(personId));
    }

    function test_ResumeRevertsIfNotSuspended() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(governance);
        vm.expectRevert("BaseAllocation: not suspended");
        baseAlloc.resume(personId);
    }

    function test_ResumeRevertsIfPersonhoodRevoked() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(governance);
        baseAlloc.suspend(personId);

        personhood.removePerson(personId);

        vm.prank(governance);
        vm.expectRevert("BaseAllocation: not verified");
        baseAlloc.resume(personId);
    }

    // ── Soulbound ──

    function test_RecipientCannotChange() public {
        vm.prank(alice);
        baseAlloc.register(personId, recipient);

        vm.prank(alice);
        vm.expectRevert("BaseAllocation: already registered");
        baseAlloc.register(personId, makeAddr("newRecipient"));
    }

    // ── Views ──

    function test_RatePerBlock() public view {
        assertEq(baseAlloc.ratePerBlock(), RATE);
    }

    function test_IsActiveDefaultFalse() public view {
        assertFalse(baseAlloc.isActive(bytes32(uint256(999))));
    }

    function test_RecipientOfDefaultZero() public view {
        assertEq(baseAlloc.recipientOf(bytes32(uint256(999))), address(0));
    }
}
