// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "../../src/protocol/Raffle.sol";
import {IRaffle} from "../../src/interfaces/IRaffle.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";
import {IRandomnessBeacon} from "../../src/interfaces/IRandomnessBeacon.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ── Mocks ──

contract MockPersonhood {
    mapping(bytes32 => bool) public verified;

    function setVerified(bytes32 id, bool v) external {
        verified[id] = v;
    }

    function isUniquePerson(bytes32 id) external view returns (bool) {
        return verified[id];
    }

    function attestationEpoch(bytes32) external pure returns (uint256) { return 1; }
    function provider(bytes32) external pure returns (address) { return address(0); }
    function isRevoked(bytes32) external pure returns (bool) { return false; }
    function verifiedCount() external pure returns (uint256) { return 1; }
}

contract MockParameterStore {
    mapping(uint8 => uint256) public budgets;

    function setPoolBudget(uint8 tier, uint256 budget) external {
        budgets[tier] = budget;
    }

    function poolBudget(uint8 tier) external view returns (uint256) {
        return budgets[tier];
    }

    function basketCost() external pure returns (uint256) { return 1e18; }
    function gradientCeiling() external pure returns (uint256) { return 10e18; }
    function gradientFloor() external pure returns (uint256) { return 1e18; }
    function levyRate() external pure returns (uint256) { return 500; }
    function minAuditStake() external pure returns (uint256) { return 1e18; }
    function decayPeriod() external pure returns (uint256) { return 1000; }
    function panelSize() external pure returns (uint256) { return 7; }
    function supermajorityThreshold() external pure returns (uint256) { return 6667; }
    function emergencyDuration() external pure returns (uint256) { return 1000; }
}

contract MockBeacon {
    uint256 private _nextId = 1;
    mapping(uint256 => uint256) private _seeds;
    mapping(uint256 => bool) private _fulfilled;
    mapping(uint256 => uint256) private _blocks;

    function requestSeed() external returns (uint256 requestId) {
        requestId = _nextId++;
        _blocks[requestId] = block.number;
        emit IRandomnessBeacon.SeedRequested(requestId, msg.sender);
    }

    function fulfillSeed(uint256 requestId, uint256 seed) external {
        _seeds[requestId] = seed;
        _fulfilled[requestId] = true;
        emit IRandomnessBeacon.SeedFulfilled(requestId, seed);
    }

    function getSeed(uint256 requestId) external view returns (uint256) {
        return _seeds[requestId];
    }

    function isFulfilled(uint256 requestId) external view returns (bool) {
        return _fulfilled[requestId];
    }

    function requestBlock(uint256 requestId) external view returns (uint256) {
        return _blocks[requestId];
    }
}

contract MockSortition {
    mapping(uint256 => bool) public panelResolved;
    mapping(uint256 => bool) public panelApproved;
    mapping(uint256 => bytes32) public panelPurpose;

    function setPanel(uint256 panelId, bool resolved, bool approved) external {
        panelResolved[panelId] = resolved;
        panelApproved[panelId] = approved;
    }

    function setPurpose(uint256 panelId, bytes32 purpose) external {
        panelPurpose[panelId] = purpose;
    }

    function isResolved(uint256 panelId) external view returns (bool, bool) {
        return (panelResolved[panelId], panelApproved[panelId]);
    }

    function getPanel(uint256 panelId) external view returns (ISortition.Panel memory) {
        bytes32[] memory members = new bytes32[](0);
        return ISortition.Panel({
            panelId: panelId,
            members: members,
            createdAt: 0,
            expiresAt: 0,
            purpose: panelPurpose[panelId],
            state: ISortition.PanelState.Resolved,
            votesFor: 0,
            votesAgainst: 0
        });
    }

    function hasVoted(uint256, bytes32) external pure returns (bool) { return false; }
    function panelCount() external pure returns (uint256) { return 0; }
}

contract MockCredit is ERC20 {
    constructor() ERC20("Credit", "CRED") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ── Tests ──

contract RaffleTest is Test {
    Raffle public raffle;
    MockPersonhood public personhood;
    MockParameterStore public paramStore;
    MockBeacon public beacon;
    MockSortition public sortition;
    MockCredit public credit;

    address public treasuryAddr = makeAddr("treasury");
    address public alice = makeAddr("alice");

    bytes32 public constant PERSON_A = bytes32(uint256(0xA));
    bytes32 public constant PERSON_B = bytes32(uint256(0xB));
    bytes32 public constant PERSON_C = bytes32(uint256(0xC));
    bytes32 public constant PERSON_D = bytes32(uint256(0xD));
    bytes32 public constant PERSON_E = bytes32(uint256(0xE));

    bytes32 public constant HASH_1 = keccak256("proposal1");
    bytes32 public constant HASH_2 = keccak256("proposal2");
    bytes32 public constant HASH_3 = keccak256("proposal3");
    bytes32 public constant HASH_4 = keccak256("proposal4");
    bytes32 public constant HASH_5 = keccak256("proposal5");

    uint256 internal constant WAD = 1e18;

    uint256 private _nextPanelId = 100;

    function setUp() public {
        personhood = new MockPersonhood();
        paramStore = new MockParameterStore();
        beacon = new MockBeacon();
        sortition = new MockSortition();
        credit = new MockCredit();

        raffle = new Raffle(
            address(personhood),
            address(paramStore),
            address(beacon),
            address(sortition),
            address(credit),
            treasuryAddr
        );

        personhood.setVerified(PERSON_A, true);
        personhood.setVerified(PERSON_B, true);
        personhood.setVerified(PERSON_C, true);
        personhood.setVerified(PERSON_D, true);
        personhood.setVerified(PERSON_E, true);

        paramStore.setPoolBudget(0, 1000e18);
    }

    // ── Helpers ──

    function _makeProposal(bytes32 proposerId, bytes32 contentHash, uint256 amount, IRaffle.Tier tier, uint256 milestones)
        internal
        pure
        returns (IRaffle.Proposal memory)
    {
        return IRaffle.Proposal({
            proposerId: proposerId,
            contentHash: contentHash,
            requestedAmount: amount,
            tier: tier,
            milestonesCount: milestones,
            submittedAt: 0
        });
    }

    function _submitDefault(bytes32 person, bytes32 hash, uint256 amount) internal returns (uint256) {
        vm.prank(address(uint160(uint256(person))));
        return raffle.submit(_makeProposal(person, hash, amount, IRaffle.Tier.Micro, 3));
    }

    function _runFullLifecycle(uint256 seed) internal returns (uint256[] memory) {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        beacon.fulfillSeed(1, seed);

        return raffle.draw(IRaffle.Tier.Micro);
    }

    function _advancePeriod() internal {
        uint256 panelId = _nextPanelId++;
        uint256 period = raffle.currentPeriod();
        bytes32 purpose = keccak256(abi.encode("raffle.advancePeriod", period));
        sortition.setPanel(panelId, true, true);
        sortition.setPurpose(panelId, purpose);
        raffle.advancePeriod(panelId);
    }

    // ── Submission tests ──

    function test_submit_succeeds() public {
        uint256 id = _submitDefault(PERSON_A, HASH_1, 100e18);
        assertEq(id, 1);
        assertEq(raffle.entryCount(IRaffle.Tier.Micro), 1);

        IRaffle.Proposal memory p = raffle.getProposal(id);
        assertEq(p.proposerId, PERSON_A);
        assertEq(p.contentHash, HASH_1);
        assertEq(p.requestedAmount, 100e18);
        assertEq(p.milestonesCount, 3);
    }

    function test_submit_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IRaffle.ProposalSubmitted(1, PERSON_A, IRaffle.Tier.Micro, 100e18);
        _submitDefault(PERSON_A, HASH_1, 100e18);
    }

    function test_submit_revertsIfNotVerified() public {
        personhood.setVerified(PERSON_A, false);
        vm.expectRevert("Raffle: proposer not verified");
        _submitDefault(PERSON_A, HASH_1, 100e18);
    }

    function test_submit_revertsIfZeroContentHash() public {
        vm.prank(address(uint160(uint256(PERSON_A))));
        vm.expectRevert("Raffle: content hash required");
        raffle.submit(_makeProposal(PERSON_A, bytes32(0), 100e18, IRaffle.Tier.Micro, 3));
    }

    function test_submit_revertsIfZeroAmount() public {
        vm.prank(address(uint160(uint256(PERSON_A))));
        vm.expectRevert("Raffle: amount required");
        raffle.submit(_makeProposal(PERSON_A, HASH_1, 0, IRaffle.Tier.Micro, 3));
    }

    function test_submit_revertsIfZeroMilestones() public {
        vm.prank(address(uint160(uint256(PERSON_A))));
        vm.expectRevert("Raffle: milestones required");
        raffle.submit(_makeProposal(PERSON_A, HASH_1, 100e18, IRaffle.Tier.Micro, 0));
    }

    function test_submit_revertsIfNotProposer() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert("Raffle: not proposer");
        raffle.submit(_makeProposal(PERSON_A, HASH_1, 100e18, IRaffle.Tier.Micro, 3));
    }

    // ── INVARIANT 1: No entry accepted after closeEntries() ──

    function test_invariant1_noEntryAfterClose() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        vm.expectRevert("Raffle: pool not open");
        _submitDefault(PERSON_B, HASH_2, 100e18);
    }

    // ── Close entries tests ──

    function test_closeEntries_freezesPool() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(uint8(raffle.poolState(IRaffle.Tier.Micro)), uint8(IRaffle.PoolState.Frozen));
    }

    function test_closeEntries_revertsIfNoEntries() public {
        vm.expectRevert("Raffle: no entries");
        raffle.closeEntries(IRaffle.Tier.Micro);
    }

    function test_closeEntries_revertsIfAlreadyFrozen() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        vm.expectRevert("Raffle: pool not open");
        raffle.closeEntries(IRaffle.Tier.Micro);
    }

    function test_closeEntries_emitsEvent() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 200e18);

        vm.warp(block.timestamp + 86400);
        vm.expectEmit(true, true, false, true);
        emit IRaffle.EntriesClosed(IRaffle.Tier.Micro, 1, 2);
        raffle.closeEntries(IRaffle.Tier.Micro);
    }

    function test_closeEntries_revertsIfSubmissionWindowOpen() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.expectRevert("Raffle: pool still in submission window");
        raffle.closeEntries(IRaffle.Tier.Micro);
    }

    // ── INVARIANT 2: draw() reverts if seed is not yet fulfilled ──

    function test_invariant2_drawRevertsIfSeedNotFulfilled() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        vm.expectRevert("Raffle: seed not fulfilled");
        raffle.draw(IRaffle.Tier.Micro);
    }

    // ── INVARIANT 3: draw() reverts if entries are not frozen ──

    function test_invariant3_drawRevertsIfNotFrozen() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.expectRevert("Raffle: entries not frozen");
        raffle.draw(IRaffle.Tier.Micro);
    }

    function test_invariant3_drawRevertsOnEmptyPool() public {
        vm.expectRevert("Raffle: entries not frozen");
        raffle.draw(IRaffle.Tier.Micro);
    }

    // ── INVARIANT 4: Over-ask weight ──

    function test_invariant4_overAskWeight_2xMedianGetsHalfWeight() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 200e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(raffle.overAskWeight(1), WAD);
        assertEq(raffle.overAskWeight(2), WAD);
        assertEq(raffle.overAskWeight(3), WAD / 2);
    }

    function test_overAskWeight_10xMedianGetsOneTenthWeight() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 1000e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(raffle.overAskWeight(3), WAD / 10);
    }

    function test_overAskWeight_atMedianGetsCappedAt1() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 50e18);
        _submitDefault(PERSON_C, HASH_3, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(raffle.overAskWeight(2), WAD);
    }

    function test_overAskWeight_revertsBeforeFreeze() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.expectRevert("Raffle: pool not frozen yet");
        raffle.overAskWeight(1);
    }

    // ── Draw tests ──

    function test_draw_fullLifecycle() public {
        uint256[] memory winners = _runFullLifecycle(42);

        assertTrue(winners.length > 0);
        assertEq(uint8(raffle.poolState(IRaffle.Tier.Micro)), uint8(IRaffle.PoolState.Drawn));
    }

    function test_draw_emitsEvent() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(1, 42);

        vm.expectEmit(true, true, false, false);
        emit IRaffle.DrawCompleted(IRaffle.Tier.Micro, 1, new uint256[](0), 0);
        raffle.draw(IRaffle.Tier.Micro);
    }

    function test_draw_winnersCountLimitedByEntries() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(1, 42);

        uint256[] memory winners = raffle.draw(IRaffle.Tier.Micro);
        assertLe(winners.length, 2);
    }

    // ── INVARIANT 6: Same seed + same frozen set = same winners (deterministic) ──

    function test_invariant6_deterministic() public {
        uint256 seed = 777;

        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 100e18);
        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(1, seed);
        uint256[] memory winners1 = raffle.draw(IRaffle.Tier.Micro);

        _advancePeriod();

        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 100e18);
        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(2, seed);
        uint256[] memory winners2 = raffle.draw(IRaffle.Tier.Micro);

        assertEq(winners1.length, winners2.length);
        for (uint256 i = 0; i < winners1.length; i++) {
            IRaffle.Proposal memory p1 = raffle.getProposal(winners1[i]);
            IRaffle.Proposal memory p2 = raffle.getProposal(winners2[i]);
            assertEq(p1.requestedAmount, p2.requestedAmount);
            assertEq(p1.proposerId, p2.proposerId);
        }
    }

    // ── INVARIANT 5: Surplus return sends Credit back to the pool ──

    function test_invariant5_surplusReturn() public {
        uint256[] memory winners = _runFullLifecycle(42);
        require(winners.length > 0, "need at least one winner");

        uint256 winnerId = winners[0];

        credit.mint(alice, 50e18);
        vm.prank(alice);
        credit.approve(address(raffle), 50e18);

        uint256 treasuryBefore = credit.balanceOf(treasuryAddr);

        vm.prank(alice);
        raffle.returnSurplus(winnerId, 50e18);

        assertEq(credit.balanceOf(treasuryAddr) - treasuryBefore, 50e18);
        assertEq(credit.balanceOf(alice), 0);
    }

    function test_returnSurplus_emitsEvent() public {
        uint256[] memory winners = _runFullLifecycle(42);
        uint256 winnerId = winners[0];

        credit.mint(alice, 10e18);
        vm.prank(alice);
        credit.approve(address(raffle), 10e18);

        vm.expectEmit(true, false, false, true);
        emit IRaffle.SurplusReturned(winnerId, 10e18);
        vm.prank(alice);
        raffle.returnSurplus(winnerId, 10e18);
    }

    function test_returnSurplus_revertsIfNotWinner() public {
        vm.expectRevert("Raffle: not a winner");
        raffle.returnSurplus(999, 10e18);
    }

    function test_returnSurplus_revertsIfZeroAmount() public {
        uint256[] memory winners = _runFullLifecycle(42);
        vm.expectRevert("Raffle: zero amount");
        raffle.returnSurplus(winners[0], 0);
    }

    // ── Megaproject tests ──

    function test_megaproject_requiresApproval() public {
        paramStore.setPoolBudget(4, 10_000e18);

        vm.prank(address(uint160(uint256(PERSON_A))));
        vm.expectRevert("Raffle: megaproject not approved");
        raffle.submit(_makeProposal(PERSON_A, HASH_1, 5000e18, IRaffle.Tier.Megaproject, 5));
    }

    function test_megaproject_submitsAfterApproval() public {
        paramStore.setPoolBudget(4, 10_000e18);

        sortition.setPanel(1, true, true);
        sortition.setPurpose(1, keccak256(abi.encode("raffle.megaproject", HASH_1)));
        raffle.registerMegaprojectApproval(HASH_1, 1);

        vm.prank(address(uint160(uint256(PERSON_A))));
        uint256 id = raffle.submit(_makeProposal(PERSON_A, HASH_1, 5000e18, IRaffle.Tier.Megaproject, 5));
        assertEq(id, 1);
    }

    function test_megaproject_revertsIfPanelNotResolved() public {
        sortition.setPanel(1, false, false);

        vm.expectRevert("Raffle: panel not resolved");
        raffle.registerMegaprojectApproval(HASH_1, 1);
    }

    function test_megaproject_revertsIfPanelNotApproved() public {
        sortition.setPanel(1, true, false);

        vm.expectRevert("Raffle: panel not approved");
        raffle.registerMegaprojectApproval(HASH_1, 1);
    }

    // ── Period management tests ──

    function test_advancePeriod() public {
        assertEq(raffle.currentPeriod(), 1);
        _advancePeriod();
        assertEq(raffle.currentPeriod(), 2);
    }

    function test_advancePeriod_revertsIfPanelNotApproved() public {
        sortition.setPanel(1, false, false);

        vm.expectRevert("Raffle: panel not approved");
        raffle.advancePeriod(1);
    }

    function test_advancePeriod_revertsIfWrongPurpose() public {
        sortition.setPanel(1, true, true);
        sortition.setPurpose(1, keccak256("wrong"));

        vm.expectRevert("Raffle: wrong panel purpose");
        raffle.advancePeriod(1);
    }

    function test_newPeriodOpensNewPools() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(1, 42);
        raffle.draw(IRaffle.Tier.Micro);

        _advancePeriod();

        assertEq(uint8(raffle.poolState(IRaffle.Tier.Micro)), uint8(IRaffle.PoolState.Open));
        assertEq(raffle.entryCount(IRaffle.Tier.Micro), 0);
    }

    // ── Median computation via over-ask weights ──

    function test_medianComputedCorrectlyForOddCount() public {
        _submitDefault(PERSON_A, HASH_1, 50e18);
        _submitDefault(PERSON_B, HASH_2, 100e18);
        _submitDefault(PERSON_C, HASH_3, 200e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(raffle.overAskWeight(2), WAD);
        assertEq(raffle.overAskWeight(3), (100e18 * WAD) / 200e18);
    }

    function test_medianComputedCorrectlyForEvenCount() public {
        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 200e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(raffle.overAskWeight(2), (150e18 * WAD) / 200e18);
    }

    // ── Multiple tiers operate independently ──

    function test_tiersAreIndependent() public {
        paramStore.setPoolBudget(1, 500e18);

        _submitDefault(PERSON_A, HASH_1, 100e18);

        vm.prank(address(uint160(uint256(PERSON_B))));
        raffle.submit(_makeProposal(PERSON_B, HASH_2, 100e18, IRaffle.Tier.Small, 3));

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);

        assertEq(uint8(raffle.poolState(IRaffle.Tier.Micro)), uint8(IRaffle.PoolState.Frozen));
        assertEq(uint8(raffle.poolState(IRaffle.Tier.Small)), uint8(IRaffle.PoolState.Open));

        vm.prank(address(uint160(uint256(PERSON_C))));
        raffle.submit(_makeProposal(PERSON_C, HASH_3, 100e18, IRaffle.Tier.Small, 3));
        assertEq(raffle.entryCount(IRaffle.Tier.Small), 2);
    }

    // ── Weighted draw produces expected bias ──

    function test_drawFavorsLowerAsk() public {
        paramStore.setPoolBudget(0, 600e18);

        _submitDefault(PERSON_A, HASH_1, 100e18);
        _submitDefault(PERSON_B, HASH_2, 1000e18);

        vm.warp(block.timestamp + 86400);
        raffle.closeEntries(IRaffle.Tier.Micro);
        beacon.fulfillSeed(1, 12345);

        uint256[] memory winners = raffle.draw(IRaffle.Tier.Micro);

        assertEq(winners.length, 1);
    }

    // ── Median quickselect correctness & benchmarks ──

    function test_medianLargeArray() public {
        RaffleHarness harness = new RaffleHarness(
            address(personhood), address(paramStore), address(beacon),
            address(sortition), address(credit), treasuryAddr
        );

        // 51 elements in reverse order to stress the algorithm
        uint256[] memory values = new uint256[](51);
        for (uint256 i = 0; i < 51; i++) {
            values[i] = (51 - i) * 1e18;
        }
        // Sorted: 1e18 .. 51e18. Odd count, median = 26th value = 26e18
        assertEq(harness.computeMedian(values), 26e18);

        // 60 elements (even count) in pseudo-random order
        uint256[] memory even = new uint256[](60);
        for (uint256 i = 0; i < 60; i++) {
            even[i] = (uint256(keccak256(abi.encode(i))) % 1000 + 1) * 1e18;
        }
        uint256 qsMedian = harness.computeMedian(even);

        // Rebuild and sort with insertion sort to get reference median
        uint256[] memory ref = new uint256[](60);
        for (uint256 i = 0; i < 60; i++) {
            ref[i] = (uint256(keccak256(abi.encode(i))) % 1000 + 1) * 1e18;
        }
        for (uint256 i = 1; i < 60; i++) {
            uint256 key = ref[i];
            uint256 j = i;
            while (j > 0 && ref[j - 1] > key) {
                ref[j] = ref[j - 1];
                j--;
            }
            ref[j] = key;
        }
        uint256 refMedian = (ref[29] / 2) + (ref[30] / 2) + (ref[29] & ref[30] & 1);

        assertEq(qsMedian, refMedian);
    }

    function test_medianGasBenchmark() public {
        RaffleHarness harness = new RaffleHarness(
            address(personhood), address(paramStore), address(beacon),
            address(sortition), address(credit), treasuryAddr
        );

        // 100 pseudo-random elements
        uint256[] memory values = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            values[i] = (uint256(keccak256(abi.encode(i))) % 10_000 + 1) * 1e18;
        }

        uint256 gasBefore = gasleft();
        harness.computeMedian(values);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Quickselect gas (100 elements)", gasUsed);
        assertTrue(gasUsed > 0);
    }
}

contract RaffleHarness is Raffle {
    constructor(
        address _personhood,
        address _paramStore,
        address _beacon,
        address _sortition,
        address _credit,
        address _treasury
    ) Raffle(_personhood, _paramStore, _beacon, _sortition, _credit, _treasury) {}

    function computeMedian(uint256[] memory values) external pure returns (uint256) {
        return _computeMedian(values);
    }
}
