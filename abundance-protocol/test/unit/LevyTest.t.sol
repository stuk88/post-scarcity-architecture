// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Levy} from "../../src/protocol/Levy.sol";
import {Credit} from "../../src/protocol/Credit.sol";
import {ILevy} from "../../src/interfaces/ILevy.sol";
import {ICredit} from "../../src/interfaces/ICredit.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {IParameterStore} from "../../src/interfaces/IParameterStore.sol";
import {MockParameterStore} from "../mocks/Mocks.sol";

contract LevyTest is Test {
    Levy levyContract;
    Credit credit;
    MockParameterStore paramStore;

    address treasuryAddr = makeAddr("treasury");
    address oracleAddr = makeAddr("oracle");
    address org = makeAddr("org");
    address auditAddr = makeAddr("audit");
    address metricRegistry = makeAddr("metricRegistry");

    bytes32 constant ORG_ID = bytes32(uint256(42));
    uint256 constant LEVY_RATE = 500;

    function setUp() public {
        paramStore = new MockParameterStore();
        paramStore.setLevyRate(LEVY_RATE);

        address levyAddrPredicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        credit = new Credit(treasuryAddr, levyAddrPredicted, auditAddr, metricRegistry, 1e18);

        levyContract = new Levy(address(credit), treasuryAddr, address(paramStore), oracleAddr);

        vm.mockCall(treasuryAddr, abi.encodeWithSelector(ITreasury.collectLevy.selector), abi.encode());
    }

    // ── collectDigital ──

    function test_CollectDigital() public {
        uint256 revenue = 10_000e18;
        uint256 expectedLevy = revenue * LEVY_RATE / 10_000;

        vm.prank(treasuryAddr);
        credit.mint(org, expectedLevy);

        vm.prank(org);
        credit.approve(address(levyContract), expectedLevy);

        vm.prank(org);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.balanceOf(org), 0);
        assertEq(credit.totalBurned(), expectedLevy);
        assertEq(levyContract.periodTotal(), expectedLevy);
        assertEq(levyContract.orgPeriodTotal(ORG_ID), expectedLevy);
    }

    function test_CollectDigitalBurnPath() public {
        uint256 revenue = 20_000e18;
        uint256 expectedLevy = revenue * LEVY_RATE / 10_000;

        vm.prank(treasuryAddr);
        credit.mint(org, expectedLevy);

        uint256 supplyBefore = credit.totalSupply();

        vm.prank(org);
        credit.approve(address(levyContract), expectedLevy);

        vm.prank(org);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.totalSupply(), supplyBefore - expectedLevy);
    }

    function test_CollectDigitalRevertsZeroLevy() public {
        vm.prank(org);
        vm.expectRevert("Levy: zero levy");
        levyContract.collectDigital(ORG_ID, 0);
    }

    function test_CollectDigitalRevertsInsufficientBalance() public {
        uint256 revenue = 10_000e18;

        vm.prank(org);
        credit.approve(address(levyContract), type(uint256).max);

        vm.prank(org);
        vm.expectRevert();
        levyContract.collectDigital(ORG_ID, revenue);
    }

    function test_CollectDigitalEmitsEvent() public {
        uint256 revenue = 10_000e18;
        uint256 expectedLevy = revenue * LEVY_RATE / 10_000;

        vm.prank(treasuryAddr);
        credit.mint(org, expectedLevy);

        vm.prank(org);
        credit.approve(address(levyContract), expectedLevy);

        vm.expectEmit(true, false, false, true);
        emit ILevy.DigitalLevyCollected(ORG_ID, revenue, expectedLevy);

        vm.prank(org);
        levyContract.collectDigital(ORG_ID, revenue);
    }

    // ── collectPhysical ──

    function test_CollectPhysical() public {
        uint256 attested = 5_000e18;
        uint256 expectedLevy = attested * LEVY_RATE / 10_000;
        bytes32 proof = bytes32(uint256(0xBEEF));

        vm.prank(treasuryAddr);
        credit.mint(oracleAddr, expectedLevy);

        vm.prank(oracleAddr);
        credit.approve(address(levyContract), expectedLevy);

        vm.prank(oracleAddr);
        levyContract.collectPhysical(ORG_ID, attested, proof);

        assertEq(credit.totalBurned(), expectedLevy);
        assertEq(levyContract.periodTotal(), expectedLevy);
    }

    function test_CollectPhysicalRevertsNonOracle() public {
        vm.prank(org);
        vm.expectRevert("Levy: only oracle");
        levyContract.collectPhysical(ORG_ID, 1000e18, bytes32(uint256(1)));
    }

    function test_CollectPhysicalRevertsEmptyProof() public {
        vm.prank(oracleAddr);
        vm.expectRevert("Levy: empty proof");
        levyContract.collectPhysical(ORG_ID, 1000e18, bytes32(0));
    }

    // ── Views ──

    function test_CurrentRate() public view {
        assertEq(levyContract.currentRate(), LEVY_RATE);
    }

    function test_CurrentPeriod() public view {
        assertEq(levyContract.currentPeriod(), 1);
    }

    // ── Levy reduces circulation ──

    function test_LevyReducesCirculation() public {
        uint256 revenue = 10_000e18;
        uint256 expectedLevy = revenue * LEVY_RATE / 10_000;

        vm.prank(treasuryAddr);
        credit.mint(org, 10_000e18);

        uint256 supplyBefore = credit.totalSupply();

        vm.prank(org);
        credit.approve(address(levyContract), expectedLevy);

        vm.prank(org);
        levyContract.collectDigital(ORG_ID, revenue);

        assertEq(credit.totalSupply(), supplyBefore - expectedLevy);
        assertEq(credit.totalMinted() - credit.totalBurned(), credit.totalSupply());
    }

    // ── Constructor ──

    function test_ConstructorRevertsZeroCredit() public {
        vm.expectRevert("Levy: zero credit");
        new Levy(address(0), treasuryAddr, address(paramStore), oracleAddr);
    }
}
