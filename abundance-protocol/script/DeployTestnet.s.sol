// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {Deploy} from "./Deploy.s.sol";
import {MockPersonhood} from "../test/mocks/Mocks.sol";
import {MockBeacon} from "../test/mocks/Mocks.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    function getPrice(bytes32) external pure returns (uint256) {
        return 1e18;
    }
}

contract DeployTestnet is Deploy {
    MockPersonhood public mockPersonhood;
    MockBeacon public mockBeacon;
    MockPriceOracle public mockOracle;

    function run() public override {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        mockPersonhood = new MockPersonhood();
        mockBeacon = new MockBeacon();
        mockOracle = new MockPriceOracle();

        _deploy(deployer, address(mockPersonhood), address(mockBeacon), address(mockOracle));

        bytes32 deployerId = bytes32(uint256(uint160(deployer)));
        mockPersonhood.addPerson(deployerId);

        baseAllocation.register(deployerId, deployer);

        vm.stopBroadcast();

        _logAddresses();
        _logTestnetExtras();
    }

    function _logTestnetExtras() internal view {
        console.log("=== Testnet Extras ===");
        console.log("MockPersonhood:  ", address(mockPersonhood));
        console.log("MockBeacon:      ", address(mockBeacon));
        console.log("MockPriceOracle: ", address(mockOracle));
        console.log("======================");
    }
}
