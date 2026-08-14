// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEmergency} from "../interfaces/IEmergency.sol";
import {ISortition} from "../interfaces/ISortition.sol";
import {IMetricRegistry} from "../interfaces/IMetricRegistry.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";

contract Emergency is IEmergency {
    ISortition public immutable sortition;
    IMetricRegistry public immutable metricRegistry;
    IParameterStore public immutable params;

    bool internal _initialized;
    mapping(bytes32 => Trigger) internal _triggers;
    mapping(bytes32 => bool) internal _triggerExists;
    mapping(bytes32 => mapping(uint256 => bool)) internal _usedPanels;

    struct ScarcityBreaker {
        bool active;
        uint256 priceChannel;
        uint256 activatedAt;
    }

    mapping(bytes32 => ScarcityBreaker) internal _scarcityBreakers;

    error TriggerNotFound(bytes32 triggerId);
    error TriggerNotInactive(bytes32 triggerId);
    error TriggerNotActive(bytes32 triggerId);
    error ThresholdNotCrossed(bytes32 triggerId, uint256 value, uint256 threshold);
    error TriggerNotExpired(bytes32 triggerId);
    error PanelNotApproved(uint256 panelId);
    error PanelNotRejected(uint256 panelId);
    error PanelAlreadyUsed(bytes32 triggerId, uint256 panelId);
    error WrongPanelPurpose();
    error AlreadyInitialized();
    error TriggerAlreadyExists(bytes32 triggerId);
    error ScarcityBreakerAlreadyActive(bytes32 goodId);
    error ScarcityBreakerNotActive(bytes32 goodId);
    error NotDeployer();

    address internal immutable _deployer;

    constructor(address _sortition, address _metricRegistry, address _params) {
        require(_sortition != address(0), "Emergency: zero sortition");
        require(_metricRegistry != address(0), "Emergency: zero metricRegistry");
        require(_params != address(0), "Emergency: zero params");

        sortition = ISortition(_sortition);
        metricRegistry = IMetricRegistry(_metricRegistry);
        params = IParameterStore(_params);
        _deployer = msg.sender;
    }

    function registerTrigger(
        bytes32 triggerId,
        bytes32 metricKey,
        uint256 threshold,
        bytes32 responseAction,
        uint256 duration
    ) external {
        if (msg.sender != _deployer) revert NotDeployer();
        if (_initialized) revert AlreadyInitialized();
        if (_triggerExists[triggerId]) revert TriggerAlreadyExists(triggerId);

        _triggers[triggerId] = Trigger({
            triggerId: triggerId,
            metricKey: metricKey,
            threshold: threshold,
            responseAction: responseAction,
            duration: duration,
            activatedAt: 0,
            state: TriggerState.Inactive
        });
        _triggerExists[triggerId] = true;

        emit TriggerRegistered(triggerId, metricKey, threshold, duration);
    }

    function finalizeSetup() external {
        if (msg.sender != _deployer) revert NotDeployer();
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
    }

    function activate(bytes32 triggerId) external {
        if (!_triggerExists[triggerId]) revert TriggerNotFound(triggerId);
        Trigger storage t = _triggers[triggerId];
        if (t.state != TriggerState.Inactive) revert TriggerNotInactive(triggerId);

        uint256 value = metricRegistry.getMetric(t.metricKey);
        if (value < t.threshold) revert ThresholdNotCrossed(triggerId, value, t.threshold);

        t.state = TriggerState.Active;
        t.activatedAt = block.number;

        emit TriggerActivated(triggerId, block.number, block.number + t.duration);
    }

    function checkExpiry(bytes32 triggerId) external {
        if (!_triggerExists[triggerId]) revert TriggerNotFound(triggerId);
        Trigger storage t = _triggers[triggerId];
        if (t.state != TriggerState.Active) revert TriggerNotActive(triggerId);
        if (block.number < t.activatedAt + t.duration) revert TriggerNotExpired(triggerId);

        t.state = TriggerState.Expired;
        emit TriggerExpired(triggerId);
    }

    function renew(bytes32 triggerId, uint256 panelId) external {
        if (!_triggerExists[triggerId]) revert TriggerNotFound(triggerId);
        Trigger storage t = _triggers[triggerId];
        if (t.state != TriggerState.Active) revert TriggerNotActive(triggerId);
        if (_usedPanels[triggerId][panelId]) revert PanelAlreadyUsed(triggerId, panelId);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("emergency.renew", triggerId));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        _usedPanels[triggerId][panelId] = true;
        t.activatedAt = block.number;

        emit TriggerRenewed(triggerId, panelId, block.number + t.duration);
    }

    function terminateEarly(bytes32 triggerId, uint256 panelId) external {
        if (!_triggerExists[triggerId]) revert TriggerNotFound(triggerId);
        Trigger storage t = _triggers[triggerId];
        if (t.state != TriggerState.Active) revert TriggerNotActive(triggerId);

        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || approved) revert PanelNotRejected(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("emergency.terminate", triggerId));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        t.state = TriggerState.Inactive;
        emit TriggerTerminated(triggerId, panelId);
    }

    function activateScarcityBreaker(bytes32 goodId, uint256 priceChannel, uint256 panelId) external {
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("scarcityBreaker.activate", goodId));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        if (_scarcityBreakers[goodId].active) revert ScarcityBreakerAlreadyActive(goodId);
        _scarcityBreakers[goodId] = ScarcityBreaker({active: true, priceChannel: priceChannel, activatedAt: block.number});
        emit ScarcityBreakerActivated(goodId, priceChannel);
    }

    function deactivateScarcityBreaker(bytes32 goodId, uint256 panelId) external {
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved || !approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("scarcityBreaker.deactivate", goodId));
        if (panel.purpose != expectedPurpose) revert WrongPanelPurpose();

        if (!_scarcityBreakers[goodId].active) revert ScarcityBreakerNotActive(goodId);
        _scarcityBreakers[goodId].active = false;
        emit ScarcityBreakerDeactivated(goodId);
    }

    function isActive(bytes32 triggerId) external view returns (bool) {
        if (!_triggerExists[triggerId]) return false;
        Trigger storage t = _triggers[triggerId];
        if (t.state != TriggerState.Active) return false;
        return block.number < t.activatedAt + t.duration;
    }

    function getTrigger(bytes32 triggerId) external view returns (Trigger memory) {
        return _triggers[triggerId];
    }

    function isScarcityBreakerActive(bytes32 goodId) external view returns (bool) {
        return _scarcityBreakers[goodId].active;
    }
}
