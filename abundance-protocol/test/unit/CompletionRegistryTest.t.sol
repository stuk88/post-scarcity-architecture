// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompletionRegistry} from "../../src/protocol/CompletionRegistry.sol";
import {ICompletionRegistry} from "../../src/interfaces/ICompletionRegistry.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";
import {IPersonhood} from "../../src/interfaces/IPersonhood.sol";
import {IParameterStore} from "../../src/interfaces/IParameterStore.sol";

contract MockTreasury is ITreasury {
    uint256 public lastBountyClaimId;

    function payBounty(uint256 claimId, uint256) external {
        lastBountyClaimId = claimId;
    }

    function releaseProjectTranche(uint256, bytes32, uint256) external {}
    function streamBaseAllocation(bytes32) external {}
    function fundRafflePool(uint8) external {}
    function fundRole(bytes32, uint256) external {}
    function collectLevy(bytes32, uint256) external {}
    function totalCirculating() external pure returns (uint256) { return 0; }
    function periodLevyCollected() external pure returns (uint256) { return 0; }
    function currentPeriod() external pure returns (uint256) { return 0; }
}

contract MockReputation is IReputation {
    struct Call {
        bytes32 personId;
        bytes32 dimension;
        int256 delta;
    }

    Call[] public calls;

    function updateDimension(bytes32 personId, bytes32 dimension, int256 delta) external {
        calls.push(Call(personId, dimension, delta));
    }

    function callCount() external view returns (uint256) {
        return calls.length;
    }

    function getScore(bytes32) external pure returns (Score memory) {
        return Score(0, 0, 0, 0);
    }

    function getDimension(bytes32, bytes32) external pure returns (uint256) {
        return 0;
    }

    function compositeScore(bytes32) external pure returns (uint256) {
        return 0;
    }
}

contract MockPersonhood is IPersonhood {
    mapping(bytes32 => bool) private _verified;

    function setVerified(bytes32 id, bool verified) external {
        _verified[id] = verified;
    }

    function isUniquePerson(bytes32 id) external view returns (bool) {
        return _verified[id];
    }

    function attestationEpoch(bytes32) external pure returns (uint256) { return 0; }
    function provider(bytes32) external pure returns (address) { return address(0); }
    function isRevoked(bytes32) external pure returns (bool) { return false; }
    function verifiedCount() external pure returns (uint256) { return 0; }
}

contract MockParameterStore is IParameterStore {
    function basketCost() external pure returns (uint256) { return 1e18; }
    function gradientCeiling() external pure returns (uint256) { return 10e18; }
    function gradientFloor() external pure returns (uint256) { return 1e18; }
    function levyRate() external pure returns (uint256) { return 500; }
    function minAuditStake() external pure returns (uint256) { return 100e18; }
    function poolBudget(uint8) external pure returns (uint256) { return 1000e18; }
    function decayPeriod() external pure returns (uint256) { return 100; }
    function panelSize() external pure returns (uint256) { return 3; }
    function supermajorityThreshold() external pure returns (uint256) { return 6667; }
    function emergencyDuration() external pure returns (uint256) { return 1000; }
    function auditReviewWindow() external pure returns (uint256) { return 30 days; }
    function bountyMultiplier() external pure returns (uint256) { return 20000; }
}

contract CompletionRegistryTest is Test {
    CompletionRegistry public registry;
    MockTreasury public treasury;
    MockReputation public reputation;
    MockPersonhood public personhood;
    MockParameterStore public parameterStore;

    address public governance = makeAddr("governance");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public constant ORG_A = keccak256("orgA");
    bytes32 public constant ORG_B = keccak256("orgB");
    bytes32 public constant EVIDENCE = keccak256("evidence");

    function setUp() public {
        treasury = new MockTreasury();
        reputation = new MockReputation();
        personhood = new MockPersonhood();
        parameterStore = new MockParameterStore();

        registry = new CompletionRegistry(
            address(treasury),
            address(reputation),
            address(personhood),
            address(parameterStore),
            governance
        );
    }

    function test_registerProject_createsRecord() public {
        vm.prank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 5);

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(p.orgId, ORG_A);
        assertEq(p.proposalId, 1);
        assertEq(p.budget, 1000e18);
        assertEq(p.milestonesTotal, 5);
        assertEq(p.milestonesCompleted, 0);
        assertEq(uint8(p.outcome), uint8(ICompletionRegistry.Outcome.InProgress));
        assertEq(p.budgetSpent, 0);
        assertEq(registry.projectCount(), 1);
    }

    function test_registerProject_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert("CompletionRegistry: caller is not governance");
        registry.registerProject(ORG_A, 1, 1000e18, 5);
    }

    function test_registerProject_revertsOnZeroOrgId() public {
        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: zero orgId");
        registry.registerProject(bytes32(0), 1, 1000e18, 5);
    }

    function test_registerProject_revertsOnZeroMilestones() public {
        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: zero milestones");
        registry.registerProject(ORG_A, 1, 1000e18, 0);
    }

    function test_registerProject_revertsOnZeroBudget() public {
        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: zero budget");
        registry.registerProject(ORG_A, 1, 0, 5);
    }

    function test_registerProject_revertsOnBannedOrg() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Fraudulent);

        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: org is banned");
        registry.registerProject(ORG_A, 2, 1000e18, 5);
    }

    function test_registerProject_revertsOnCooldownOrg() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Abandoned);

        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: org is in cooldown");
        registry.registerProject(ORG_A, 2, 1000e18, 5);
    }

    function test_registerProject_soulbound_noTransferFunction() public {
        vm.prank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 5);

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(p.orgId, ORG_A);
    }

    function test_completeMilestone_incrementsCount() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 3);
        registry.completeMilestone(0, EVIDENCE);
        vm.stopPrank();

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(p.milestonesCompleted, 1);
    }

    function test_completeMilestone_revertsOnNonexistentProject() public {
        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: project does not exist");
        registry.completeMilestone(999, EVIDENCE);
    }

    function test_completeMilestone_revertsOnFinalizedProject() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Delivered);

        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: project not in progress");
        registry.completeMilestone(0, EVIDENCE);
    }

    function test_completeMilestone_revertsOnZeroEvidence() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 3);
        vm.expectRevert("CompletionRegistry: zero evidence hash");
        registry.completeMilestone(0, bytes32(0));
        vm.stopPrank();
    }

    function test_completeMilestone_revertsWhenAllCompleted() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 2);
        registry.completeMilestone(0, EVIDENCE);
        registry.completeMilestone(0, keccak256("ev2"));
        vm.expectRevert("CompletionRegistry: all milestones completed");
        registry.completeMilestone(0, keccak256("ev3"));
        vm.stopPrank();
    }

    function test_releaseTranche_calculatesCorrectAmount() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 4);
        registry.completeMilestone(0, EVIDENCE);
        registry.releaseTranche(0, 0);
        vm.stopPrank();

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(p.budgetSpent, 250e18);
    }

    function test_releaseTranche_revertsOnUncompletedMilestone() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 4);
        vm.expectRevert("CompletionRegistry: milestone not completed");
        registry.releaseTranche(0, 0);
        vm.stopPrank();
    }

    function test_releaseTranche_revertsOnDoubleRelease() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 4);
        registry.completeMilestone(0, EVIDENCE);
        registry.releaseTranche(0, 0);
        vm.expectRevert("CompletionRegistry: tranche already released");
        registry.releaseTranche(0, 0);
        vm.stopPrank();
    }

    function test_finalizeOutcome_delivered_updatesReputation() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Delivered);

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(uint8(p.outcome), uint8(ICompletionRegistry.Outcome.Delivered));
        assertTrue(p.finalizedAt > 0);

        assertEq(reputation.callCount(), 2);
        (bytes32 pid, bytes32 dim, int256 delta) = reputation.calls(0);
        assertEq(pid, ORG_A);
        assertEq(dim, "reliability");
        assertEq(delta, int256(10));
    }

    function test_finalizeOutcome_honestFailure_noPenalty() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.HonestFailure);

        ICompletionRegistry.Project memory p = registry.getProject(0);
        assertEq(uint8(p.outcome), uint8(ICompletionRegistry.Outcome.HonestFailure));
        assertEq(reputation.callCount(), 0);

        assertFalse(registry.isBanned(ORG_A));
        assertFalse(registry.isInCooldown(ORG_A));
    }

    function test_finalizeOutcome_honestFailure_preservesFutureEligibility() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.HonestFailure);

        vm.prank(governance);
        registry.registerProject(ORG_A, 2, 500e18, 3);

        ICompletionRegistry.Project memory p2 = registry.getProject(1);
        assertEq(p2.orgId, ORG_A);
    }

    function test_finalizeOutcome_abandoned_appliesCooldown() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Abandoned);

        assertTrue(registry.isInCooldown(ORG_A));
        assertFalse(registry.isBanned(ORG_A));
    }

    function test_finalizeOutcome_abandoned_cooldownExpires() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Abandoned);

        vm.warp(block.timestamp + 181 days);
        assertFalse(registry.isInCooldown(ORG_A));

        vm.prank(governance);
        registry.registerProject(ORG_A, 2, 500e18, 3);
        assertEq(registry.projectCount(), 2);
    }

    function test_finalizeOutcome_fraudulent_permanentBan() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Fraudulent);

        assertTrue(registry.isBanned(ORG_A));

        vm.warp(block.timestamp + 10000 days);
        assertTrue(registry.isBanned(ORG_A));
    }

    function test_finalizeOutcome_revertsOnDoubleFinalization() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 3);
        registry.finalizeOutcome(0, ICompletionRegistry.Outcome.Delivered);
        vm.expectRevert("CompletionRegistry: already finalized");
        registry.finalizeOutcome(0, ICompletionRegistry.Outcome.Abandoned);
        vm.stopPrank();
    }

    function test_finalizeOutcome_revertsOnInProgress() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 3);
        vm.expectRevert("CompletionRegistry: cannot finalize as InProgress");
        registry.finalizeOutcome(0, ICompletionRegistry.Outcome.InProgress);
        vm.stopPrank();
    }

    function test_multipleProjects_independentTracking() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 1000e18, 3);
        registry.registerProject(ORG_B, 2, 2000e18, 5);
        vm.stopPrank();

        assertEq(registry.projectCount(), 2);

        ICompletionRegistry.Project memory p0 = registry.getProject(0);
        ICompletionRegistry.Project memory p1 = registry.getProject(1);

        assertEq(p0.orgId, ORG_A);
        assertEq(p1.orgId, ORG_B);
        assertEq(p0.budget, 1000e18);
        assertEq(p1.budget, 2000e18);
    }

    function test_returnUnspentBudget_calculatesCorrectly() public {
        vm.startPrank(governance);
        registry.registerProject(ORG_A, 1, 300e18, 3);
        registry.completeMilestone(0, EVIDENCE);
        registry.releaseTranche(0, 0);
        registry.finalizeOutcome(0, ICompletionRegistry.Outcome.Abandoned);
        vm.stopPrank();

        uint256 unspent = registry.returnUnspentBudget(0);
        assertEq(unspent, 200e18);
    }

    // ── Abandonment Auto-Ban ──

    function _abandonNTimes(bytes32 orgId, uint256 n) internal {
        vm.startPrank(governance);
        uint256 base = registry.projectCount();
        for (uint256 i = 0; i < n; i++) {
            registry.registerProject(orgId, base + i + 1, 1000e18, 3);
            registry.finalizeOutcome(base + i, ICompletionRegistry.Outcome.Abandoned);
            if (i < n - 1) {
                vm.warp(block.timestamp + 181 days);
            }
        }
        vm.stopPrank();
    }

    function test_abandoned_threeTimesResultsInBan() public {
        uint256 repBefore = reputation.callCount();
        _abandonNTimes(ORG_A, 3);

        assertTrue(registry.isBanned(ORG_A), "org should be banned after 3 abandonments");
        assertEq(registry.abandonmentCount(ORG_A), 3);
        assertEq(reputation.callCount(), repBefore + 3, "3 reputation hits for 3 abandonments");
    }

    function test_abandoned_twoTimesNotBanned() public {
        uint256 repBefore = reputation.callCount();
        _abandonNTimes(ORG_A, 2);

        assertFalse(registry.isBanned(ORG_A), "org should NOT be banned after 2 abandonments");
        assertTrue(registry.isInCooldown(ORG_A), "second cooldown still active");
        assertEq(registry.abandonmentCount(ORG_A), 2);
        assertEq(reputation.callCount(), repBefore + 2, "2 reputation hits for 2 abandonments");

        vm.warp(block.timestamp + 181 days);
        assertFalse(registry.isInCooldown(ORG_A), "second cooldown expired");
    }

    function test_abandoned_thirdBanBlocksRegistration() public {
        _abandonNTimes(ORG_A, 3);

        vm.prank(governance);
        vm.expectRevert("CompletionRegistry: org is banned");
        registry.registerProject(ORG_A, 99, 1000e18, 3);
    }

    function test_abandoned_countIsolatedPerOrg() public {
        _abandonNTimes(ORG_A, 2);
        vm.warp(block.timestamp + 181 days);

        _abandonNTimes(ORG_B, 1);

        assertEq(registry.abandonmentCount(ORG_A), 2);
        assertEq(registry.abandonmentCount(ORG_B), 1);
        assertFalse(registry.isBanned(ORG_A), "ORG_A not banned at 2");
        assertFalse(registry.isBanned(ORG_B), "ORG_B not banned at 1");
    }

    function test_abandoned_cooldownBoundaryExact180Days() public {
        _registerAndFinalize(ORG_A, ICompletionRegistry.Outcome.Abandoned);

        vm.warp(block.timestamp + 180 days - 1);
        assertTrue(registry.isInCooldown(ORG_A), "still in cooldown 1s before expiry");

        vm.warp(block.timestamp + 1);
        assertFalse(registry.isInCooldown(ORG_A), "cooldown expired at exactly 180 days");
    }

    function _registerAndFinalize(bytes32 orgId, ICompletionRegistry.Outcome outcome) internal {
        vm.startPrank(governance);
        registry.registerProject(orgId, 1, 1000e18, 3);
        registry.finalizeOutcome(registry.projectCount() - 1, outcome);
        vm.stopPrank();
    }
}
