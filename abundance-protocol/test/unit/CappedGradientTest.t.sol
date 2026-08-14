// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CappedGradient} from "../../src/protocol/CappedGradient.sol";
import {MockParameterStore} from "../mocks/Mocks.sol";

contract CappedGradientTest is Test {
    CappedGradient gradient;
    MockParameterStore paramStore;

    uint256 constant FLOOR = 1e18;
    uint256 constant CEILING = 10e18;

    function setUp() public {
        paramStore = new MockParameterStore();
        paramStore.setGradientFloor(FLOOR);
        paramStore.setGradientCeiling(CEILING);
        gradient = new CappedGradient(address(paramStore));
    }

    // ── Clamp ──

    function test_ClampBelowFloor() public view {
        uint256 result = gradient.clamp(0.5e18);
        assertEq(result, FLOOR);
    }

    function test_ClampAboveCeiling() public view {
        uint256 result = gradient.clamp(50e18);
        assertEq(result, CEILING);
    }

    function test_ClampInRange() public view {
        uint256 result = gradient.clamp(5e18);
        assertEq(result, 5e18);
    }

    function test_ClampAtFloor() public view {
        uint256 result = gradient.clamp(FLOOR);
        assertEq(result, FLOOR);
    }

    function test_ClampAtCeiling() public view {
        uint256 result = gradient.clamp(CEILING);
        assertEq(result, CEILING);
    }

    function test_ClampZeroReturnFloor() public view {
        uint256 result = gradient.clamp(0);
        assertEq(result, FLOOR);
    }

    function test_ClampAlwaysWithinBounds(uint256 rawAmount) public view {
        uint256 result = gradient.clamp(rawAmount);
        assertGe(result, FLOOR);
        assertLe(result, CEILING);
    }

    // ── Views ──

    function test_FloorReturnsParameterStoreValue() public view {
        assertEq(gradient.floor(), FLOOR);
    }

    function test_CeilingReturnsParameterStoreValue() public view {
        assertEq(gradient.ceiling(), CEILING);
    }

    function test_Ratio() public view {
        assertEq(gradient.ratio(), CEILING / FLOOR);
        assertEq(gradient.ratio(), 10);
    }

    function test_RatioRevertsOnZeroFloor() public {
        paramStore.setGradientFloor(0);
        vm.expectRevert("CappedGradient: zero floor");
        gradient.ratio();
    }

    // ── Dynamic Parameters ──

    function test_ClampReflectsUpdatedBounds() public {
        paramStore.setGradientFloor(2e18);
        paramStore.setGradientCeiling(5e18);

        assertEq(gradient.clamp(1e18), 2e18);
        assertEq(gradient.clamp(3e18), 3e18);
        assertEq(gradient.clamp(8e18), 5e18);
    }

    // ── Constructor ──

    function test_ConstructorRevertsZeroStore() public {
        vm.expectRevert("CappedGradient: zero store");
        new CappedGradient(address(0));
    }
}
