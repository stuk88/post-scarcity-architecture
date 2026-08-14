// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RandomnessBeacon} from "../../src/protocol/RandomnessBeacon.sol";
import {IRandomnessBeacon} from "../../src/interfaces/IRandomnessBeacon.sol";

contract RandomnessBeaconTest is Test {
    RandomnessBeacon public beacon;

    address public vrfProvider = makeAddr("vrfProvider");
    address public requester = makeAddr("requester");
    address public nobody = makeAddr("nobody");

    function setUp() public {
        beacon = new RandomnessBeacon(vrfProvider);
    }

    function test_constructor_setsProvider() public view {
        assertEq(beacon.vrfProvider(), vrfProvider);
    }

    function test_constructor_revertsZeroProvider() public {
        vm.expectRevert("RandomnessBeacon: zero provider");
        new RandomnessBeacon(address(0));
    }

    function test_requestSeed_recordsRequestAndBlock() public {
        vm.roll(42);
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        assertEq(requestId, 1);
        assertEq(beacon.requestBlock(requestId), 42);
        assertFalse(beacon.isFulfilled(requestId));
    }

    function test_requestSeed_incrementsIds() public {
        vm.prank(requester);
        uint256 id1 = beacon.requestSeed();
        vm.prank(requester);
        uint256 id2 = beacon.requestSeed();

        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_requestSeed_emitsEvent() public {
        vm.prank(requester);
        vm.expectEmit(true, true, false, false);
        emit IRandomnessBeacon.SeedRequested(1, requester);
        beacon.requestSeed();
    }

    function test_fulfillSeed_storesSeed() public {
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        vm.prank(vrfProvider);
        beacon.fulfillSeed(requestId, 12345);

        assertTrue(beacon.isFulfilled(requestId));
        assertEq(beacon.getSeed(requestId), 12345);
    }

    function test_fulfillSeed_emitsEvent() public {
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        vm.prank(vrfProvider);
        vm.expectEmit(true, false, false, true);
        emit IRandomnessBeacon.SeedFulfilled(requestId, 99999);
        beacon.fulfillSeed(requestId, 99999);
    }

    function test_fulfillSeed_revertsIfNotProvider() public {
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        vm.prank(nobody);
        vm.expectRevert("RandomnessBeacon: caller is not VRF provider");
        beacon.fulfillSeed(requestId, 12345);
    }

    function test_fulfillSeed_revertsIfRequestDoesNotExist() public {
        vm.prank(vrfProvider);
        vm.expectRevert("RandomnessBeacon: request does not exist");
        beacon.fulfillSeed(999, 12345);
    }

    function test_fulfillSeed_revertsIfAlreadyFulfilled() public {
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        vm.prank(vrfProvider);
        beacon.fulfillSeed(requestId, 12345);

        vm.prank(vrfProvider);
        vm.expectRevert("RandomnessBeacon: already fulfilled");
        beacon.fulfillSeed(requestId, 67890);
    }

    function test_getSeed_revertsIfNotFulfilled() public {
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        vm.expectRevert("RandomnessBeacon: not fulfilled");
        beacon.getSeed(requestId);
    }

    function test_seedNotKnowableAtRequest() public {
        vm.roll(100);
        vm.prank(requester);
        uint256 requestId = beacon.requestSeed();

        assertFalse(beacon.isFulfilled(requestId));
        assertEq(beacon.requestBlock(requestId), 100);

        vm.roll(110);
        vm.prank(vrfProvider);
        beacon.fulfillSeed(requestId, 42);

        assertTrue(beacon.isFulfilled(requestId));
        assertEq(beacon.getSeed(requestId), 42);
    }
}
