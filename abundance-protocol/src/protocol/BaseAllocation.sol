// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBaseAllocation} from "../interfaces/IBaseAllocation.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";

contract BaseAllocation is IBaseAllocation {
    struct Allocation {
        address recipient;
        uint256 lastWithdrawBlock;
        bool active;
    }

    IParameterStore public immutable parameterStore;
    IPersonhood public immutable personhood;
    address public immutable treasury;
    address public immutable governance;

    mapping(bytes32 => Allocation) private _allocations;

    constructor(
        address _treasury,
        address _parameterStore,
        address _personhood,
        address _governance
    ) {
        require(_treasury != address(0), "BaseAllocation: zero treasury");
        require(_parameterStore != address(0), "BaseAllocation: zero store");
        require(_personhood != address(0), "BaseAllocation: zero personhood");
        require(_governance != address(0), "BaseAllocation: zero governance");

        treasury = _treasury;
        parameterStore = IParameterStore(_parameterStore);
        personhood = IPersonhood(_personhood);
        governance = _governance;
    }

    function register(bytes32 personId, address recipient) external override {
        require(personId == bytes32(uint256(uint160(msg.sender))), "BaseAllocation: not owner");
        require(personhood.isUniquePerson(personId), "BaseAllocation: not verified");
        require(recipient != address(0), "BaseAllocation: zero recipient");
        Allocation storage alloc = _allocations[personId];
        require(alloc.recipient == address(0), "BaseAllocation: already registered");

        alloc.recipient = recipient;
        alloc.lastWithdrawBlock = block.number;
        alloc.active = true;

        emit Registered(personId, recipient);
    }

    function withdraw(bytes32 personId) external override returns (uint256 amount) {
        require(msg.sender == treasury, "BaseAllocation: only treasury");
        Allocation storage alloc = _allocations[personId];
        require(alloc.active, "BaseAllocation: not active");

        uint256 rate = parameterStore.basketCost();
        amount = (block.number - alloc.lastWithdrawBlock) * rate;
        alloc.lastWithdrawBlock = block.number;

        emit Withdrawn(personId, alloc.recipient, amount);
    }

    function suspend(bytes32 personId) external override {
        require(msg.sender == governance, "BaseAllocation: only governance");
        Allocation storage alloc = _allocations[personId];
        require(alloc.active, "BaseAllocation: not active");

        alloc.lastWithdrawBlock = block.number;
        alloc.active = false;

        emit Suspended(personId);
    }

    function resume(bytes32 personId) external override {
        require(msg.sender == governance, "BaseAllocation: only governance");
        Allocation storage alloc = _allocations[personId];
        require(!alloc.active, "BaseAllocation: not suspended");
        require(alloc.recipient != address(0), "BaseAllocation: not registered");
        require(personhood.isUniquePerson(personId), "BaseAllocation: not verified");

        alloc.active = true;
        alloc.lastWithdrawBlock = block.number;

        emit Resumed(personId);
    }

    function accrued(bytes32 personId) external view override returns (uint256) {
        Allocation storage alloc = _allocations[personId];
        if (!alloc.active) return 0;
        uint256 rate = parameterStore.basketCost();
        return (block.number - alloc.lastWithdrawBlock) * rate;
    }

    function ratePerBlock() external view override returns (uint256) {
        return parameterStore.basketCost();
    }

    function isActive(bytes32 personId) external view override returns (bool) {
        return _allocations[personId].active;
    }

    function recipientOf(bytes32 personId) external view override returns (address) {
        return _allocations[personId].recipient;
    }
}
