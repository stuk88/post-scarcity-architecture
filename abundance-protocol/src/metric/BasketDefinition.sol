// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISortition} from "../interfaces/ISortition.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

contract BasketDefinition {
    struct BasketItem {
        bytes32 itemId;
        uint256 weight;
    }

    struct Proposal {
        uint256 panelId;
        bool submitted;
    }

    ISortition public immutable sortition;
    IPriceOracle public immutable oracle;

    BasketItem[] internal _basket;
    mapping(bytes32 => Proposal) internal _proposals;

    error EmptyBasket();
    error LengthMismatch();
    error NoProposalFound(bytes32 proposalHash);
    error PanelNotResolved(uint256 panelId);
    error PanelNotApproved(uint256 panelId);
    error WrongPanelPurpose();

    event BasketUpdated(uint256 itemCount, uint256 panelId);
    event ProposalSubmitted(bytes32 indexed proposalHash, uint256 panelId);

    constructor(address _sortition, address _oracle) {
        sortition = ISortition(_sortition);
        oracle = IPriceOracle(_oracle);
    }

    function proposeUpdateBasket(bytes32[] calldata itemIds, uint256[] calldata weights, uint256 panelId) external {
        bytes32 h = keccak256(abi.encode("updateBasket", itemIds, weights));
        _proposals[h] = Proposal(panelId, true);
        emit ProposalSubmitted(h, panelId);
    }

    function updateBasket(bytes32[] calldata itemIds, uint256[] calldata weights) external {
        if (itemIds.length != weights.length) revert LengthMismatch();
        if (itemIds.length == 0) revert EmptyBasket();

        bytes32 proposalHash = keccak256(abi.encode("updateBasket", itemIds, weights));
        uint256 panelId = _consumeProposal(proposalHash);

        delete _basket;
        for (uint256 i = 0; i < itemIds.length; i++) {
            _basket.push(BasketItem(itemIds[i], weights[i]));
        }

        emit BasketUpdated(itemIds.length, panelId);
    }

    function calculateBasketCost() external view returns (uint256 totalCost) {
        uint256 len = _basket.length;
        if (len == 0) revert EmptyBasket();

        for (uint256 i = 0; i < len; i++) {
            BasketItem storage item = _basket[i];
            uint256 price = oracle.getPrice(item.itemId);
            totalCost += (item.weight * price) / 1e18;
        }
    }

    function basketLength() external view returns (uint256) {
        return _basket.length;
    }

    function getBasketItem(uint256 index) external view returns (bytes32 itemId, uint256 weight) {
        BasketItem storage item = _basket[index];
        return (item.itemId, item.weight);
    }

    function _consumeProposal(bytes32 proposalHash) internal returns (uint256 panelId) {
        Proposal storage p = _proposals[proposalHash];
        if (!p.submitted) revert NoProposalFound(proposalHash);
        panelId = p.panelId;
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        if (!resolved) revert PanelNotResolved(panelId);
        if (!approved) revert PanelNotApproved(panelId);

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        if (panel.purpose != proposalHash) revert WrongPanelPurpose();

        delete _proposals[proposalHash];
    }
}
