// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CappedGradient} from "../../src/protocol/CappedGradient.sol";
import {MockParameterStore} from "../mocks/Mocks.sol";

contract InvariantGradientTest is Test {
    CappedGradient gradient;
    MockParameterStore paramStore;

    function setUp() public {
        paramStore = new MockParameterStore();
        paramStore.setGradientFloor(1e18);
        paramStore.setGradientCeiling(10e18);
        gradient = new CappedGradient(address(paramStore));
    }

    function testFuzz_clampAlwaysInBounds(uint256 x) public view {
        uint256 result = gradient.clamp(x);
        uint256 f = gradient.floor();
        uint256 c = gradient.ceiling();
        assertGe(result, f, "clamp below floor");
        assertLe(result, c, "clamp above ceiling");
    }

    function testFuzz_clampIdentityInRange(uint256 x) public view {
        uint256 f = gradient.floor();
        uint256 c = gradient.ceiling();
        x = bound(x, f, c);
        assertEq(gradient.clamp(x), x, "clamp changed value within range");
    }

    function testFuzz_clampWithVaryingBounds(uint256 floorVal, uint256 ceilVal, uint256 x) public {
        floorVal = bound(floorVal, 1, 1e30);
        ceilVal = bound(ceilVal, floorVal, floorVal + 1e30);

        paramStore.setGradientFloor(floorVal);
        paramStore.setGradientCeiling(ceilVal);

        uint256 result = gradient.clamp(x);
        assertGe(result, floorVal, "clamp below dynamic floor");
        assertLe(result, ceilVal, "clamp above dynamic ceiling");
    }

    function testFuzz_clampBelowFloorReturnsFloor(uint256 floorVal, uint256 ceilVal, uint256 x) public {
        floorVal = bound(floorVal, 1, 1e30);
        ceilVal = bound(ceilVal, floorVal, floorVal + 1e30);
        x = bound(x, 0, floorVal - 1);

        paramStore.setGradientFloor(floorVal);
        paramStore.setGradientCeiling(ceilVal);

        assertEq(gradient.clamp(x), floorVal, "below-floor not clamped to floor");
    }

    function testFuzz_clampAboveCeilingReturnsCeiling(uint256 floorVal, uint256 ceilVal, uint256 x) public {
        floorVal = bound(floorVal, 1, 1e30);
        ceilVal = bound(ceilVal, floorVal, floorVal + 1e30);
        vm.assume(ceilVal < type(uint256).max);
        x = bound(x, ceilVal + 1, type(uint256).max);

        paramStore.setGradientFloor(floorVal);
        paramStore.setGradientCeiling(ceilVal);

        assertEq(gradient.clamp(x), ceilVal, "above-ceiling not clamped to ceiling");
    }
}
