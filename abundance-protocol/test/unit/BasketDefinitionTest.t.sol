// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BasketDefinition} from "../../src/metric/BasketDefinition.sol";
import {ISortition} from "../../src/interfaces/ISortition.sol";

contract MockSortitionBD {
    mapping(uint256 => bool) internal _resolved;
    mapping(uint256 => bool) internal _approved;
    mapping(uint256 => bytes32) internal _purposes;

    function mockPanel(uint256 panelId, bool resolved, bool approved) external {
        _resolved[panelId] = resolved;
        _approved[panelId] = approved;
    }

    function mockPurpose(uint256 panelId, bytes32 purpose) external {
        _purposes[panelId] = purpose;
    }

    function isResolved(uint256 panelId) external view returns (bool, bool) {
        return (_resolved[panelId], _approved[panelId]);
    }

    function getPanel(uint256 panelId) external view returns (ISortition.Panel memory) {
        ISortition.Panel memory p;
        p.panelId = panelId;
        p.purpose = _purposes[panelId];
        p.state = _resolved[panelId] ? ISortition.PanelState.Resolved : ISortition.PanelState.Active;
        return p;
    }
}

contract MockPriceOracle {
    mapping(bytes32 => uint256) internal _prices;

    function setPrice(bytes32 itemId, uint256 price) external {
        _prices[itemId] = price;
    }

    function getPrice(bytes32 itemId) external view returns (uint256) {
        return _prices[itemId];
    }
}

contract BasketDefinitionTest is Test {
    BasketDefinition public basket;
    MockSortitionBD public sortition;
    MockPriceOracle public oracle;

    uint256 constant PANEL_ID = 1;

    bytes32 constant BREAD = keccak256("BREAD");
    bytes32 constant MILK = keccak256("MILK");
    bytes32 constant RICE = keccak256("RICE");

    function setUp() public {
        sortition = new MockSortitionBD();
        oracle = new MockPriceOracle();
        basket = new BasketDefinition(address(sortition), address(oracle));
    }

    function _approvePanelForPurpose(uint256 panelId, bytes32 purpose) internal {
        sortition.mockPanel(panelId, true, true);
        sortition.mockPurpose(panelId, purpose);
    }

    function _setupBasket() internal {
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = BREAD;
        ids[1] = MILK;
        ids[2] = RICE;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 2e18;
        weights[1] = 1e18;
        weights[2] = 3e18;

        bytes32 proposalHash = keccak256(abi.encode("updateBasket", ids, weights));
        _approvePanelForPurpose(PANEL_ID, proposalHash);
        basket.proposeUpdateBasket(ids, weights, PANEL_ID);
        basket.updateBasket(ids, weights);
    }

    // ── updateBasket ──

    function test_updateBasket_succeeds() public {
        _setupBasket();

        assertEq(basket.basketLength(), 3);

        (bytes32 id0, uint256 w0) = basket.getBasketItem(0);
        assertEq(id0, BREAD);
        assertEq(w0, 2e18);

        (bytes32 id1, uint256 w1) = basket.getBasketItem(1);
        assertEq(id1, MILK);
        assertEq(w1, 1e18);

        (bytes32 id2, uint256 w2) = basket.getBasketItem(2);
        assertEq(id2, RICE);
        assertEq(w2, 3e18);
    }

    function test_updateBasket_reverts_without_sortition() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BREAD;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;

        bytes32 proposalHash = keccak256(abi.encode("updateBasket", ids, weights));
        vm.expectRevert(abi.encodeWithSelector(BasketDefinition.NoProposalFound.selector, proposalHash));
        basket.updateBasket(ids, weights);
    }

    function test_updateBasket_reverts_panel_not_approved() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BREAD;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;

        sortition.mockPanel(PANEL_ID, true, false);
        basket.proposeUpdateBasket(ids, weights, PANEL_ID);

        vm.expectRevert(abi.encodeWithSelector(BasketDefinition.PanelNotApproved.selector, PANEL_ID));
        basket.updateBasket(ids, weights);
    }

    function test_updateBasket_reverts_empty() public {
        bytes32[] memory ids = new bytes32[](0);
        uint256[] memory weights = new uint256[](0);

        vm.expectRevert(BasketDefinition.EmptyBasket.selector);
        basket.updateBasket(ids, weights);
    }

    function test_updateBasket_reverts_length_mismatch() public {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = BREAD;
        ids[1] = MILK;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;

        vm.expectRevert(BasketDefinition.LengthMismatch.selector);
        basket.updateBasket(ids, weights);
    }

    function test_updateBasket_replaces_previous() public {
        _setupBasket();
        assertEq(basket.basketLength(), 3);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BREAD;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 5e18;

        uint256 panel2 = 2;
        bytes32 proposalHash = keccak256(abi.encode("updateBasket", ids, weights));
        _approvePanelForPurpose(panel2, proposalHash);
        basket.proposeUpdateBasket(ids, weights, panel2);
        basket.updateBasket(ids, weights);

        assertEq(basket.basketLength(), 1);
        (bytes32 id, uint256 w) = basket.getBasketItem(0);
        assertEq(id, BREAD);
        assertEq(w, 5e18);
    }

    // ── calculateBasketCost ──

    function test_calculateBasketCost_correct() public {
        _setupBasket();

        oracle.setPrice(BREAD, 3e18);
        oracle.setPrice(MILK, 5e18);
        oracle.setPrice(RICE, 2e18);

        // cost = (2 * 3) + (1 * 5) + (3 * 2) = 6 + 5 + 6 = 17e18
        uint256 cost = basket.calculateBasketCost();
        assertEq(cost, 17e18);
    }

    function test_calculateBasketCost_single_item() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BREAD;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 4e18;

        bytes32 proposalHash = keccak256(abi.encode("updateBasket", ids, weights));
        _approvePanelForPurpose(PANEL_ID, proposalHash);
        basket.proposeUpdateBasket(ids, weights, PANEL_ID);
        basket.updateBasket(ids, weights);

        oracle.setPrice(BREAD, 25e17);

        // cost = 4 * 2.5 = 10e18
        uint256 cost = basket.calculateBasketCost();
        assertEq(cost, 10e18);
    }

    function test_calculateBasketCost_reverts_empty() public {
        vm.expectRevert(BasketDefinition.EmptyBasket.selector);
        basket.calculateBasketCost();
    }

    function test_calculateBasketCost_zero_price_item() public {
        _setupBasket();

        oracle.setPrice(BREAD, 3e18);
        oracle.setPrice(MILK, 0);
        oracle.setPrice(RICE, 2e18);

        // cost = (2 * 3) + (1 * 0) + (3 * 2) = 6 + 0 + 6 = 12e18
        uint256 cost = basket.calculateBasketCost();
        assertEq(cost, 12e18);
    }

    // ── Panel purpose verification ──

    function test_consumeProposal_reverts_wrong_purpose() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = BREAD;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1e18;

        sortition.mockPanel(PANEL_ID, true, true);
        sortition.mockPurpose(PANEL_ID, keccak256("WRONG_PURPOSE"));
        basket.proposeUpdateBasket(ids, weights, PANEL_ID);

        vm.expectRevert(BasketDefinition.WrongPanelPurpose.selector);
        basket.updateBasket(ids, weights);
    }

    function test_consumeProposal_reverts_reused_panel_different_proposal() public {
        _setupBasket();

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = MILK;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 9e18;

        basket.proposeUpdateBasket(ids, weights, PANEL_ID);

        vm.expectRevert(BasketDefinition.WrongPanelPurpose.selector);
        basket.updateBasket(ids, weights);
    }
}
