// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Reputation} from "../../src/protocol/Reputation.sol";

contract ReputationTest is Test {
    Reputation public rep;

    address public governance = makeAddr("governance");
    address public completionRegistry = makeAddr("completionRegistry");
    address public audit = makeAddr("audit");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public constant PERSON_A = keccak256("personA");
    bytes32 public constant PERSON_B = keccak256("personB");

    function setUp() public {
        rep = new Reputation(governance);

        vm.startPrank(governance);
        rep.authorize(completionRegistry);
        rep.authorize(audit);
        vm.stopPrank();
    }

    function test_constructor_setsGovernance() public view {
        assertEq(rep.governance(), governance);
    }

    function test_constructor_setsDefaultWeights() public view {
        assertEq(rep.getWeight("accuracy"), 0.3e18);
        assertEq(rep.getWeight("volume"), 0.2e18);
        assertEq(rep.getWeight("novelty"), 0.2e18);
        assertEq(rep.getWeight("reliability"), 0.3e18);
    }

    function test_constructor_revertsOnZeroGovernance() public {
        vm.expectRevert("Reputation: zero governance");
        new Reputation(address(0));
    }

    function test_authorize_setsCallerAuthorized() public {
        address newCaller = makeAddr("newCaller");
        vm.prank(governance);
        rep.authorize(newCaller);
        assertTrue(rep.isAuthorized(newCaller));
    }

    function test_authorize_revertsOnZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert("Reputation: zero address");
        rep.authorize(address(0));
    }

    function test_authorize_revertsWhenNotGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert("Reputation: caller is not governance");
        rep.authorize(makeAddr("x"));
    }

    function test_deauthorize_removesAuthorization() public {
        vm.prank(governance);
        rep.deauthorize(completionRegistry);
        assertFalse(rep.isAuthorized(completionRegistry));
    }

    function test_updateDimension_incrementsAccuracy() public {
        vm.prank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(10));

        assertEq(rep.getDimension(PERSON_A, "accuracy"), 10);
    }

    function test_updateDimension_incrementsVolume() public {
        vm.prank(completionRegistry);
        rep.updateDimension(PERSON_A, "volume", int256(5));

        assertEq(rep.getDimension(PERSON_A, "volume"), 5);
    }

    function test_updateDimension_incrementsNovelty() public {
        vm.prank(completionRegistry);
        rep.updateDimension(PERSON_A, "novelty", int256(3));

        assertEq(rep.getDimension(PERSON_A, "novelty"), 3);
    }

    function test_updateDimension_incrementsReliability() public {
        vm.prank(completionRegistry);
        rep.updateDimension(PERSON_A, "reliability", int256(7));

        assertEq(rep.getDimension(PERSON_A, "reliability"), 7);
    }

    function test_updateDimension_decrementsWithFloorAtZero() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(5));
        rep.updateDimension(PERSON_A, "accuracy", -int256(10));
        vm.stopPrank();

        assertEq(rep.getDimension(PERSON_A, "accuracy"), 0);
    }

    function test_updateDimension_decrementsPartially() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(10));
        rep.updateDimension(PERSON_A, "accuracy", -int256(3));
        vm.stopPrank();

        assertEq(rep.getDimension(PERSON_A, "accuracy"), 7);
    }

    function test_updateDimension_revertsOnUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert("Reputation: caller not authorized");
        rep.updateDimension(PERSON_A, "accuracy", int256(1));
    }

    function test_updateDimension_revertsOnZeroPersonId() public {
        vm.prank(completionRegistry);
        vm.expectRevert("Reputation: zero personId");
        rep.updateDimension(bytes32(0), "accuracy", int256(1));
    }

    function test_updateDimension_revertsOnInvalidDimension() public {
        vm.prank(completionRegistry);
        vm.expectRevert("Reputation: invalid dimension");
        rep.updateDimension(PERSON_A, "invalid", int256(1));
    }

    function test_getScore_returnsAllDimensions() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(10));
        rep.updateDimension(PERSON_A, "volume", int256(20));
        rep.updateDimension(PERSON_A, "novelty", int256(30));
        rep.updateDimension(PERSON_A, "reliability", int256(40));
        vm.stopPrank();

        Reputation.Score memory s = rep.getScore(PERSON_A);
        assertEq(s.accuracy, 10);
        assertEq(s.volume, 20);
        assertEq(s.novelty, 30);
        assertEq(s.reliability, 40);
    }

    function test_compositeScore_calculatesWeightedSum() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(10));
        rep.updateDimension(PERSON_A, "volume", int256(20));
        rep.updateDimension(PERSON_A, "novelty", int256(30));
        rep.updateDimension(PERSON_A, "reliability", int256(40));
        vm.stopPrank();

        uint256 expected = (10 * 0.3e18 + 20 * 0.2e18 + 30 * 0.2e18 + 40 * 0.3e18) / 1e18;
        assertEq(rep.compositeScore(PERSON_A), expected);
    }

    function test_setWeight_updatesWeight() public {
        vm.prank(governance);
        rep.setWeight("accuracy", 0.5e18);
        assertEq(rep.getWeight("accuracy"), 0.5e18);
    }

    function test_setWeight_revertsOnInvalidDimension() public {
        vm.prank(governance);
        vm.expectRevert("Reputation: invalid dimension");
        rep.setWeight("invalid", 0.5e18);
    }

    function test_setWeight_revertsWhenNotGovernance() public {
        vm.prank(unauthorized);
        vm.expectRevert("Reputation: caller is not governance");
        rep.setWeight("accuracy", 0.5e18);
    }

    function test_invariant_noTransferFunction() public pure {
        bytes4 transferSel = bytes4(keccak256("transfer(bytes32,bytes32)"));
        bytes4 transferFromSel = bytes4(keccak256("transferFrom(bytes32,bytes32,bytes32)"));

        bytes4[] memory knownSelectors = new bytes4[](8);
        knownSelectors[0] = Reputation.authorize.selector;
        knownSelectors[1] = Reputation.deauthorize.selector;
        knownSelectors[2] = Reputation.isAuthorized.selector;
        knownSelectors[3] = Reputation.updateDimension.selector;
        knownSelectors[4] = Reputation.getScore.selector;
        knownSelectors[5] = Reputation.getDimension.selector;
        knownSelectors[6] = Reputation.compositeScore.selector;
        knownSelectors[7] = Reputation.setWeight.selector;

        for (uint256 i = 0; i < knownSelectors.length; i++) {
            assertTrue(knownSelectors[i] != transferSel, "transfer function found");
            assertTrue(knownSelectors[i] != transferFromSel, "transferFrom function found");
        }
    }

    function test_invariant_scoresAreSoulbound() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(100));
        vm.stopPrank();

        assertEq(rep.getDimension(PERSON_A, "accuracy"), 100);
        assertEq(rep.getDimension(PERSON_B, "accuracy"), 0);
    }

    function test_updateDimension_isolatesPersonScores() public {
        vm.startPrank(completionRegistry);
        rep.updateDimension(PERSON_A, "accuracy", int256(50));
        rep.updateDimension(PERSON_B, "accuracy", int256(25));
        vm.stopPrank();

        assertEq(rep.getDimension(PERSON_A, "accuracy"), 50);
        assertEq(rep.getDimension(PERSON_B, "accuracy"), 25);
    }
}
