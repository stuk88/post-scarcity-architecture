// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {Credit} from "../src/protocol/Credit.sol";
import {Reputation} from "../src/protocol/Reputation.sol";
import {Treasury} from "../src/protocol/Treasury.sol";
import {BaseAllocation} from "../src/protocol/BaseAllocation.sol";
import {CappedGradient} from "../src/protocol/CappedGradient.sol";
import {Raffle} from "../src/protocol/Raffle.sol";
import {Levy} from "../src/protocol/Levy.sol";
import {Audit} from "../src/protocol/Audit.sol";
import {CompletionRegistry} from "../src/protocol/CompletionRegistry.sol";

import {Sortition} from "../src/governance/Sortition.sol";
import {Emergency} from "../src/governance/Emergency.sol";
import {DecayCycle} from "../src/governance/DecayCycle.sol";

import {MetricRegistry} from "../src/metric/MetricRegistry.sol";
import {BasketDefinition} from "../src/metric/BasketDefinition.sol";
import {ParameterStore} from "../src/metric/ParameterStore.sol";

struct Predicted {
    address reputation;
    address metricRegistry;
    address parameterStore;
    address cappedGradient;
    address credit;
    address levy;
    address audit;
    address sortition;
    address treasury;
    address baseAllocation;
    address raffle;
    address emergency;
    address decayCycle;
    address basketDefinition;
    address completionRegistry;
}

contract Deploy is Script {
    Reputation public reputation;
    MetricRegistry public metricRegistry;
    ParameterStore public parameterStore;
    CappedGradient public cappedGradient;
    Credit public credit;
    Levy public levy;
    Audit public audit;
    Sortition public sortition;
    Treasury public treasury;
    BaseAllocation public baseAllocation;
    Raffle public raffle;
    Emergency public emergency;
    DecayCycle public decayCycle;
    BasketDefinition public basketDefinition;
    CompletionRegistry public completionRegistry;

    uint256 internal constant DECAY_PERIOD = 50_400;
    uint256 internal constant INITIAL_BASKET_RATE = 1e18;

    function run() public virtual {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address personhood = vm.envAddress("PERSONHOOD_ADDRESS");
        address beacon = vm.envAddress("BEACON_ADDRESS");
        address oracle = vm.envAddress("ORACLE_ADDRESS");

        vm.startBroadcast(deployerKey);
        _deploy(deployer, personhood, beacon, oracle);
        vm.stopBroadcast();

        _logAddresses();
    }

    function _precompute(address deployer) internal view returns (Predicted memory p) {
        uint256 n = vm.getNonce(deployer);
        p.reputation = vm.computeCreateAddress(deployer, n);
        p.metricRegistry = vm.computeCreateAddress(deployer, n + 1);
        p.parameterStore = vm.computeCreateAddress(deployer, n + 2);
        p.cappedGradient = vm.computeCreateAddress(deployer, n + 3);
        p.credit = vm.computeCreateAddress(deployer, n + 4);
        p.levy = vm.computeCreateAddress(deployer, n + 5);
        p.audit = vm.computeCreateAddress(deployer, n + 6);
        p.sortition = vm.computeCreateAddress(deployer, n + 7);
        p.treasury = vm.computeCreateAddress(deployer, n + 8);
        p.baseAllocation = vm.computeCreateAddress(deployer, n + 9);
        p.raffle = vm.computeCreateAddress(deployer, n + 10);
        p.emergency = vm.computeCreateAddress(deployer, n + 11);
        p.decayCycle = vm.computeCreateAddress(deployer, n + 12);
        p.basketDefinition = vm.computeCreateAddress(deployer, n + 13);
        p.completionRegistry = vm.computeCreateAddress(deployer, n + 14);
    }

    function _deploy(
        address deployer,
        address personhood,
        address beacon,
        address oracle
    ) internal {
        Predicted memory p = _precompute(deployer);

        _deployContracts(deployer, personhood, beacon, oracle, p);
        _verifyAddresses(p);
        _postDeploy();
    }

    function _deployContracts(
        address deployer,
        address personhood,
        address beacon,
        address oracle,
        Predicted memory p
    ) internal {
        reputation = new Reputation(deployer);
        metricRegistry = new MetricRegistry(p.sortition, p.audit, DECAY_PERIOD);
        parameterStore = new ParameterStore(p.metricRegistry);
        cappedGradient = new CappedGradient(p.parameterStore);
        credit = new Credit(p.treasury, p.levy, p.audit, p.metricRegistry, INITIAL_BASKET_RATE);
        levy = new Levy(p.credit, p.treasury, p.parameterStore, oracle);
        audit = new Audit(p.credit, personhood, p.treasury, p.reputation, p.parameterStore);
        sortition = new Sortition(personhood, beacon, p.parameterStore, p.treasury);
        treasury = new Treasury(
            p.credit, p.baseAllocation, p.parameterStore, personhood,
            p.raffle, p.audit, p.sortition, p.levy,
            p.completionRegistry, p.cappedGradient
        );
        baseAllocation = new BaseAllocation(p.treasury, p.parameterStore, personhood, deployer);
        raffle = new Raffle(personhood, p.parameterStore, beacon, p.sortition, p.credit, p.treasury);
        emergency = new Emergency(p.sortition, p.metricRegistry, p.parameterStore);
        decayCycle = new DecayCycle(p.sortition, p.parameterStore);
        basketDefinition = new BasketDefinition(p.sortition, oracle);
        completionRegistry = new CompletionRegistry(p.treasury, p.reputation, personhood, p.parameterStore, deployer);
    }

    function _verifyAddresses(Predicted memory p) internal view {
        require(address(reputation) == p.reputation, "nonce mismatch: reputation");
        require(address(metricRegistry) == p.metricRegistry, "nonce mismatch: metricRegistry");
        require(address(parameterStore) == p.parameterStore, "nonce mismatch: parameterStore");
        require(address(cappedGradient) == p.cappedGradient, "nonce mismatch: cappedGradient");
        require(address(credit) == p.credit, "nonce mismatch: credit");
        require(address(levy) == p.levy, "nonce mismatch: levy");
        require(address(audit) == p.audit, "nonce mismatch: audit");
        require(address(sortition) == p.sortition, "nonce mismatch: sortition");
        require(address(treasury) == p.treasury, "nonce mismatch: treasury");
        require(address(baseAllocation) == p.baseAllocation, "nonce mismatch: baseAllocation");
        require(address(raffle) == p.raffle, "nonce mismatch: raffle");
        require(address(emergency) == p.emergency, "nonce mismatch: emergency");
        require(address(decayCycle) == p.decayCycle, "nonce mismatch: decayCycle");
        require(address(basketDefinition) == p.basketDefinition, "nonce mismatch: basketDefinition");
        require(address(completionRegistry) == p.completionRegistry, "nonce mismatch: completionRegistry");
    }

    function _postDeploy() internal virtual {
        reputation.authorize(address(audit));
        reputation.authorize(address(completionRegistry));

        emergency.registerTrigger(
            keccak256("SUPPLY_SHORTAGE"),
            keccak256("supply_index"),
            50e18,
            keccak256("INCREASE_ALLOCATION"),
            7200
        );

        emergency.registerTrigger(
            keccak256("DEMAND_SPIKE"),
            keccak256("demand_index"),
            200e18,
            keccak256("ADJUST_PRICING"),
            3600
        );

        emergency.finalizeSetup();
    }

    function _logAddresses() internal view {
        console.log("=== Abundance Protocol Deployed ===");
        console.log("Reputation:      ", address(reputation));
        console.log("MetricRegistry:  ", address(metricRegistry));
        console.log("ParameterStore:  ", address(parameterStore));
        console.log("CappedGradient:  ", address(cappedGradient));
        console.log("Credit:          ", address(credit));
        console.log("Levy:            ", address(levy));
        console.log("Audit:           ", address(audit));
        console.log("Sortition:       ", address(sortition));
        console.log("Treasury:        ", address(treasury));
        console.log("BaseAllocation:  ", address(baseAllocation));
        console.log("Raffle:          ", address(raffle));
        console.log("Emergency:       ", address(emergency));
        console.log("DecayCycle:      ", address(decayCycle));
        console.log("BasketDefinition:", address(basketDefinition));
        console.log("CompletionReg:   ", address(completionRegistry));
        console.log("===================================");
    }
}
