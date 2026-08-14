// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMetricRegistry} from "../interfaces/IMetricRegistry.sol";
import {ISortition} from "../interfaces/ISortition.sol";
import {IAudit} from "../interfaces/IAudit.sol";

contract MetricRegistry is IMetricRegistry {
    ISortition public immutable sortition;
    IAudit public immutable audit;
    uint256 public immutable decayPeriod;

    mapping(bytes32 => Metric) internal _metrics;
    mapping(bytes32 => bool) internal _exists;

    struct Proposal {
        uint256 panelId;
        bool submitted;
    }

    mapping(bytes32 => Proposal) internal _proposals;

    error MetricNotFound(bytes32 key);
    error MetricAlreadyExists(bytes32 key);
    error MetricExpiredError(bytes32 key);
    error PanelNotResolved(uint256 panelId);
    error PanelNotApproved(uint256 panelId);
    error NoProposalFound(bytes32 proposalHash);
    error WrongPanelPurpose();

    event ProposalSubmitted(bytes32 indexed proposalHash, uint256 panelId);

    constructor(address _sortition, address _audit, uint256 _decayPeriod) {
        require(_sortition != address(0), "MetricRegistry: zero sortition");
        require(_audit != address(0), "MetricRegistry: zero audit");
        require(_decayPeriod > 0, "MetricRegistry: zero decay period");
        sortition = ISortition(_sortition);
        audit = IAudit(_audit);
        decayPeriod = _decayPeriod;
    }

    function proposeCreate(bytes32 key, uint256 value, bytes32 oracleSource, uint256 panelId) external {
        bytes32 h = keccak256(abi.encode("create", key, value, oracleSource));
        _proposals[h] = Proposal(panelId, true);
        emit ProposalSubmitted(h, panelId);
    }

    function proposeUpdate(bytes32 key, uint256 newValue, uint256 panelId) external {
        bytes32 h = keccak256(abi.encode("update", key, newValue));
        _proposals[h] = Proposal(panelId, true);
        emit ProposalSubmitted(h, panelId);
    }

    function proposeReratify(bytes32 key, uint256 panelId) external {
        bytes32 h = keccak256(abi.encode("reratify", key));
        _proposals[h] = Proposal(panelId, true);
        emit ProposalSubmitted(h, panelId);
    }

    function _consumeProposal(bytes32 proposalHash) internal returns (uint256 panelId) {
        Proposal storage p = _proposals[proposalHash];
        if (!p.submitted) revert NoProposalFound(proposalHash);
        panelId = p.panelId;
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved) revert PanelNotResolved(panelId);
        if (!approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        if (panel.purpose != proposalHash) revert WrongPanelPurpose();

        delete _proposals[proposalHash];
    }

    function createMetric(bytes32 key, uint256 value, bytes32 oracleSource) external {
        bytes32 proposalHash = keccak256(abi.encode("create", key, value, oracleSource));
        _consumeProposal(proposalHash);

        if (_exists[key]) revert MetricAlreadyExists(key);

        uint256 deadline = block.number + decayPeriod;
        _metrics[key] = Metric({
            key: key,
            value: value,
            decayDeadline: deadline,
            lastUpdated: block.number,
            oracleSource: oracleSource
        });
        _exists[key] = true;

        emit MetricCreated(key, value, oracleSource, deadline);
    }

    function updateMetric(bytes32 key, uint256 newValue) external {
        if (!_exists[key]) revert MetricNotFound(key);

        bytes32 proposalHash = keccak256(abi.encode("update", key, newValue));
        uint256 panelId = _consumeProposal(proposalHash);

        Metric storage m = _metrics[key];
        uint256 oldValue = m.value;
        m.value = newValue;
        m.lastUpdated = block.number;
        m.decayDeadline = block.number + decayPeriod;

        emit MetricUpdated(key, oldValue, newValue, panelId);
    }

    function reratify(bytes32 key) external {
        if (!_exists[key]) revert MetricNotFound(key);

        bytes32 proposalHash = keccak256(abi.encode("reratify", key));
        _consumeProposal(proposalHash);

        Metric storage m = _metrics[key];
        uint256 newDeadline = block.number + decayPeriod;
        m.decayDeadline = newDeadline;
        m.lastUpdated = block.number;

        emit MetricReratified(key, newDeadline);
    }

    function fileDivergenceClaim(bytes32 key, bytes32 evidenceHash) external {
        if (!_exists[key]) revert MetricNotFound(key);

        uint256 stakeAmount = audit.minStake();
        uint256 claimId = audit.fileClaim(key, evidenceHash, stakeAmount);

        emit DivergenceClaimFiled(key, evidenceHash, claimId);
    }

    function escalateDivergence(uint256 claimId) external {
        IAudit.Claim memory claim = audit.getClaim(claimId);
        require(claim.resolution == IAudit.Resolution.Confirmed, "MetricRegistry: claim not confirmed");
        require(_exists[claim.target], "MetricRegistry: target not a metric");

        Metric storage m = _metrics[claim.target];
        m.decayDeadline = 0;

        emit DivergenceEscalated(claim.target, claimId);
    }

    function getMetric(bytes32 key) external view returns (uint256) {
        if (!_exists[key]) revert MetricNotFound(key);
        Metric storage m = _metrics[key];
        if (block.number > m.decayDeadline) {
            revert MetricExpiredError(key);
        }
        return m.value;
    }

    function isExpired(bytes32 key) external view returns (bool) {
        if (!_exists[key]) revert MetricNotFound(key);
        return block.number > _metrics[key].decayDeadline;
    }

    function getMetricRecord(bytes32 key) external view returns (Metric memory) {
        if (!_exists[key]) revert MetricNotFound(key);
        return _metrics[key];
    }
}
