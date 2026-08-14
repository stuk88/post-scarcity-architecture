// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {Audit} from "../../src/protocol/Audit.sol";
import {IAudit} from "../../src/interfaces/IAudit.sol";
import {ICredit} from "../../src/interfaces/ICredit.sol";
import {IPersonhood} from "../../src/interfaces/IPersonhood.sol";
import {IReputation} from "../../src/interfaces/IReputation.sol";
import {MockParameterStore, MockTreasury} from "../mocks/Mocks.sol";

contract AuditMockCredit is ICredit {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _supply;
    uint256 private _minted;
    uint256 private _burned;

    function freeMint(address to, uint256 amount) external {
        _balances[to] += amount;
        _supply += amount;
        _minted += amount;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _supply += amount;
        _minted += amount;
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "insufficient");
        _balances[from] -= amount;
        _supply -= amount;
        _burned += amount;
    }

    function updateBasketRate(uint256) external {}
    function basketRate() external pure returns (uint256) { return 1e18; }
    function totalMinted() external view returns (uint256) { return _minted; }
    function totalBurned() external view returns (uint256) { return _burned; }
    function totalSupply() external view returns (uint256) { return _supply; }
    function balanceOf(address a) external view returns (uint256) { return _balances[a]; }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "insufficient");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "insufficient");
        require(_allowances[from][msg.sender] >= amount, "no allowance");
        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;
        return true;
    }
}

contract AuditMockPersonhood is IPersonhood {
    mapping(bytes32 => bool) private _verified;

    function setVerified(bytes32 id, bool v) external { _verified[id] = v; }
    function isUniquePerson(bytes32 id) external view returns (bool) { return _verified[id]; }
    function attestationEpoch(bytes32) external pure returns (uint256) { return 0; }
    function provider(bytes32) external pure returns (address) { return address(0); }
    function isRevoked(bytes32) external pure returns (bool) { return false; }
    function verifiedCount() external pure returns (uint256) { return 0; }
}

contract AuditMockReputation is IReputation {
    function updateDimension(bytes32, bytes32, int256) external {}
    function getScore(bytes32) external pure returns (Score memory) { return Score(0,0,0,0); }
    function getDimension(bytes32, bytes32) external pure returns (uint256) { return 0; }
    function compositeScore(bytes32) external pure returns (uint256) { return 0; }
}

contract TimeWarper {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function warpForward(uint256 delta) external {
        delta = (delta % 30 days) + 1;
        _vm.warp(block.timestamp + delta);
    }
}

contract AuditHandler is StdUtils {
    Audit public audit;
    AuditMockCredit public mockCredit;
    AuditMockPersonhood public mockPersonhood;

    uint256 public ghostPendingStake;
    uint256[] public filedClaimIds;
    mapping(uint256 => bool) public claimPending;
    mapping(uint256 => uint256) public claimStake;

    constructor(
        Audit _audit,
        AuditMockCredit _mockCredit,
        AuditMockPersonhood _mockPersonhood
    ) {
        audit = _audit;
        mockCredit = _mockCredit;
        mockPersonhood = _mockPersonhood;

        bytes32 handlerId = bytes32(uint256(uint160(address(this))));
        mockPersonhood.setVerified(handlerId, true);
    }

    function fileClaim(uint256 stakeExtra) external {
        uint256 minStake = 100e18;
        uint256 stake = minStake + _bound(stakeExtra, 0, 1e24);

        mockCredit.freeMint(address(this), stake);
        mockCredit.approve(address(audit), stake);

        uint256 nonce = filedClaimIds.length;
        uint256 claimId = audit.fileClaim(
            bytes32(nonce + 1),
            bytes32(uint256(keccak256(abi.encode(nonce)))),
            stake
        );

        filedClaimIds.push(claimId);
        claimPending[claimId] = true;
        claimStake[claimId] = stake;
        ghostPendingStake += stake;
    }

    function expireClaim(uint256 claimIdx) external {
        if (filedClaimIds.length == 0) return;
        claimIdx = _bound(claimIdx, 0, filedClaimIds.length - 1);
        uint256 claimId = filedClaimIds[claimIdx];
        if (!claimPending[claimId]) return;

        IAudit.Claim memory c = audit.getClaim(claimId);
        if (c.resolution != IAudit.Resolution.Pending) {
            claimPending[claimId] = false;
            ghostPendingStake -= claimStake[claimId];
            return;
        }
        if (block.timestamp <= c.reviewDeadline) return;

        audit.expire(claimId);
        claimPending[claimId] = false;
        ghostPendingStake -= claimStake[claimId];
    }

    function filedCount() external view returns (uint256) {
        return filedClaimIds.length;
    }
}

contract InvariantAuditTest is Test {
    Audit audit;
    AuditMockCredit mockCredit;
    AuditMockPersonhood mockPersonhood;
    MockTreasury mockTreasury;
    AuditMockReputation mockReputation;
    MockParameterStore paramStore;
    AuditHandler handler;
    TimeWarper warper;

    address claimant = makeAddr("claimant");
    bytes32 claimantId;
    uint256 constant STAKE = 100e18;

    function setUp() public {
        mockCredit = new AuditMockCredit();
        mockPersonhood = new AuditMockPersonhood();
        mockTreasury = new MockTreasury();
        mockReputation = new AuditMockReputation();
        paramStore = new MockParameterStore();
        paramStore.setMinAuditStake(STAKE);
        paramStore.setAuditReviewWindow(7200);

        audit = new Audit(
            address(mockCredit),
            address(mockPersonhood),
            address(mockTreasury),
            address(mockReputation),
            address(paramStore)
        );

        handler = new AuditHandler(audit, mockCredit, mockPersonhood);
        warper = new TimeWarper();

        claimantId = bytes32(uint256(uint160(claimant)));
        mockPersonhood.setVerified(claimantId, true);

        bytes4[] memory handlerSelectors = new bytes4[](2);
        handlerSelectors[0] = AuditHandler.fileClaim.selector;
        handlerSelectors[1] = AuditHandler.expireClaim.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: handlerSelectors}));

        bytes4[] memory warperSelectors = new bytes4[](1);
        warperSelectors[0] = TimeWarper.warpForward.selector;
        targetSelector(FuzzSelector({addr: address(warper), selectors: warperSelectors}));

        targetContract(address(handler));
        targetContract(address(warper));
    }

    function invariant_pendingStakesAccountedFor() public view {
        uint256 auditBalance = mockCredit.balanceOf(address(audit));
        assertEq(auditBalance, handler.ghostPendingStake(), "audit balance != ghost pending stake");
    }

    function _fileClaimAsUser() internal returns (uint256) {
        uint256 stake = paramStore.minAuditStake();
        mockCredit.freeMint(claimant, stake);
        vm.prank(claimant);
        mockCredit.approve(address(audit), stake);

        vm.prank(claimant);
        return audit.fileClaim(bytes32(uint256(1)), bytes32(uint256(0xdead)), stake);
    }

    function testFuzz_stakeNeverStuck(uint256 warpTime) public {
        warpTime = bound(warpTime, 1, 365 days);
        uint256 reviewWindow = paramStore.auditReviewWindow();

        uint256 claimId = _fileClaimAsUser();

        vm.warp(block.timestamp + reviewWindow + warpTime);

        uint256 balanceBefore = mockCredit.balanceOf(claimant);
        audit.expire(claimId);
        uint256 balanceAfter = mockCredit.balanceOf(claimant);

        assertEq(balanceAfter - balanceBefore, STAKE, "stake not fully refunded");

        IAudit.Claim memory c = audit.getClaim(claimId);
        assertTrue(c.resolution == IAudit.Resolution.Expired, "not expired");
    }

    function testFuzz_reviewDeadlineEnforced(uint256 warpTime) public {
        warpTime = bound(warpTime, 1, 365 days);
        uint256 reviewWindow = paramStore.auditReviewWindow();

        uint256 claimId = _fileClaimAsUser();

        vm.warp(block.timestamp + reviewWindow + warpTime);

        address reviewer = makeAddr("reviewer");
        bytes32 reviewerId = bytes32(uint256(uint160(reviewer)));
        mockPersonhood.setVerified(reviewerId, true);

        vm.prank(reviewer);
        vm.expectRevert("Audit: review deadline passed");
        audit.review(claimId, true);
    }

    function testFuzz_expireBeforeDeadlineReverts(uint256 warpTime) public {
        uint256 reviewWindow = paramStore.auditReviewWindow();
        warpTime = bound(warpTime, 0, reviewWindow);

        uint256 claimId = _fileClaimAsUser();

        vm.warp(block.timestamp + warpTime);

        vm.expectRevert("Audit: deadline not passed");
        audit.expire(claimId);
    }

    function testFuzz_stakeRefundedAtVariousAmounts(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, STAKE, 1e30);
        uint256 reviewWindow = paramStore.auditReviewWindow();

        mockCredit.freeMint(claimant, stakeAmount);
        vm.prank(claimant);
        mockCredit.approve(address(audit), stakeAmount);

        vm.prank(claimant);
        uint256 claimId = audit.fileClaim(
            bytes32(uint256(1)),
            bytes32(uint256(keccak256(abi.encode(stakeAmount)))),
            stakeAmount
        );

        vm.warp(block.timestamp + reviewWindow + 1);

        uint256 balanceBefore = mockCredit.balanceOf(claimant);
        audit.expire(claimId);
        uint256 balanceAfter = mockCredit.balanceOf(claimant);

        assertEq(balanceAfter - balanceBefore, stakeAmount, "variable stake not fully refunded");
    }
}
