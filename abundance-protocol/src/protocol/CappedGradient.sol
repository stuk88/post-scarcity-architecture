// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICappedGradient} from "../interfaces/ICappedGradient.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";

contract CappedGradient is ICappedGradient {
    IParameterStore public immutable parameterStore;

    constructor(address _parameterStore) {
        require(_parameterStore != address(0), "CappedGradient: zero store");
        parameterStore = IParameterStore(_parameterStore);
    }

    function clamp(uint256 rawAmount) external view override returns (uint256) {
        uint256 f = parameterStore.gradientFloor();
        uint256 c = parameterStore.gradientCeiling();
        if (rawAmount < f) return f;
        if (rawAmount > c) return c;
        return rawAmount;
    }

    function floor() external view override returns (uint256) {
        return parameterStore.gradientFloor();
    }

    function ceiling() external view override returns (uint256) {
        return parameterStore.gradientCeiling();
    }

    function ratio() external view override returns (uint256) {
        uint256 f = parameterStore.gradientFloor();
        require(f > 0, "CappedGradient: zero floor");
        return parameterStore.gradientCeiling() / f;
    }
}
