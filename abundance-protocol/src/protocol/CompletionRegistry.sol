// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICompletionRegistry} from "../interfaces/ICompletionRegistry.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IReputation} from "../interfaces/IReputation.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CompletionRegistry is ICompletionRegistry, ReentrancyGuard {
    ITreasury public immutable treasury;
    IReputation public immutable reputation;
    IPersonhood public immutable personhood;
    IParameterStore public immutable parameterStore;

    address public immutable governance;

    uint256 private _projectCount;

    mapping(uint256 => Project) private _projects;
    mapping(uint256 => mapping(uint256 => bytes32)) private _milestoneEvidence;
    mapping(uint256 => mapping(uint256 => bool)) private _trancheReleased;
    mapping(bytes32 => bool) private _banned;
    mapping(bytes32 => uint256) private _cooldownUntil;
    mapping(bytes32 => uint256) private _abandonmentCount;

    uint256 public constant COOLDOWN_DURATION = 180 days;
    uint256 public constant MAX_ABANDONMENTS = 3;

    modifier onlyGovernance() {
        require(msg.sender == governance, "CompletionRegistry: caller is not governance");
        _;
    }

    constructor(address treasury_, address reputation_, address personhood_, address parameterStore_, address governance_) {
        require(treasury_ != address(0), "CompletionRegistry: zero treasury");
        require(reputation_ != address(0), "CompletionRegistry: zero reputation");
        require(personhood_ != address(0), "CompletionRegistry: zero personhood");
        require(parameterStore_ != address(0), "CompletionRegistry: zero parameterStore");
        require(governance_ != address(0), "CompletionRegistry: zero governance");

        treasury = ITreasury(treasury_);
        reputation = IReputation(reputation_);
        personhood = IPersonhood(personhood_);
        parameterStore = IParameterStore(parameterStore_);
        governance = governance_;
    }

    function registerProject(
        bytes32 orgId,
        uint256 proposalId,
        uint256 budget,
        uint256 milestones
    ) external onlyGovernance {
        require(orgId != bytes32(0), "CompletionRegistry: zero orgId");
        require(milestones > 0, "CompletionRegistry: zero milestones");
        require(budget > 0, "CompletionRegistry: zero budget");
        require(!_banned[orgId], "CompletionRegistry: org is banned");
        require(!isInCooldown(orgId), "CompletionRegistry: org is in cooldown");

        uint256 projectId = _projectCount;
        _projectCount = projectId + 1;

        _projects[projectId] = Project({
            orgId: orgId,
            proposalId: proposalId,
            budget: budget,
            budgetSpent: 0,
            outcome: Outcome.InProgress,
            milestonesTotal: milestones,
            milestonesCompleted: 0,
            registeredAt: block.timestamp,
            finalizedAt: 0
        });

        emit ProjectRegistered(projectId, orgId, proposalId, budget);
    }

    function completeMilestone(uint256 projectId, bytes32 evidenceHash) external onlyGovernance {
        Project storage p = _projects[projectId];
        require(p.registeredAt != 0, "CompletionRegistry: project does not exist");
        require(p.outcome == Outcome.InProgress, "CompletionRegistry: project not in progress");
        require(p.milestonesCompleted < p.milestonesTotal, "CompletionRegistry: all milestones completed");
        require(evidenceHash != bytes32(0), "CompletionRegistry: zero evidence hash");

        uint256 milestoneIndex = p.milestonesCompleted;
        p.milestonesCompleted = milestoneIndex + 1;
        _milestoneEvidence[projectId][milestoneIndex] = evidenceHash;

        emit MilestoneCompleted(projectId, milestoneIndex, evidenceHash);
    }

    function releaseTranche(uint256 projectId, uint256 milestoneIndex) external nonReentrant onlyGovernance {
        Project storage p = _projects[projectId];
        require(p.registeredAt != 0, "CompletionRegistry: project does not exist");
        require(milestoneIndex < p.milestonesCompleted, "CompletionRegistry: milestone not completed");
        require(!_trancheReleased[projectId][milestoneIndex], "CompletionRegistry: tranche already released");

        uint256 tranche = p.budget / p.milestonesTotal;
        _trancheReleased[projectId][milestoneIndex] = true;
        p.budgetSpent += tranche;

        treasury.releaseProjectTranche(projectId, p.orgId, tranche);

        emit TrancheReleased(projectId, milestoneIndex, tranche);
    }

    function finalizeOutcome(uint256 projectId, Outcome outcome) external onlyGovernance {
        Project storage p = _projects[projectId];
        require(p.registeredAt != 0, "CompletionRegistry: project does not exist");
        require(p.outcome == Outcome.InProgress, "CompletionRegistry: already finalized");
        require(outcome != Outcome.InProgress, "CompletionRegistry: cannot finalize as InProgress");

        p.outcome = outcome;
        p.finalizedAt = block.timestamp;

        if (outcome == Outcome.Delivered) {
            reputation.updateDimension(p.orgId, "reliability", int256(10));
            reputation.updateDimension(p.orgId, "volume", int256(1));
        } else if (outcome == Outcome.PartialPivot) {
            reputation.updateDimension(p.orgId, "reliability", int256(5));
            reputation.updateDimension(p.orgId, "novelty", int256(3));
        } else if (outcome == Outcome.HonestFailure) {
            // No penalty, full future eligibility
        } else if (outcome == Outcome.Abandoned) {
            _abandonmentCount[p.orgId] += 1;
            reputation.updateDimension(p.orgId, "reliability", -int256(5));
            if (_abandonmentCount[p.orgId] >= MAX_ABANDONMENTS) {
                _banned[p.orgId] = true;
                emit AbandonmentAutoBan(p.orgId, _abandonmentCount[p.orgId]);
            } else {
                _cooldownUntil[p.orgId] = block.timestamp + COOLDOWN_DURATION;
                emit CooldownApplied(p.orgId, _cooldownUntil[p.orgId]);
            }
        } else if (outcome == Outcome.Fraudulent) {
            _banned[p.orgId] = true;
            reputation.updateDimension(p.orgId, "reliability", -int256(100));
            emit FraudBountyActivated(projectId, p.orgId);
        }

        emit OutcomeFinalized(projectId, outcome);
    }

    function returnUnspentBudget(uint256 projectId) external view returns (uint256 unspent) {
        Project storage p = _projects[projectId];
        require(p.registeredAt != 0, "CompletionRegistry: project does not exist");
        require(p.outcome != Outcome.InProgress, "CompletionRegistry: not finalized");
        unspent = p.budget - p.budgetSpent;
    }

    function getProject(uint256 projectId) external view returns (Project memory) {
        return _projects[projectId];
    }

    function isInCooldown(bytes32 orgId) public view returns (bool) {
        return _cooldownUntil[orgId] > block.timestamp;
    }

    function isBanned(bytes32 orgId) external view returns (bool) {
        return _banned[orgId];
    }

    function abandonmentCount(bytes32 orgId) external view returns (uint256) {
        return _abandonmentCount[orgId];
    }

    function projectCount() external view returns (uint256) {
        return _projectCount;
    }
}
