// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {Credit} from "../../src/protocol/Credit.sol";

contract CreditHandler is StdUtils {
    Credit public credit;

    uint256 public ghostMinted;
    uint256 public ghostBurned;

    constructor(Credit _credit) {
        credit = _credit;
    }

    function mint(uint256 amount) external {
        amount = _bound(amount, 0, 1e30);
        credit.mint(address(this), amount);
        ghostMinted += amount;
    }

    function burn(uint256 amount) external {
        uint256 balance = credit.balanceOf(address(this));
        if (balance == 0) return;
        amount = _bound(amount, 1, balance);
        credit.burn(address(this), amount);
        ghostBurned += amount;
    }
}

contract InvariantCreditTest is Test {
    Credit credit;
    CreditHandler handler;

    function setUp() public {
        address handlerAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        credit = new Credit(handlerAddr, handlerAddr, handlerAddr, makeAddr("registry"), 1e18);
        handler = new CreditHandler(credit);

        targetContract(address(handler));
    }

    function invariant_supplyIdentity() public view {
        assertEq(
            credit.totalSupply(),
            credit.totalMinted() - credit.totalBurned(),
            "supply != minted - burned"
        );
    }

    function invariant_ghostMatchesContract() public view {
        assertEq(credit.totalMinted(), handler.ghostMinted(), "ghost minted mismatch");
        assertEq(credit.totalBurned(), handler.ghostBurned(), "ghost burned mismatch");
    }

    function testFuzz_mintBurn(uint256 mintAmt, uint256 burnAmt) public {
        mintAmt = bound(mintAmt, 0, 1e30);

        address treasury = address(handler);

        vm.prank(treasury);
        credit.mint(address(this), mintAmt);

        uint256 balance = credit.balanceOf(address(this));
        burnAmt = bound(burnAmt, 0, balance);

        if (burnAmt > 0) {
            vm.prank(treasury);
            credit.burn(address(this), burnAmt);
        }

        assertEq(
            credit.totalSupply(),
            credit.totalMinted() - credit.totalBurned(),
            "supply identity violated after mint+burn"
        );
    }
}
