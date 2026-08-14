// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAudit} from "../interfaces/IAudit.sol";
import {ICredit} from "../interfaces/ICredit.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IReputation} from "../interfaces/IReputation.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Audit is IAudit, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ICredit public immutable credit;
    IPersonhood public immutable personhood;
    ITreasury public immutable treasury;
    IReputation public immutable reputation;
    IParameterStore public immutable parameterStore;

    uint256 private _claimCount;

    mapping(uint256 => Claim) private _claims;
    mapping(uint256 => mapping(bytes32 => bool)) private _hasReviewed;
    mapping(uint256 => bool) private _reviewIsBadFaith;
    mapping(uint256 => uint256) private _badFaithVotes;
    mapping(uint256 => mapping(bytes32 => bool)) private _hasMarkedBadFaith;

    uint8 public constant REQUIRED_REVIEWS = 3;

    constructor(
        address credit_,
        address personhood_,
        address treasury_,
        address reputation_,
        address parameterStore_
    ) {
        require(credit_ != address(0), "Audit: zero credit");
        require(personhood_ != address(0), "Audit: zero personhood");
        require(treasury_ != address(0), "Audit: zero treasury");
        require(reputation_ != address(0), "Audit: zero reputation");
        require(parameterStore_ != address(0), "Audit: zero parameterStore");

        credit = ICredit(credit_);
        personhood = IPersonhood(personhood_);
        treasury = ITreasury(treasury_);
        reputation = IReputation(reputation_);
        parameterStore = IParameterStore(parameterStore_);
    }

    function fileClaim(
        bytes32 target,
        bytes32 evidenceHash,
        uint256 stakeAmount
    ) external nonReentrant returns (uint256 claimId) {
        bytes32 claimantId = bytes32(uint256(uint160(msg.sender)));
        require(personhood.isUniquePerson(claimantId), "Audit: claimant not verified");
        require(target != bytes32(0), "Audit: zero target");
        require(evidenceHash != bytes32(0), "Audit: zero evidence");
        require(stakeAmount >= parameterStore.minAuditStake(), "Audit: stake below minimum");

        IERC20(address(credit)).safeTransferFrom(msg.sender, address(this), stakeAmount);

        claimId = _claimCount;
        _claimCount = claimId + 1;

        uint256 deadline = block.timestamp + parameterStore.auditReviewWindow();

        _claims[claimId] = Claim({
            claimant: claimantId,
            target: target,
            evidenceHash: evidenceHash,
            stake: stakeAmount,
            resolution: Resolution.Pending,
            reviewsFor: 0,
            reviewsAgainst: 0,
            filedAt: block.timestamp,
            resolvedAt: 0,
            reviewDeadline: deadline
        });

        emit ClaimFiled(claimId, claimantId, target, stakeAmount);
    }

    function review(uint256 claimId, bool upheld) external {
        Claim storage c = _claims[claimId];
        require(c.filedAt != 0, "Audit: claim does not exist");
        require(c.resolution == Resolution.Pending, "Audit: claim already resolved");
        require(block.timestamp <= c.reviewDeadline, "Audit: review deadline passed");

        bytes32 reviewerId = bytes32(uint256(uint160(msg.sender)));
        require(personhood.isUniquePerson(reviewerId), "Audit: reviewer not verified");
        require(reviewerId != c.claimant, "Audit: claimant cannot self-review");
        require(!_hasReviewed[claimId][reviewerId], "Audit: already reviewed");

        uint8 totalReviews = c.reviewsFor + c.reviewsAgainst;
        require(totalReviews < REQUIRED_REVIEWS, "Audit: all reviews submitted");

        _hasReviewed[claimId][reviewerId] = true;

        if (upheld) {
            c.reviewsFor += 1;
        } else {
            c.reviewsAgainst += 1;
        }

        emit ReviewSubmitted(claimId, reviewerId, upheld);
    }

    function resolve(uint256 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        require(c.filedAt != 0, "Audit: claim does not exist");
        require(c.resolution == Resolution.Pending, "Audit: already resolved");

        uint8 totalReviews = c.reviewsFor + c.reviewsAgainst;
        require(totalReviews == REQUIRED_REVIEWS, "Audit: need exactly 3 reviews");

        c.resolvedAt = block.timestamp;

        if (c.reviewsFor >= 2) {
            c.resolution = Resolution.Confirmed;

            IERC20(address(credit)).safeTransfer(
                address(uint160(uint256(c.claimant))),
                c.stake
            );

            treasury.payBounty(claimId, c.stake);

            reputation.updateDimension(c.claimant, "accuracy", int256(10));

            emit BountyPaid(claimId, c.claimant, c.stake);
            emit StakeRefunded(claimId, c.claimant, c.stake);
        } else if (_reviewIsBadFaith[claimId]) {
            c.resolution = Resolution.BadFaith;

            // ICredit.burn calls OZ _burn which always reverts on failure; SafeERC20 not needed
            credit.burn(address(this), c.stake);

            reputation.updateDimension(c.claimant, "accuracy", -int256(20));

            emit StakeSlashed(claimId, c.claimant, c.stake);
        } else {
            c.resolution = Resolution.Unconfirmed;

            IERC20(address(credit)).safeTransfer(
                address(uint160(uint256(c.claimant))),
                c.stake
            );

            emit StakeRefunded(claimId, c.claimant, c.stake);
        }

        emit ClaimResolved(claimId, c.resolution);
    }

    function expire(uint256 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        require(c.filedAt != 0, "Audit: claim does not exist");
        require(c.resolution == Resolution.Pending, "Audit: not pending");
        require(block.timestamp > c.reviewDeadline, "Audit: deadline not passed");

        uint8 totalReviews = c.reviewsFor + c.reviewsAgainst;
        require(totalReviews < REQUIRED_REVIEWS, "Audit: has enough reviews, use resolve");

        c.resolution = Resolution.Expired;
        c.resolvedAt = block.timestamp;

        IERC20(address(credit)).safeTransfer(
            address(uint160(uint256(c.claimant))),
            c.stake
        );

        emit ClaimExpired(claimId, c.claimant, c.stake);
        emit StakeRefunded(claimId, c.claimant, c.stake);
    }

    function markBadFaith(uint256 claimId) external {
        Claim storage c = _claims[claimId];
        require(c.filedAt != 0, "Audit: claim does not exist");
        require(c.resolution == Resolution.Pending, "Audit: already resolved");

        bytes32 reviewerId = bytes32(uint256(uint160(msg.sender)));
        require(_hasReviewed[claimId][reviewerId], "Audit: only reviewers can mark bad faith");
        require(!_hasMarkedBadFaith[claimId][reviewerId], "Audit: already marked");

        _hasMarkedBadFaith[claimId][reviewerId] = true;
        _badFaithVotes[claimId]++;

        if (_badFaithVotes[claimId] >= 2) {
            _reviewIsBadFaith[claimId] = true;
        }
    }

    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return _claims[claimId];
    }

    function minStake() external view returns (uint256) {
        return parameterStore.minAuditStake();
    }

    function claimCount() external view returns (uint256) {
        return _claimCount;
    }

    function hasReviewed(uint256 claimId, bytes32 reviewerId) external view returns (bool) {
        return _hasReviewed[claimId][reviewerId];
    }
}
