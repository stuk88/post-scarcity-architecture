// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Levy} from "../../src/protocol/Levy.sol";
import {Credit} from "../../src/protocol/Credit.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {MockParameterStore} from "../mocks/Mocks.sol";

contract FuzzLevyTest is Test {
    Levy levyContract;
    Credit credit;
    MockParameterStore paramStore;

    address treasuryAddr = makeAddr("treasury");
    address oracleAddr = makeAddr("oracle");
    address auditAddr = makeAddr("audit");
    address metricRegistry = makeAddr("metricRegistry");
    address payer = makeAddr("payer");

    bytes32 constant ORG_ID = bytes32(uint256(42));
    uint256 constant DEFAULT_RATE = 500;

    function setUp() public {
        paramStore = new MockParameterStore();
        paramStore.setLevyRate(DEFAULT_RATE);

        address levyAddrPredicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        credit = new Credit(treasuryAddr, levyAddrPredicted, auditAddr, metricRegistry, 1e18);
        levyContract = new Levy(address(credit), treasuryAddr, address(paramStore), oracleAddr);

        vm.mockCall(treasuryAddr, abi.encodeWithSelector(ITreasury.collectLevy.selector), abi.encode());
    }

    function _setupPayer(uint256 levyAmount) internal {
        vm.prank(treasuryAddr);
        credit.mint(payer, levyAmount);

        vm.prank(payer);
        credit.approve(address(levyContract), levyAmount);
    }

    function testFuzz_levyCalculation(uint256 revenue) public {
        uint256 rate = paramStore.levyRate();
        revenue = bound(revenue, 1, type(uint256).max / rate);

        uint256 expectedLevy = revenue * rate / 10_000;
        vm.assume(expectedLevy > 0);

        _setupPayer(expectedLevy);

        vm.prank(payer);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(levyContract.periodTotal(), expectedLevy, "period total != expected levy");
        assertEq(levyContract.orgPeriodTotal(ORG_ID), expectedLevy, "org total != expected levy");
    }

    function testFuzz_levyBurnsCorrectly(uint256 revenue) public {
        uint256 rate = paramStore.levyRate();
        revenue = bound(revenue, 1, type(uint256).max / rate);

        uint256 expectedLevy = revenue * rate / 10_000;
        vm.assume(expectedLevy > 0);

        _setupPayer(expectedLevy);

        uint256 burnedBefore = credit.totalBurned();
        uint256 supplyBefore = credit.totalSupply();

        vm.prank(payer);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.totalBurned() - burnedBefore, expectedLevy, "burned delta != levy");
        assertEq(supplyBefore - credit.totalSupply(), expectedLevy, "supply delta != levy");
    }

    function testFuzz_levyWithVaryingRates(uint256 revenue, uint256 rate) public {
        rate = bound(rate, 1, 10_000);
        paramStore.setLevyRate(rate);

        revenue = bound(revenue, 1, type(uint256).max / rate);
        uint256 expectedLevy = revenue * rate / 10_000;
        vm.assume(expectedLevy > 0);

        _setupPayer(expectedLevy);

        vm.prank(payer);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.totalBurned(), expectedLevy, "burned != expected at varied rate");
        assertEq(levyContract.periodTotal(), expectedLevy, "period total wrong at varied rate");
    }

    function testFuzz_zeroLevyReverts(uint256 revenue) public {
        uint256 rate = paramStore.levyRate();
        revenue = bound(revenue, 0, (10_000 / rate) - 1);

        vm.prank(payer);
        vm.expectRevert("Levy: zero levy");
        levyContract.collectDigital(ORG_ID, revenue);
    }

    function testFuzz_levyPayerBalanceZeroAfter(uint256 revenue) public {
        uint256 rate = paramStore.levyRate();
        revenue = bound(revenue, 1, type(uint256).max / rate);

        uint256 expectedLevy = revenue * rate / 10_000;
        vm.assume(expectedLevy > 0);

        _setupPayer(expectedLevy);

        vm.prank(payer);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.balanceOf(payer), 0, "payer should have zero balance after exact levy");
    }
}
