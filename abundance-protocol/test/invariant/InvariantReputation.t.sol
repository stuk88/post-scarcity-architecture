// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Reputation} from "../../src/protocol/Reputation.sol";

contract ReputationHandler is StdUtils {
    Reputation public reputation;

    bytes32[4] public dims;
    bytes32[] public trackedPersons;
    mapping(bytes32 => bool) public isTracked;
    mapping(bytes32 => mapping(bytes32 => uint256)) public ghost;
    mapping(bytes32 => uint256) public ghostPositiveSum;

    constructor(Reputation _reputation) {
        reputation = _reputation;
        dims[0] = "accuracy";
        dims[1] = "volume";
        dims[2] = "novelty";
        dims[3] = "reliability";
    }

    function updateDimension(uint256 personSeed, uint256 dimSeed, uint256 deltaSeed) external {
        bytes32 personId = bytes32(_bound(personSeed, 1, 50));
        uint8 dimIdx = uint8(_bound(dimSeed, 0, 3));
        bytes32 dim = dims[dimIdx];

        int256 delta;
        if (deltaSeed % 2 == 0) {
            delta = int256(_bound(deltaSeed >> 1, 0, 1e18));
        } else {
            delta = -int256(_bound(deltaSeed >> 1, 0, 1e18));
        }

        if (!isTracked[personId]) {
            isTracked[personId] = true;
            trackedPersons.push(personId);
        }

        uint256 current = ghost[personId][dim];
        uint256 newValue;
        if (delta < 0) {
            uint256 absDelta = uint256(-delta);
            newValue = current > absDelta ? current - absDelta : 0;
        } else {
            newValue = current + uint256(delta);
            ghostPositiveSum[personId] += uint256(delta);
        }
        ghost[personId][dim] = newValue;

        reputation.updateDimension(personId, dim, delta);
    }

    function trackedCount() external view returns (uint256) {
        return trackedPersons.length;
    }

    function getGhost(bytes32 personId, bytes32 dim) external view returns (uint256) {
        return ghost[personId][dim];
    }
}

contract InvariantReputationTest is Test {
    Reputation reputation;
    ReputationHandler handler;
    address governance = makeAddr("governance");

    bytes32[4] dims;

    function setUp() public {
        reputation = new Reputation(governance);

        address handlerAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.prank(governance);
        reputation.authorize(handlerAddr);

        handler = new ReputationHandler(reputation);

        dims[0] = "accuracy";
        dims[1] = "volume";
        dims[2] = "novelty";
        dims[3] = "reliability";

        targetContract(address(handler));
    }

    function invariant_neverNegative() public view {
        uint256 count = handler.trackedCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 personId = handler.trackedPersons(i);
            uint256 maxPossible = handler.ghostPositiveSum(personId);
            for (uint256 d = 0; d < 4; d++) {
                uint256 val = reputation.getDimension(personId, dims[d]);
                assertLe(val, maxPossible, "dimension exceeds sum of positive deltas (underflow wrap?)");
            }
        }
    }

    function invariant_scoresIsolated() public view {
        uint256 count = handler.trackedCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 personId = handler.trackedPersons(i);
            for (uint256 d = 0; d < 4; d++) {
                bytes32 dim = dims[d];
                uint256 actual = reputation.getDimension(personId, dim);
                uint256 expected = handler.getGhost(personId, dim);
                assertEq(actual, expected, "score mismatch: cross-contamination detected");
            }
        }
    }

    function invariant_compositeScoreConsistent() public view {
        uint256 count = handler.trackedCount();
        for (uint256 i = 0; i < count; i++) {
            bytes32 personId = handler.trackedPersons(i);
            uint256 composite = reputation.compositeScore(personId);
            uint256 acc = reputation.getDimension(personId, "accuracy");
            uint256 vol = reputation.getDimension(personId, "volume");
            uint256 nov = reputation.getDimension(personId, "novelty");
            uint256 rel = reputation.getDimension(personId, "reliability");
            uint256 expected = (
                acc * 0.3e18 + vol * 0.2e18 + nov * 0.2e18 + rel * 0.3e18
            ) / 1e18;
            assertEq(composite, expected, "composite score mismatch");
        }
    }
}
