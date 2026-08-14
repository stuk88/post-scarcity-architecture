// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILevy} from "../interfaces/ILevy.sol";
import {ICredit} from "../interfaces/ICredit.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";

contract Levy is ILevy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ICredit public immutable credit;
    ITreasury public immutable treasury;
    IParameterStore public immutable parameterStore;
    address public immutable oracle;

    uint256 private _currentPeriod;
    uint256 private _periodTotal;
    uint256 private _periodStartBlock;

    mapping(uint256 => mapping(bytes32 => uint256)) private _orgPeriodTotals;

    constructor(
        address _credit,
        address _treasury,
        address _parameterStore,
        address _oracle
    ) {
        require(_credit != address(0), "Levy: zero credit");
        require(_treasury != address(0), "Levy: zero treasury");
        require(_parameterStore != address(0), "Levy: zero store");
        require(_oracle != address(0), "Levy: zero oracle");

        credit = ICredit(_credit);
        treasury = ITreasury(_treasury);
        parameterStore = IParameterStore(_parameterStore);
        oracle = _oracle;

        _currentPeriod = 1;
        _periodStartBlock = block.number;
    }

    function _advancePeriodIfNeeded() internal {
        uint256 periodLength = parameterStore.decayPeriod();
        if (periodLength == 0) return;
        uint256 elapsed = block.number - _periodStartBlock;
        if (elapsed < periodLength) return;
        uint256 periodsAdvanced = elapsed / periodLength;
        uint256 previousTotal = _periodTotal;
        _currentPeriod += periodsAdvanced;
        _periodTotal = 0;
        _periodStartBlock += periodsAdvanced * periodLength;
        emit PeriodRolled(_currentPeriod, previousTotal);
    }

    function collectDigital(bytes32 orgId, uint256 settledRevenue) external override nonReentrant {
        _advancePeriodIfNeeded();
        uint256 rate = parameterStore.levyRate();
        uint256 levyAmount = settledRevenue * rate / 10_000;
        require(levyAmount > 0, "Levy: zero levy");

        IERC20(address(credit)).safeTransferFrom(msg.sender, address(this), levyAmount);
        credit.burn(address(this), levyAmount);

        treasury.collectLevy(orgId, settledRevenue);

        _periodTotal += levyAmount;
        _orgPeriodTotals[_currentPeriod][orgId] += levyAmount;

        emit DigitalLevyCollected(orgId, settledRevenue, levyAmount);
    }

    function collectPhysical(
        bytes32 orgId,
        uint256 attestedValue,
        bytes32 oracleProof
    ) external override nonReentrant {
        _advancePeriodIfNeeded();
        require(msg.sender == oracle, "Levy: only oracle");
        require(oracleProof != bytes32(0), "Levy: empty proof");

        uint256 rate = parameterStore.levyRate();
        uint256 levyAmount = attestedValue * rate / 10_000;
        require(levyAmount > 0, "Levy: zero levy");

        IERC20(address(credit)).safeTransferFrom(oracle, address(this), levyAmount);
        credit.burn(address(this), levyAmount);

        treasury.collectLevy(orgId, attestedValue);

        _periodTotal += levyAmount;
        _orgPeriodTotals[_currentPeriod][orgId] += levyAmount;

        emit PhysicalLevyCollected(orgId, attestedValue, levyAmount, oracleProof);
    }

    function currentRate() external view override returns (uint256) {
        return parameterStore.levyRate();
    }

    function periodTotal() external view override returns (uint256) {
        return _periodTotal;
    }

    function orgPeriodTotal(bytes32 orgId) external view override returns (uint256) {
        return _orgPeriodTotals[_currentPeriod][orgId];
    }

    function currentPeriod() external view override returns (uint256) {
        return _currentPeriod;
    }
}
