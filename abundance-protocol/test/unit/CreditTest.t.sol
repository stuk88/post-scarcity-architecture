// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Credit} from "../../src/protocol/Credit.sol";
import {ICredit} from "../../src/interfaces/ICredit.sol";

contract CreditTest is Test {
    Credit credit;
    address treasury = makeAddr("treasury");
    address levy = makeAddr("levy");
    address audit = makeAddr("audit");
    address metricRegistry = makeAddr("metricRegistry");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BASKET_RATE = 1e18;

    function setUp() public {
        credit = new Credit(treasury, levy, audit, metricRegistry, INITIAL_BASKET_RATE);
    }

    // ── Mint ──

    function test_MintByTreasury() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        assertEq(credit.balanceOf(alice), 100e18);
        assertEq(credit.totalMinted(), 100e18);
        assertEq(credit.totalSupply(), 100e18);
    }

    function test_MintRevertsFromNonTreasury() public {
        vm.prank(alice);
        vm.expectRevert("Credit: only treasury");
        credit.mint(alice, 100e18);
    }

    function test_MintRevertsFromLevy() public {
        vm.prank(levy);
        vm.expectRevert("Credit: only treasury");
        credit.mint(alice, 100e18);
    }

    function test_MintEmitsEvent() public {
        vm.prank(treasury);
        vm.expectEmit(true, false, false, true);
        emit ICredit.Minted(alice, 100e18);
        credit.mint(alice, 100e18);
    }

    // ── Burn ──

    function test_BurnByLevy() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        vm.prank(levy);
        credit.burn(alice, 40e18);

        assertEq(credit.balanceOf(alice), 60e18);
        assertEq(credit.totalBurned(), 40e18);
        assertEq(credit.totalSupply(), 60e18);
    }

    function test_BurnByAudit() public {
        vm.prank(treasury);
        credit.mint(audit, 50e18);

        vm.prank(audit);
        credit.burn(audit, 50e18);

        assertEq(credit.totalBurned(), 50e18);
        assertEq(credit.totalSupply(), 0);
    }

    function test_BurnRevertsFromNonAuthorized() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        vm.prank(alice);
        vm.expectRevert("Credit: unauthorized burn");
        credit.burn(alice, 50e18);
    }

    function test_BurnRevertsFromTreasury() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        vm.prank(treasury);
        vm.expectRevert("Credit: unauthorized burn");
        credit.burn(alice, 50e18);
    }

    function test_BurnEmitsEvent() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        vm.prank(levy);
        vm.expectEmit(true, false, false, true);
        emit ICredit.Burned(alice, 30e18);
        credit.burn(alice, 30e18);
    }

    // ── Supply Invariant ──

    function test_SupplyInvariant() public {
        vm.startPrank(treasury);
        credit.mint(alice, 200e18);
        credit.mint(bob, 150e18);
        vm.stopPrank();

        vm.prank(levy);
        credit.burn(alice, 50e18);

        assertEq(credit.totalSupply(), credit.totalMinted() - credit.totalBurned());
        assertEq(credit.totalSupply(), 300e18);
        assertEq(credit.totalMinted(), 350e18);
        assertEq(credit.totalBurned(), 50e18);
    }

    // ── Basket Rate ──

    function test_UpdateBasketRate() public {
        assertEq(credit.basketRate(), INITIAL_BASKET_RATE);

        vm.prank(metricRegistry);
        credit.updateBasketRate(2e18);

        assertEq(credit.basketRate(), 2e18);
    }

    function test_UpdateBasketRateRevertsFromNonRegistry() public {
        vm.prank(alice);
        vm.expectRevert("Credit: only registry");
        credit.updateBasketRate(2e18);
    }

    function test_UpdateBasketRateRevertsOnZero() public {
        vm.prank(metricRegistry);
        vm.expectRevert("Credit: zero rate");
        credit.updateBasketRate(0);
    }

    function test_UpdateBasketRateEmitsEvent() public {
        vm.prank(metricRegistry);
        vm.expectEmit(true, false, false, true);
        emit ICredit.BasketRateUpdated(INITIAL_BASKET_RATE, 3e18, metricRegistry);
        credit.updateBasketRate(3e18);
    }

    // ── Constructor ──

    function test_ConstructorRevertsZeroTreasury() public {
        vm.expectRevert("Credit: zero treasury");
        new Credit(address(0), levy, audit, metricRegistry, 1e18);
    }

    function test_ConstructorRevertsZeroBasketRate() public {
        vm.expectRevert("Credit: zero basket rate");
        new Credit(treasury, levy, audit, metricRegistry, 0);
    }

    // ── ERC20 ──

    function test_NameAndSymbol() public view {
        assertEq(credit.name(), "Abundance Credit");
        assertEq(credit.symbol(), "CREDIT");
    }

    function test_TransferWorks() public {
        vm.prank(treasury);
        credit.mint(alice, 100e18);

        vm.prank(alice);
        credit.transfer(bob, 30e18);

        assertEq(credit.balanceOf(alice), 70e18);
        assertEq(credit.balanceOf(bob), 30e18);
    }
}
