// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./DeployHelper.sol";
import {IRaffle} from "../../src/interfaces/IRaffle.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";
import {IAudit} from "../../src/interfaces/IAudit.sol";
import {IEmergency} from "../../src/interfaces/IEmergency.sol";
import {ICompletionRegistry} from "../../src/interfaces/ICompletionRegistry.sol";

contract LifecycleTest is DeployHelper {
    function setUp() public {
        _deployProtocol();
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 1: Person Registration -> Base Allocation -> Withdrawal
    // ═══════════════════════════════════════════════════════════════

    function test_BaseAllocationLifecycle() public {
        address alice = makeAddr("alice");
        bytes32 aliceId = _personId(alice);

        personhood.addPerson(aliceId);
        vm.prank(alice);
        baseAllocation.register(aliceId, alice);

        assertTrue(baseAllocation.isActive(aliceId));
        assertEq(baseAllocation.recipientOf(aliceId), alice);

        vm.roll(block.number + 100);

        uint256 accrued = baseAllocation.accrued(aliceId);
        assertEq(accrued, 100 * BASKET_COST, "accrued should equal blocks * basketCost");

        treasury.streamBaseAllocation(aliceId);

        assertEq(credit.balanceOf(alice), 100 * BASKET_COST, "alice should receive minted credits");
        assertEq(credit.totalMinted(), 100 * BASKET_COST, "totalMinted should match");
        assertEq(baseAllocation.accrued(aliceId), 0, "accrued should reset after withdrawal");

        vm.roll(block.number + 50);
        treasury.streamBaseAllocation(aliceId);
        assertEq(credit.balanceOf(alice), 150 * BASKET_COST, "second withdrawal should add to balance");
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 2: Raffle Full Lifecycle
    //   Tests: Raffle submit/close/draw -> CompletionRegistry
    //   Catches: treasury.payBounty access control mismatch when
    //   CompletionRegistry.releaseTranche calls it
    // ═══════════════════════════════════════════════════════════════

    function test_RaffleFullLifecycle() public {
        address[5] memory proposers;
        bytes32[5] memory proposerIds;
        uint256[5] memory amounts = [uint256(80e18), 90e18, 100e18, 110e18, 120e18];

        for (uint256 i = 0; i < 5; i++) {
            proposers[i] = makeAddr(string.concat("proposer", vm.toString(i)));
            proposerIds[i] = _personId(proposers[i]);
            personhood.addPerson(proposerIds[i]);
        }

        uint256[] memory proposalIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            IRaffle.Proposal memory p = IRaffle.Proposal({
                proposerId: proposerIds[i],
                contentHash: keccak256(abi.encode("proposal", i)),
                requestedAmount: amounts[i],
                tier: IRaffle.Tier.Micro,
                milestonesCount: 3,
                submittedAt: 0
            });
            vm.prank(proposers[i]);
            proposalIds[i] = raffle.submit(p);
        }

        assertEq(raffle.entryCount(IRaffle.Tier.Micro), 5, "should have 5 entries");

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        assertEq(
            uint8(raffle.poolState(IRaffle.Tier.Micro)),
            uint8(IRaffle.PoolState.Frozen),
            "pool should be frozen after closeEntries"
        );

        uint256[] memory winnerIds = raffle.draw(IRaffle.Tier.Micro);
        assertTrue(winnerIds.length > 0, "should have at least one winner");
        assertEq(
            uint8(raffle.poolState(IRaffle.Tier.Micro)),
            uint8(IRaffle.PoolState.Drawn),
            "pool should be drawn"
        );

        // Cross-contract boundary: register a winning proposal in CompletionRegistry
        uint256 winnerId = winnerIds[0];
        IRaffle.Proposal memory winner = raffle.getProposal(winnerId);

        completionRegistry.registerProject(
            winner.proposerId,
            winnerId,
            winner.requestedAmount,
            winner.milestonesCount
        );

        ICompletionRegistry.Project memory project = completionRegistry.getProject(0);
        assertEq(uint8(project.outcome), uint8(ICompletionRegistry.Outcome.InProgress));
        assertEq(project.milestonesTotal, winner.milestonesCount);

        completionRegistry.completeMilestone(0, keccak256("milestone_evidence_0"));
        project = completionRegistry.getProject(0);
        assertEq(project.milestonesCompleted, 1);

        // Register winner in BaseAllocation so Treasury can look up a recipient
        address winnerAddr = address(uint160(uint256(winner.proposerId)));
        vm.prank(winnerAddr);
        baseAllocation.register(winner.proposerId, winnerAddr);

        uint256 balBefore = credit.balanceOf(winnerAddr);
        completionRegistry.releaseTranche(0, 0);

        // Tranche = budget / milestonesTotal, clamped by CappedGradient
        uint256 rawTranche = winner.requestedAmount / winner.milestonesCount;
        uint256 expectedMint = rawTranche > GRADIENT_CEILING ? GRADIENT_CEILING : rawTranche;
        assertEq(
            credit.balanceOf(winnerAddr),
            balBefore + expectedMint,
            "winner receives clamped tranche"
        );

        project = completionRegistry.getProject(0);
        assertEq(project.budgetSpent, rawTranche, "budgetSpent tracks raw tranche");
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 3: Audit Lifecycle with Reputation Effects
    //   Tests: Audit -> Credit transfers -> Treasury bounty -> Reputation
    //   Confirmed resolution: stake returned, bounty minted, rep +10
    //   BadFaith resolution: stake burned, rep -20 (floors at 0)
    // ═══════════════════════════════════════════════════════════════

    function test_AuditLifecycleWithReputation() public {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address carol = makeAddr("carol");
        address dave = makeAddr("dave");
        bytes32 aliceId = _personId(alice);

        personhood.addPerson(aliceId);
        personhood.addPerson(_personId(bob));
        personhood.addPerson(_personId(carol));
        personhood.addPerson(_personId(dave));

        vm.prank(alice);
        baseAllocation.register(aliceId, alice);
        vm.roll(block.number + 500);
        treasury.streamBaseAllocation(aliceId);
        uint256 aliceStart = credit.balanceOf(alice);
        assertEq(aliceStart, 500 * BASKET_COST);

        // ── Confirmed claim ──
        {
            vm.prank(alice);
            credit.approve(address(audit), MIN_AUDIT_STAKE);

            vm.prank(alice);
            uint256 claimId = audit.fileClaim(
                keccak256("target1"),
                keccak256("evidence1"),
                MIN_AUDIT_STAKE
            );

            vm.prank(bob);
            audit.review(claimId, true);
            vm.prank(carol);
            audit.review(claimId, true);
            vm.prank(dave);
            audit.review(claimId, false);

            uint256 auditBalBefore = credit.balanceOf(address(audit));
            audit.resolve(claimId);

            assertEq(
                uint8(audit.getClaim(claimId).resolution),
                uint8(IAudit.Resolution.Confirmed)
            );
            assertEq(credit.balanceOf(alice), aliceStart, "stake returned after Confirmed");
            assertEq(
                credit.balanceOf(address(audit)),
                auditBalBefore - MIN_AUDIT_STAKE + GRADIENT_CEILING,
                "audit balance = prior - stake_returned + bounty_minted (clamped)"
            );
            assertEq(reputation.getDimension(aliceId, "accuracy"), 10, "rep +10 accuracy");
        }

        // ── BadFaith claim ──
        {
            vm.prank(alice);
            credit.approve(address(audit), MIN_AUDIT_STAKE);

            vm.prank(alice);
            uint256 claimId2 = audit.fileClaim(
                keccak256("target2"),
                keccak256("evidence2"),
                MIN_AUDIT_STAKE
            );

            vm.prank(bob);
            audit.review(claimId2, false);
            vm.prank(carol);
            audit.review(claimId2, false);
            vm.prank(dave);
            audit.review(claimId2, true);

            vm.prank(bob);
            audit.markBadFaith(claimId2);
            vm.prank(carol);
            audit.markBadFaith(claimId2);

            uint256 burnedBefore = credit.totalBurned();
            audit.resolve(claimId2);

            assertEq(
                uint8(audit.getClaim(claimId2).resolution),
                uint8(IAudit.Resolution.BadFaith)
            );
            assertEq(credit.totalBurned(), burnedBefore + MIN_AUDIT_STAKE, "stake burned");
            assertEq(reputation.getDimension(aliceId, "accuracy"), 0, "rep floors at 0");
            assertEq(
                credit.balanceOf(alice),
                aliceStart - MIN_AUDIT_STAKE,
                "alice loses stake permanently"
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 4: Levy -> Treasury -> Base Allocation Loop
    //   Tests: Levy burns credits -> Treasury records levy ->
    //   base allocation still streams afterwards
    // ═══════════════════════════════════════════════════════════════

    function test_LevyTreasuryBaseAllocationLoop() public {
        address alice = makeAddr("alice");
        bytes32 aliceId = _personId(alice);
        bytes32 orgId = keccak256("test-org");

        personhood.addPerson(aliceId);
        vm.prank(alice);
        baseAllocation.register(aliceId, alice);

        vm.roll(block.number + 1000);
        treasury.streamBaseAllocation(aliceId);
        uint256 preBalance = credit.balanceOf(alice);
        assertEq(preBalance, 1000 * BASKET_COST);

        uint256 settledRevenue = 2000e18;
        uint256 levyAmount = settledRevenue * LEVY_RATE / 10_000;

        vm.prank(alice);
        credit.approve(address(levy), levyAmount);

        uint256 burnedBefore = credit.totalBurned();

        vm.prank(alice);
        levy.collectDigital(orgId, settledRevenue);

        assertEq(credit.totalBurned(), burnedBefore + levyAmount, "levy should burn credits");
        assertEq(credit.balanceOf(alice), preBalance - levyAmount, "alice balance should decrease by levy");

        uint256 expectedTreasuryLevy = settledRevenue * LEVY_RATE / 10_000;
        assertEq(treasury.periodLevyCollected(), expectedTreasuryLevy, "treasury should record levy");

        // The loop: base allocation still works after levy
        vm.roll(block.number + 200);
        treasury.streamBaseAllocation(aliceId);
        assertEq(
            credit.balanceOf(alice),
            preBalance - levyAmount + 200 * BASKET_COST,
            "streaming should continue after levy"
        );
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 5: Emergency Circuit Breaker
    //   Tests: trigger registration -> activation -> expiry
    //   Verifies: no side effects on other protocol contracts
    // ═══════════════════════════════════════════════════════════════

    function test_EmergencyCircuitBreaker() public {
        bytes32 triggerId = keccak256("inflation_trigger");
        bytes32 priceKey = keccak256("PRICE_INDEX");
        uint256 threshold = 1000;
        uint256 triggerDuration = 50;

        _seedMetric(address(metricRegistry), priceKey, 500);

        emergency.registerTrigger(
            triggerId,
            priceKey,
            threshold,
            keccak256("halt_minting"),
            triggerDuration
        );
        emergency.finalizeSetup();

        // Below threshold -> revert
        vm.expectRevert(
            abi.encodeWithSelector(
                Emergency.ThresholdNotCrossed.selector,
                triggerId, 500, threshold
            )
        );
        emergency.activate(triggerId);

        // Push metric above threshold
        _seedMetric(address(metricRegistry), priceKey, 1500);

        uint256 supplyBefore = credit.totalSupply();
        uint256 mintedBefore = credit.totalMinted();

        emergency.activate(triggerId);
        assertTrue(emergency.isActive(triggerId), "trigger should be active");

        // No side effects on other protocol state
        assertEq(credit.totalSupply(), supplyBefore, "credit supply should not change");
        assertEq(credit.totalMinted(), mintedBefore, "credit minted should not change");

        // Advance past trigger duration
        vm.roll(block.number + triggerDuration + 1);

        assertFalse(emergency.isActive(triggerId), "trigger should be inactive after duration");

        emergency.checkExpiry(triggerId);
        IEmergency.Trigger memory t = emergency.getTrigger(triggerId);
        assertEq(uint8(t.state), uint8(IEmergency.TriggerState.Expired));

        // Protocol remains functional after expiry
        address alice = makeAddr("alice_emergency");
        bytes32 aliceId = _personId(alice);
        personhood.addPerson(aliceId);
        vm.prank(alice);
        baseAllocation.register(aliceId, alice);
        vm.roll(block.number + 10);
        treasury.streamBaseAllocation(aliceId);
        assertGt(credit.balanceOf(alice), 0, "protocol should still function after trigger expires");
    }

    // ═══════════════════════════════════════════════════════════════
    // Scenario 6: Sortition Governance -> Metric Update
    //   Tests: full governance flow from panel draw through metric
    //   update to downstream parameter change
    // ═══════════════════════════════════════════════════════════════

    function test_SortitionGovernanceMetricUpdate() public {
        uint256 panelSize = 5;
        uint256 poolSize = 7;

        address[] memory persons = new address[](poolSize);
        bytes32[] memory pIds = new bytes32[](poolSize);

        for (uint256 i = 0; i < poolSize; i++) {
            persons[i] = makeAddr(string.concat("voter", vm.toString(i)));
            pIds[i] = _personId(persons[i]);
            personhood.addPerson(pIds[i]);

            vm.prank(persons[i]);
            baseAllocation.register(pIds[i], persons[i]);

            vm.prank(persons[i]);
            sortition.registerForSortition(pIds[i]);
        }

        assertEq(sortition.registeredCount(), poolSize);
        assertEq(parameterStore.basketCost(), BASKET_COST, "initial basketCost should match");

        bytes32 basketCostKey = keccak256("BASKET_COST");
        uint256 newBasketCost = 2e18;
        bytes32 proposalHash = keccak256(abi.encode("update", basketCostKey, newBasketCost));

        uint256 panelId = sortition.drawPanel(proposalHash, panelSize);

        metricRegistry.proposeUpdate(basketCostKey, newBasketCost, panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        assertEq(panel.members.length, panelSize);
        assertEq(panel.purpose, proposalHash);

        for (uint256 i = 0; i < panel.members.length; i++) {
            address memberAddr = address(uint160(uint256(panel.members[i])));
            vm.prank(memberAddr);
            sortition.vote(panelId, panel.members[i], true);
        }

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        assertTrue(resolved, "panel should be resolved");
        assertTrue(approved, "panel should be approved");

        metricRegistry.updateMetric(basketCostKey, newBasketCost);

        assertEq(parameterStore.basketCost(), newBasketCost, "basketCost should be updated");
        assertEq(metricRegistry.getMetric(basketCostKey), newBasketCost, "metric should be updated");

        // Verify downstream: new accrual rate uses updated basketCost
        address verifier = makeAddr("verifier");
        bytes32 verifierId = _personId(verifier);
        personhood.addPerson(verifierId);
        vm.prank(verifier);
        baseAllocation.register(verifierId, verifier);

        vm.roll(block.number + 50);
        assertEq(baseAllocation.accrued(verifierId), 50 * newBasketCost, "accrual should use new rate");

        treasury.streamBaseAllocation(verifierId);
        assertEq(
            credit.balanceOf(verifier),
            50 * newBasketCost,
            "minted credits should reflect updated basketCost"
        );
    }
}
