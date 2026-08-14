// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDecayCycle} from "../interfaces/IDecayCycle.sol";
import {ISortition} from "../interfaces/ISortition.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Migration is a signaling contract. The protocol layer has no upgrade key:
///      executeMigration emits MigrationExecuted with the approved newProtocol address,
///      which off-chain deployment infrastructure consumes to coordinate contract
///      deployment and state migration. Each protocol contract is immutable with no
///      admin key, so actual ownership transfer is impossible from within this contract.
contract DecayCycle is IDecayCycle, ReentrancyGuard {
    ISortition public immutable sortition;
    IParameterStore public immutable params;

    uint256 internal _currentCycle;
    CyclePhase internal _currentPhase;
    uint256 internal _reviewWindowBlock;
    bool internal _pendingMigration;
    address internal _approvedNewProtocol;
    uint256 internal _approvalPanelId;

    error NotInPhase(CyclePhase expected, CyclePhase actual);
    error CycleNotExpired();
    error NoMigrationPending();
    error PanelNotApproved(uint256 panelId);
    error WrongPanelPurpose();
    error ZeroProtocolAddress();
    error SamePanelAsApproval(uint256 panelId);

    error ZeroAddress();

    constructor(address _sortition, address _params) {
        if (_sortition == address(0)) revert ZeroAddress();
        if (_params == address(0)) revert ZeroAddress();
        sortition = ISortition(_sortition);
        params = IParameterStore(_params);
        _reviewWindowBlock = block.number + params.decayPeriod();
        emit CycleStarted(0, block.number, _reviewWindowBlock);
    }

    function openReviewWindow() external {
        if (_currentPhase != CyclePhase.Normal) revert NotInPhase(CyclePhase.Normal, _currentPhase);
        if (block.number < _reviewWindowBlock) revert CycleNotExpired();
        _currentPhase = CyclePhase.ReviewWindow;
        emit ReviewWindowOpened(_currentCycle);
    }

    function approveMigration(uint256 panelId, address newProtocol) external nonReentrant {
        if (_currentPhase != CyclePhase.ReviewWindow) {
            revert NotInPhase(CyclePhase.ReviewWindow, _currentPhase);
        }
        if (newProtocol == address(0)) revert ZeroProtocolAddress();

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("migration", _currentCycle, newProtocol));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        _pendingMigration = true;
        _approvedNewProtocol = newProtocol;
        _approvalPanelId = panelId;
        _currentPhase = CyclePhase.Migration;

        emit MigrationApproved(_currentCycle, panelId, newProtocol);
    }

    /// @dev Requires a SEPARATE confirmation panel from the approval panel.
    ///      Emits MigrationExecuted for off-chain deployment infrastructure;
    ///      see contract-level NatSpec for why this is signaling-only.
    function executeMigration(uint256 panelId) external nonReentrant {
        if (_currentPhase != CyclePhase.Migration) revert NotInPhase(CyclePhase.Migration, _currentPhase);
        if (!_pendingMigration) revert NoMigrationPending();
        if (panelId == _approvalPanelId) revert SamePanelAsApproval(panelId);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("confirmMigration", _currentCycle, _approvedNewProtocol));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        address oldProtocol = address(this);
        address newProto = _approvedNewProtocol;

        _pendingMigration = false;
        _approvedNewProtocol = address(0);
        _approvalPanelId = 0;

        emit MigrationExecuted(_currentCycle, oldProtocol, newProto);
        _startNewCycle();
    }

    function renewCycle(uint256 panelId) external nonReentrant {
        if (_currentPhase != CyclePhase.ReviewWindow) {
            revert NotInPhase(CyclePhase.ReviewWindow, _currentPhase);
        }

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("renewCycle", _currentCycle));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        emit CycleRenewed(_currentCycle);
        _startNewCycle();
    }

    function currentCycle() external view returns (uint256) {
        return _currentCycle;
    }

    function currentPhase() external view returns (CyclePhase) {
        return _currentPhase;
    }

    function reviewWindowBlock() external view returns (uint256) {
        return _reviewWindowBlock;
    }

    function pendingMigration() external view returns (bool) {
        return _pendingMigration;
    }

    function approvedNewProtocol() external view returns (address) {
        return _approvedNewProtocol;
    }

    function _startNewCycle() internal {
        _currentCycle++;
        _currentPhase = CyclePhase.Normal;
        _reviewWindowBlock = block.number + params.decayPeriod();
        emit CycleStarted(_currentCycle, block.number, _reviewWindowBlock);
    }
}
