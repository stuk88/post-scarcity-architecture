// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {ICredit} from "../interfaces/ICredit.sol";
import {IBaseAllocation} from "../interfaces/IBaseAllocation.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";
import {ICappedGradient} from "../interfaces/ICappedGradient.sol";

contract Treasury is ITreasury, ReentrancyGuard {
    ICredit public immutable credit;
    IBaseAllocation public immutable baseAllocation;
    IParameterStore public immutable parameterStore;
    IPersonhood public immutable personhood;

    address public immutable raffleContract;
    address public immutable auditContract;
    address public immutable sortitionContract;
    address public immutable levyContract;
    address public immutable completionRegistryContract;
    ICappedGradient public immutable cappedGradient;

    uint256 private _currentPeriod;
    uint256 private _periodLevyCollected;
    uint256 private _periodStartBlock;

    constructor(
        address _credit,
        address _baseAllocation,
        address _parameterStore,
        address _personhood,
        address _raffleContract,
        address _auditContract,
        address _sortitionContract,
        address _levyContract,
        address _completionRegistryContract,
        address _cappedGradient
    ) {
        require(_credit != address(0), "Treasury: zero credit");
        require(_baseAllocation != address(0), "Treasury: zero base alloc");
        require(_parameterStore != address(0), "Treasury: zero store");
        require(_personhood != address(0), "Treasury: zero personhood");
        require(_raffleContract != address(0), "Treasury: zero raffle");
        require(_auditContract != address(0), "Treasury: zero audit");
        require(_sortitionContract != address(0), "Treasury: zero sortition");
        require(_levyContract != address(0), "Treasury: zero levy");
        require(_completionRegistryContract != address(0), "Treasury: zero registry");
        require(_cappedGradient != address(0), "Treasury: zero gradient");

        credit = ICredit(_credit);
        baseAllocation = IBaseAllocation(_baseAllocation);
        parameterStore = IParameterStore(_parameterStore);
        personhood = IPersonhood(_personhood);
        raffleContract = _raffleContract;
        auditContract = _auditContract;
        sortitionContract = _sortitionContract;
        levyContract = _levyContract;
        completionRegistryContract = _completionRegistryContract;
        cappedGradient = ICappedGradient(_cappedGradient);

        _currentPeriod = 1;
        _periodStartBlock = block.number;
    }

    function _advancePeriodIfNeeded() internal {
        uint256 periodLength = parameterStore.decayPeriod();
        if (periodLength == 0) return;
        uint256 elapsed = block.number - _periodStartBlock;
        if (elapsed < periodLength) return;
        uint256 periodsAdvanced = elapsed / periodLength;
        _currentPeriod += periodsAdvanced;
        _periodLevyCollected = 0;
        _periodStartBlock += periodsAdvanced * periodLength;
        emit PeriodRolled(_currentPeriod);
    }

    function streamBaseAllocation(bytes32 personId) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(personhood.isUniquePerson(personId), "Treasury: not verified");
        require(baseAllocation.isActive(personId), "Treasury: not active");

        uint256 amount = baseAllocation.withdraw(personId);
        require(amount > 0, "Treasury: nothing accrued");

        address recipient = baseAllocation.recipientOf(personId);
        credit.mint(recipient, amount);

        emit BaseAllocationStreamed(personId, amount);
    }

    function fundRafflePool(uint8 tier) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == raffleContract, "Treasury: only raffle");
        uint256 budget = parameterStore.poolBudget(tier);
        require(budget > 0, "Treasury: zero budget");

        credit.mint(raffleContract, budget);

        emit RafflePoolFunded(tier, budget);
    }

    function payBounty(uint256 claimId, uint256 stakeAmount) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == auditContract, "Treasury: only audit");
        require(stakeAmount > 0, "Treasury: zero stake");

        uint256 rawBounty = stakeAmount * parameterStore.bountyMultiplier() / 10_000;
        uint256 amount = cappedGradient.clamp(rawBounty);

        credit.mint(auditContract, amount);

        emit BountyPaid(claimId, amount);
    }

    function releaseProjectTranche(uint256 projectId, bytes32 orgId, uint256 trancheAmount) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == completionRegistryContract, "Treasury: only registry");
        require(trancheAmount > 0, "Treasury: zero tranche");

        uint256 amount = cappedGradient.clamp(trancheAmount);
        address recipient = baseAllocation.recipientOf(orgId);
        require(recipient != address(0), "Treasury: no recipient");

        credit.mint(recipient, amount);

        emit ProjectTrancheReleased(projectId, orgId, amount);
    }

    function fundRole(bytes32 personId, uint256 roleId) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == sortitionContract, "Treasury: only sortition");
        require(personhood.isUniquePerson(personId), "Treasury: not verified");

        address recipient = baseAllocation.recipientOf(personId);
        require(recipient != address(0), "Treasury: no recipient");

        uint256 rawAmount = parameterStore.basketCost();
        require(rawAmount > 0, "Treasury: zero amount");
        uint256 amount = cappedGradient.clamp(rawAmount);

        credit.mint(recipient, amount);

        emit RoleFunded(personId, roleId, amount);
    }

    function collectLevy(bytes32 orgId, uint256 attestedOutput) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == levyContract, "Treasury: only levy");

        uint256 levyAmount = attestedOutput * parameterStore.levyRate() / 10_000;
        _periodLevyCollected += levyAmount;

        emit LevyCollected(orgId, attestedOutput, levyAmount);
    }

    function totalCirculating() external view override returns (uint256) {
        return credit.totalSupply();
    }

    function periodLevyCollected() external view override returns (uint256) {
        return _periodLevyCollected;
    }

    function currentPeriod() external view override returns (uint256) {
        return _currentPeriod;
    }
}
