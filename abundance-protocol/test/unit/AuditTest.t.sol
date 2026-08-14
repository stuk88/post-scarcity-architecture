// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Audit} from "../../src/protocol/Audit.sol";
import {IAudit} from "../../src/interfaces/IAudit.sol";
import {ICredit} from "../../src/interfaces/ICredit.sol";
import {IPersonhood} from "../../src/interfaces/IPersonhood.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";
import {IParameterStore} from "../../src/interfaces/IParameterStore.sol";

contract MockCredit is ICredit {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint256 public totalBurned;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Minted(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "MockCredit: burn exceeds balance");
        _balances[from] -= amount;
        _totalSupply -= amount;
        totalBurned += amount;
        emit Burned(from, amount);
    }

    function updateBasketRate(uint256) external {}
    function basketRate() external pure returns (uint256) { return 1e18; }
    function totalMinted() external pure returns (uint256) { return 0; }

    function totalSupply() external view returns (uint256) { return _totalSupply; }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "MockCredit: insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "MockCredit: insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "MockCredit: insufficient allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
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

contract MockTreasury is ITreasury {
    uint256 public lastBountyClaimId;
    bool public bountyCalled;

    function payBounty(uint256 claimId, uint256) external {
        lastBountyClaimId = claimId;
        bountyCalled = true;
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

contract MockParameterStore is IParameterStore {
    uint256 private _minAuditStake = 100e18;

    function setMinAuditStake(uint256 val) external {
        _minAuditStake = val;
    }

    function basketCost() external pure returns (uint256) { return 1e18; }
    function gradientCeiling() external pure returns (uint256) { return 10e18; }
    function gradientFloor() external pure returns (uint256) { return 1e18; }
    function levyRate() external pure returns (uint256) { return 500; }
    function minAuditStake() external view returns (uint256) { return _minAuditStake; }
    function poolBudget(uint8) external pure returns (uint256) { return 1000e18; }
    function decayPeriod() external pure returns (uint256) { return 100; }
    function panelSize() external pure returns (uint256) { return 3; }
    function supermajorityThreshold() external pure returns (uint256) { return 6667; }
    function emergencyDuration() external pure returns (uint256) { return 1000; }
    function auditReviewWindow() external pure returns (uint256) { return 7 days; }
    function bountyMultiplier() external pure returns (uint256) { return 20000; }
}

contract AuditTest is Test {
    Audit public audit;
    MockCredit public credit;
    MockPersonhood public personhood;
    MockTreasury public treasury;
    MockReputation public reputation;
    MockParameterStore public parameterStore;

    address public claimant = makeAddr("claimant");
    address public reviewer1 = makeAddr("reviewer1");
    address public reviewer2 = makeAddr("reviewer2");
    address public reviewer3 = makeAddr("reviewer3");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public claimantId;
    bytes32 public reviewer1Id;
    bytes32 public reviewer2Id;
    bytes32 public reviewer3Id;

    bytes32 public constant TARGET = keccak256("target");
    bytes32 public constant EVIDENCE = keccak256("evidence");
    uint256 public constant STAKE = 200e18;

    function setUp() public {
        credit = new MockCredit();
        personhood = new MockPersonhood();
        treasury = new MockTreasury();
        reputation = new MockReputation();
        parameterStore = new MockParameterStore();

        audit = new Audit(
            address(credit),
            address(personhood),
            address(treasury),
            address(reputation),
            address(parameterStore)
        );

        claimantId = bytes32(uint256(uint160(claimant)));
        reviewer1Id = bytes32(uint256(uint160(reviewer1)));
        reviewer2Id = bytes32(uint256(uint160(reviewer2)));
        reviewer3Id = bytes32(uint256(uint160(reviewer3)));

        personhood.setVerified(claimantId, true);
        personhood.setVerified(reviewer1Id, true);
        personhood.setVerified(reviewer2Id, true);
        personhood.setVerified(reviewer3Id, true);

        credit.mint(claimant, 1000e18);

        vm.prank(claimant);
        credit.approve(address(audit), type(uint256).max);
    }

    function test_fileClaim_createsClaimRecord() public {
        vm.prank(claimant);
        uint256 claimId = audit.fileClaim(TARGET, EVIDENCE, STAKE);

        assertEq(claimId, 0);
        assertEq(audit.claimCount(), 1);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(c.claimant, claimantId);
        assertEq(c.target, TARGET);
        assertEq(c.evidenceHash, EVIDENCE);
        assertEq(c.stake, STAKE);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Pending));
        assertEq(c.reviewsFor, 0);
        assertEq(c.reviewsAgainst, 0);
        assertTrue(c.filedAt > 0);
    }

    function test_fileClaim_transfersStakeInCredit() public {
        uint256 balBefore = credit.balanceOf(claimant);

        vm.prank(claimant);
        audit.fileClaim(TARGET, EVIDENCE, STAKE);

        assertEq(credit.balanceOf(claimant), balBefore - STAKE);
        assertEq(credit.balanceOf(address(audit)), STAKE);
    }

    function test_fileClaim_revertsIfNotVerified() public {
        personhood.setVerified(claimantId, false);
        vm.prank(claimant);
        vm.expectRevert("Audit: claimant not verified");
        audit.fileClaim(TARGET, EVIDENCE, STAKE);
    }

    function test_fileClaim_revertsOnZeroTarget() public {
        vm.prank(claimant);
        vm.expectRevert("Audit: zero target");
        audit.fileClaim(bytes32(0), EVIDENCE, STAKE);
    }

    function test_fileClaim_revertsOnZeroEvidence() public {
        vm.prank(claimant);
        vm.expectRevert("Audit: zero evidence");
        audit.fileClaim(TARGET, bytes32(0), STAKE);
    }

    function test_fileClaim_revertsOnStakeBelowMinimum() public {
        vm.prank(claimant);
        vm.expectRevert("Audit: stake below minimum");
        audit.fileClaim(TARGET, EVIDENCE, 1e18);
    }

    function test_review_submitsReview() public {
        _fileClaim();

        vm.prank(reviewer1);
        audit.review(0, true);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(c.reviewsFor, 1);
        assertEq(c.reviewsAgainst, 0);
        assertTrue(audit.hasReviewed(0, reviewer1Id));
    }

    function test_review_revertsOnSelfReview() public {
        _fileClaim();

        vm.prank(claimant);
        vm.expectRevert("Audit: claimant cannot self-review");
        audit.review(0, true);
    }

    function test_review_revertsOnDoubleReview() public {
        _fileClaim();

        vm.prank(reviewer1);
        audit.review(0, true);

        vm.prank(reviewer1);
        vm.expectRevert("Audit: already reviewed");
        audit.review(0, false);
    }

    function test_review_revertsOnUnverifiedReviewer() public {
        _fileClaim();

        bytes32 unverifiedId = bytes32(uint256(uint160(unauthorized)));
        personhood.setVerified(unverifiedId, false);

        vm.prank(unauthorized);
        vm.expectRevert("Audit: reviewer not verified");
        audit.review(0, true);
    }

    function test_review_revertsAfterThreeReviews() public {
        _fileClaim();
        _submitThreeReviews(0, true, true, true);

        address reviewer4 = makeAddr("reviewer4");
        bytes32 reviewer4Id = bytes32(uint256(uint160(reviewer4)));
        personhood.setVerified(reviewer4Id, true);

        vm.prank(reviewer4);
        vm.expectRevert("Audit: all reviews submitted");
        audit.review(0, true);
    }

    function test_review_requiresExactlyThreeForResolution() public {
        _fileClaim();

        vm.prank(reviewer1);
        audit.review(0, true);

        vm.expectRevert("Audit: need exactly 3 reviews");
        audit.resolve(0);

        vm.prank(reviewer2);
        audit.review(0, true);

        vm.expectRevert("Audit: need exactly 3 reviews");
        audit.resolve(0);

        vm.prank(reviewer3);
        audit.review(0, false);

        audit.resolve(0);
        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Confirmed));
    }

    function test_resolve_confirmed_returnStakeAndPaysBounty() public {
        _fileClaim();
        _submitThreeReviews(0, true, true, false);

        uint256 claimantBalBefore = credit.balanceOf(claimant);

        audit.resolve(0);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Confirmed));
        assertTrue(c.resolvedAt > 0);

        assertEq(credit.balanceOf(claimant), claimantBalBefore + STAKE);
        assertTrue(treasury.bountyCalled());
        assertEq(treasury.lastBountyClaimId(), 0);

        assertEq(reputation.callCount(), 1);
        (bytes32 pid, bytes32 dim, int256 delta) = reputation.calls(0);
        assertEq(pid, claimantId);
        assertEq(dim, "accuracy");
        assertEq(delta, int256(10));
    }

    function test_resolve_unconfirmed_returnsStake() public {
        _fileClaim();
        _submitThreeReviews(0, false, false, true);

        uint256 claimantBalBefore = credit.balanceOf(claimant);

        audit.resolve(0);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Unconfirmed));

        assertEq(credit.balanceOf(claimant), claimantBalBefore + STAKE);
        assertFalse(treasury.bountyCalled());
        assertEq(reputation.callCount(), 0);
    }

    function test_resolve_badFaith_slashesStake() public {
        _fileClaim();
        _submitThreeReviews(0, false, false, true);

        vm.prank(reviewer1);
        audit.markBadFaith(0);
        vm.prank(reviewer2);
        audit.markBadFaith(0);

        uint256 auditBalBefore = credit.balanceOf(address(audit));

        audit.resolve(0);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.BadFaith));

        assertEq(credit.balanceOf(address(audit)), auditBalBefore - STAKE);
        assertEq(credit.totalBurned(), STAKE);

        assertEq(reputation.callCount(), 1);
        (bytes32 pid, bytes32 dim, int256 delta) = reputation.calls(0);
        assertEq(pid, claimantId);
        assertEq(dim, "accuracy");
        assertEq(delta, -int256(20));
    }

    function test_resolve_revertsOnDoubleResolve() public {
        _fileClaim();
        _submitThreeReviews(0, true, true, true);

        audit.resolve(0);

        vm.expectRevert("Audit: already resolved");
        audit.resolve(0);
    }

    function test_resolve_revertsOnNonexistentClaim() public {
        vm.expectRevert("Audit: claim does not exist");
        audit.resolve(999);
    }

    function test_fullLifecycle_confirmed() public {
        vm.prank(claimant);
        uint256 claimId = audit.fileClaim(TARGET, EVIDENCE, STAKE);

        vm.prank(reviewer1);
        audit.review(claimId, true);
        vm.prank(reviewer2);
        audit.review(claimId, true);
        vm.prank(reviewer3);
        audit.review(claimId, false);

        uint256 claimantBalBefore = credit.balanceOf(claimant);
        audit.resolve(claimId);

        IAudit.Claim memory c = audit.getClaim(claimId);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Confirmed));
        assertEq(credit.balanceOf(claimant), claimantBalBefore + STAKE);
        assertTrue(treasury.bountyCalled());
    }

    function test_fullLifecycle_badFaith() public {
        vm.prank(claimant);
        uint256 claimId = audit.fileClaim(TARGET, EVIDENCE, STAKE);

        vm.prank(reviewer1);
        audit.review(claimId, false);
        vm.prank(reviewer2);
        audit.review(claimId, false);
        vm.prank(reviewer3);
        audit.review(claimId, true);

        vm.prank(reviewer1);
        audit.markBadFaith(claimId);
        vm.prank(reviewer2);
        audit.markBadFaith(claimId);

        audit.resolve(claimId);

        IAudit.Claim memory c = audit.getClaim(claimId);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.BadFaith));
        assertEq(credit.totalBurned(), STAKE);
    }

    function test_markBadFaith_singleReviewerDoesNotTrigger() public {
        _fileClaim();
        _submitThreeReviews(0, false, false, true);

        vm.prank(reviewer1);
        audit.markBadFaith(0);

        audit.resolve(0);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Unconfirmed));
    }

    function test_markBadFaith_twoReviewersTrigger() public {
        _fileClaim();
        _submitThreeReviews(0, false, false, true);

        vm.prank(reviewer1);
        audit.markBadFaith(0);
        vm.prank(reviewer2);
        audit.markBadFaith(0);

        audit.resolve(0);

        IAudit.Claim memory c = audit.getClaim(0);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.BadFaith));
    }

    function test_markBadFaith_revertsIfAlreadyMarked() public {
        _fileClaim();
        _submitThreeReviews(0, false, false, true);

        vm.prank(reviewer1);
        audit.markBadFaith(0);

        vm.prank(reviewer1);
        vm.expectRevert("Audit: already marked");
        audit.markBadFaith(0);
    }

    function test_minStake_readsFromParameterStore() public view {
        assertEq(audit.minStake(), 100e18);
    }

    function test_expire_refundsStakeAfterDeadline() public {
        uint256 claimId = _fileClaim();

        // Only 1 review submitted (need 3)
        vm.prank(reviewer1);
        audit.review(claimId, true);

        // Advance past the review deadline (7 days)
        vm.warp(block.timestamp + 7 days + 1);

        uint256 balanceBefore = credit.balanceOf(claimant);
        audit.expire(claimId);

        IAudit.Claim memory c = audit.getClaim(claimId);
        assertEq(uint8(c.resolution), uint8(IAudit.Resolution.Expired));
        assertEq(credit.balanceOf(claimant), balanceBefore + STAKE);
    }

    function test_expire_revertsBeforeDeadline() public {
        _fileClaim();

        vm.expectRevert("Audit: deadline not passed");
        audit.expire(0);
    }

    function test_expire_revertsIfEnoughReviews() public {
        uint256 claimId = _fileClaim();
        _submitThreeReviews(claimId, true, true, false);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert("Audit: has enough reviews, use resolve");
        audit.expire(claimId);
    }

    function test_review_revertsAfterDeadline() public {
        _fileClaim();

        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(reviewer1);
        vm.expectRevert("Audit: review deadline passed");
        audit.review(0, true);
    }

    function _fileClaim() internal returns (uint256) {
        vm.prank(claimant);
        return audit.fileClaim(TARGET, EVIDENCE, STAKE);
    }

    function _submitThreeReviews(uint256 claimId, bool v1, bool v2, bool v3) internal {
        vm.prank(reviewer1);
        audit.review(claimId, v1);
        vm.prank(reviewer2);
        audit.review(claimId, v2);
        vm.prank(reviewer3);
        audit.review(claimId, v3);
    }
}
