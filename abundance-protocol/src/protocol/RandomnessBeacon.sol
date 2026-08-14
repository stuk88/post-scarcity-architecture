// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRandomnessBeacon} from "../interfaces/IRandomnessBeacon.sol";

contract RandomnessBeacon is IRandomnessBeacon {
    address public immutable vrfProvider;

    struct SeedRequest {
        address requester;
        uint256 requestedAtBlock;
        uint256 seed;
        bool fulfilled;
    }

    uint256 private _nextRequestId = 1;
    mapping(uint256 => SeedRequest) private _requests;

    constructor(address vrfProvider_) {
        require(vrfProvider_ != address(0), "RandomnessBeacon: zero provider");
        vrfProvider = vrfProvider_;
    }

    function requestSeed() external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        _requests[requestId] = SeedRequest({
            requester: msg.sender,
            requestedAtBlock: block.number,
            seed: 0,
            fulfilled: false
        });
        emit SeedRequested(requestId, msg.sender);
    }

    function fulfillSeed(uint256 requestId, uint256 seed) external {
        require(msg.sender == vrfProvider, "RandomnessBeacon: caller is not VRF provider");
        SeedRequest storage req = _requests[requestId];
        require(req.requestedAtBlock > 0, "RandomnessBeacon: request does not exist");
        require(!req.fulfilled, "RandomnessBeacon: already fulfilled");
        req.seed = seed;
        req.fulfilled = true;
        emit SeedFulfilled(requestId, seed);
    }

    function getSeed(uint256 requestId) external view returns (uint256) {
        require(_requests[requestId].fulfilled, "RandomnessBeacon: not fulfilled");
        return _requests[requestId].seed;
    }

    function isFulfilled(uint256 requestId) external view returns (bool) {
        return _requests[requestId].fulfilled;
    }

    function requestBlock(uint256 requestId) external view returns (uint256) {
        return _requests[requestId].requestedAtBlock;
    }
}
