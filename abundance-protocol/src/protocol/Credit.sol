// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ICredit} from "../interfaces/ICredit.sol";

contract Credit is ICredit, ERC20 {
    address public immutable treasury;
    address public immutable levy;
    address public immutable audit;
    address public immutable metricRegistry;

    uint256 private _basketRate;
    uint256 private _totalMinted;
    uint256 private _totalBurned;

    constructor(
        address _treasury,
        address _levy,
        address _audit,
        address _metricRegistry,
        uint256 initialBasketRate
    ) ERC20("Abundance Credit", "CREDIT") {
        require(_treasury != address(0), "Credit: zero treasury");
        require(_levy != address(0), "Credit: zero levy");
        require(_audit != address(0), "Credit: zero audit");
        require(_metricRegistry != address(0), "Credit: zero registry");
        require(initialBasketRate > 0, "Credit: zero basket rate");

        treasury = _treasury;
        levy = _levy;
        audit = _audit;
        metricRegistry = _metricRegistry;
        _basketRate = initialBasketRate;
    }

    function mint(address to, uint256 amount) external override {
        require(msg.sender == treasury, "Credit: only treasury");
        _totalMinted += amount;
        _mint(to, amount);
        emit Minted(to, amount);
    }

    function burn(address from, uint256 amount) external override {
        require(
            msg.sender == levy || msg.sender == audit,
            "Credit: unauthorized burn"
        );
        _totalBurned += amount;
        _burn(from, amount);
        emit Burned(from, amount);
    }

    function updateBasketRate(uint256 newRate) external override {
        require(msg.sender == metricRegistry, "Credit: only registry");
        require(newRate > 0, "Credit: zero rate");
        uint256 oldRate = _basketRate;
        _basketRate = newRate;
        emit BasketRateUpdated(oldRate, newRate, msg.sender);
    }

    function basketRate() external view override returns (uint256) {
        return _basketRate;
    }

    function totalMinted() external view override returns (uint256) {
        return _totalMinted;
    }

    function totalBurned() external view override returns (uint256) {
        return _totalBurned;
    }
}
