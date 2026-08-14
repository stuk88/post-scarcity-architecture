// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReputation} from "../interfaces/IReputation.sol";

contract Reputation is IReputation {
    address public immutable governance;
    mapping(address => bool) private _authorizedCallers;
    mapping(bytes32 => Score) private _scores;
    mapping(bytes32 => uint256) private _weights;

    bytes32 public constant DIM_ACCURACY = "accuracy";
    bytes32 public constant DIM_VOLUME = "volume";
    bytes32 public constant DIM_NOVELTY = "novelty";
    bytes32 public constant DIM_RELIABILITY = "reliability";

    event CallerAuthorized(address indexed caller);
    event CallerDeauthorized(address indexed caller);
    event WeightUpdated(bytes32 indexed dimension, uint256 newWeight);

    modifier onlyAuthorized() {
        require(_authorizedCallers[msg.sender], "Reputation: caller not authorized");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "Reputation: caller is not governance");
        _;
    }

    constructor(address governance_) {
        require(governance_ != address(0), "Reputation: zero governance");

        governance = governance_;

        _weights[DIM_ACCURACY] = 0.3e18;
        _weights[DIM_VOLUME] = 0.2e18;
        _weights[DIM_NOVELTY] = 0.2e18;
        _weights[DIM_RELIABILITY] = 0.3e18;
    }

    function setWeight(bytes32 dimension, uint256 weight) external onlyGovernance {
        require(
            dimension == DIM_ACCURACY || dimension == DIM_VOLUME || dimension == DIM_NOVELTY
                || dimension == DIM_RELIABILITY,
            "Reputation: invalid dimension"
        );
        _weights[dimension] = weight;
        emit WeightUpdated(dimension, weight);
    }

    function getWeight(bytes32 dimension) external view returns (uint256) {
        return _weights[dimension];
    }

    function authorize(address caller) external onlyGovernance {
        require(caller != address(0), "Reputation: zero address");
        _authorizedCallers[caller] = true;
        emit CallerAuthorized(caller);
    }

    function deauthorize(address caller) external onlyGovernance {
        _authorizedCallers[caller] = false;
        emit CallerDeauthorized(caller);
    }

    function isAuthorized(address caller) external view returns (bool) {
        return _authorizedCallers[caller];
    }

    function updateDimension(bytes32 personId, bytes32 dimension, int256 delta) external onlyAuthorized {
        require(personId != bytes32(0), "Reputation: zero personId");
        require(
            dimension == DIM_ACCURACY || dimension == DIM_VOLUME || dimension == DIM_NOVELTY
                || dimension == DIM_RELIABILITY,
            "Reputation: invalid dimension"
        );

        Score storage s = _scores[personId];
        uint256 current = _getDimension(s, dimension);
        uint256 newValue;

        if (delta < 0) {
            uint256 absDelta = uint256(-delta);
            newValue = current > absDelta ? current - absDelta : 0;
        } else {
            newValue = current + uint256(delta);
        }

        _setDimension(s, dimension, newValue);

        emit DimensionUpdated(personId, dimension, delta, newValue);
    }

    function getScore(bytes32 personId) external view returns (Score memory) {
        return _scores[personId];
    }

    function getDimension(bytes32 personId, bytes32 dimension) external view returns (uint256) {
        return _getDimension(_scores[personId], dimension);
    }

    function compositeScore(bytes32 personId) external view returns (uint256) {
        Score storage s = _scores[personId];

        return (
            s.accuracy * _weights[DIM_ACCURACY] + s.volume * _weights[DIM_VOLUME]
                + s.novelty * _weights[DIM_NOVELTY] + s.reliability * _weights[DIM_RELIABILITY]
        ) / 1e18;
    }

    function _getDimension(Score storage s, bytes32 dimension) private view returns (uint256) {
        if (dimension == DIM_ACCURACY) return s.accuracy;
        if (dimension == DIM_VOLUME) return s.volume;
        if (dimension == DIM_NOVELTY) return s.novelty;
        if (dimension == DIM_RELIABILITY) return s.reliability;
        return 0;
    }

    function _setDimension(Score storage s, bytes32 dimension, uint256 value) private {
        if (dimension == DIM_ACCURACY) s.accuracy = value;
        else if (dimension == DIM_VOLUME) s.volume = value;
        else if (dimension == DIM_NOVELTY) s.novelty = value;
        else if (dimension == DIM_RELIABILITY) s.reliability = value;
    }
}
