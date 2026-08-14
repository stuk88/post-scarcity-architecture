// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../../src/protocol/Treasury.sol";
import {ITreasury} from "../../src/interfaces/ITreasury.sol";
import {ICredit} from "../../src/interfaces/ICredit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBaseAllocation} from "../../src/interfaces/IBaseAllocation.sol";
import {IParameterStore} from "../../src/interfaces/IParameterStore.sol";
import {IPersonhood} from "../../src/interfaces/IPersonhood.sol";
import {ICappedGradient} from "../../src/interfaces/ICappedGradient.sol";

contract MockCappedGradient is ICappedGradient {
    function clamp(uint256 rawAmount) external pure returns (uint256) {
        return rawAmount;
    }

    function floor() external pure returns (uint256) {
        return 1e18;
    }

    function ceiling() external pure returns (uint256) {
        return 10e18;
    }

    function ratio() external pure returns (uint256) {
        return 10;
    }
}

contract TreasuryTest is Test {
    Treasury treasury;
    MockCappedGradient mockGradient;

    address credit = makeAddr("credit");
    address baseAllocation = makeAddr("baseAllocation");
    address parameterStore = makeAddr("parameterStore");
    address personhood = makeAddr("personhood");
    address raffle = makeAddr("raffle");
    address auditContract = makeAddr("audit");
    address sortition = makeAddr("sortition");
    address levy = makeAddr("levy");
    address completionRegistry = makeAddr("completionRegistry");

    address recipient = makeAddr("recipient");
    bytes32 constant PERSON_ID = bytes32(uint256(1));
    bytes32 constant ORG_ID = bytes32(uint256(2));

    function setUp() public {
        mockGradient = new MockCappedGradient();

        treasury = new Treasury(
            credit, baseAllocation, parameterStore, personhood,
            raffle, auditContract, sortition, levy,
            completionRegistry, address(mockGradient)
        );

        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.decayPeriod.selector), abi.encode(uint256(1000)));
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.basketCost.selector), abi.encode(uint256(1e18)));
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.levyRate.selector), abi.encode(uint256(500)));
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.minAuditStake.selector), abi.encode(uint256(100e18)));
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.poolBudget.selector), abi.encode(uint256(1000e18)));
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.bountyMultiplier.selector), abi.encode(uint256(20000)));
    }

    // ── streamBaseAllocation ──

    function test_StreamBaseAllocation() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.isActive.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.withdraw.selector, PERSON_ID), abi.encode(uint256(100e18)));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, PERSON_ID), abi.encode(recipient));
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());

        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, recipient, 100e18));

        treasury.streamBaseAllocation(PERSON_ID);
    }

    function test_StreamRevertsUnverified() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(false));

        vm.expectRevert("Treasury: not verified");
        treasury.streamBaseAllocation(PERSON_ID);
    }

    function test_StreamRevertsNotActive() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.isActive.selector, PERSON_ID), abi.encode(false));

        vm.expectRevert("Treasury: not active");
        treasury.streamBaseAllocation(PERSON_ID);
    }

    function test_StreamRevertsZeroAccrual() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.isActive.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.withdraw.selector, PERSON_ID), abi.encode(uint256(0)));

        vm.expectRevert("Treasury: nothing accrued");
        treasury.streamBaseAllocation(PERSON_ID);
    }

    // ── fundRafflePool ──

    function test_FundRafflePool() public {
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());
        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, raffle, 1000e18));

        vm.prank(raffle);
        treasury.fundRafflePool(0);
    }

    function test_FundRaffleRevertsNonRaffle() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("Treasury: only raffle");
        treasury.fundRafflePool(0);
    }

    function test_FundRaffleRevertsZeroBudget() public {
        vm.mockCall(parameterStore, abi.encodeWithSelector(IParameterStore.poolBudget.selector, uint8(1)), abi.encode(uint256(0)));

        vm.prank(raffle);
        vm.expectRevert("Treasury: zero budget");
        treasury.fundRafflePool(1);
    }

    // ── payBounty ──

    function test_PayBounty() public {
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());
        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, auditContract, 200e18));

        vm.prank(auditContract);
        treasury.payBounty(1, 100e18);
    }

    function test_PayBountyRevertsNonAudit() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("Treasury: only audit");
        treasury.payBounty(1, 100e18);
    }

    function test_PayBountyScaling() public {
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());
        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, auditContract, 100e18));

        vm.prank(auditContract);
        treasury.payBounty(1, 50e18);
    }

    function test_PayBountyRevertsZeroStake() public {
        vm.prank(auditContract);
        vm.expectRevert("Treasury: zero stake");
        treasury.payBounty(1, 0);
    }

    // ── releaseProjectTranche ──

    function test_ReleaseProjectTranche() public {
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, ORG_ID), abi.encode(recipient));
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());

        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, recipient, 500e18));

        vm.prank(completionRegistry);
        treasury.releaseProjectTranche(42, ORG_ID, 500e18);
    }

    function test_ReleaseProjectTrancheRevertsNonRegistry() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("Treasury: only registry");
        treasury.releaseProjectTranche(42, ORG_ID, 500e18);
    }

    function test_ReleaseProjectTrancheRevertsZeroTranche() public {
        vm.prank(completionRegistry);
        vm.expectRevert("Treasury: zero tranche");
        treasury.releaseProjectTranche(42, ORG_ID, 0);
    }

    function test_ReleaseProjectTrancheRevertsNoRecipient() public {
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, ORG_ID), abi.encode(address(0)));

        vm.prank(completionRegistry);
        vm.expectRevert("Treasury: no recipient");
        treasury.releaseProjectTranche(42, ORG_ID, 500e18);
    }

    // ── fundRole ──

    function test_FundRole() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, PERSON_ID), abi.encode(recipient));
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());

        vm.expectCall(credit, abi.encodeWithSelector(ICredit.mint.selector, recipient, 1e18));

        vm.prank(sortition);
        treasury.fundRole(PERSON_ID, 42);
    }

    function test_FundRoleRevertsUnverified() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(false));

        vm.prank(sortition);
        vm.expectRevert("Treasury: not verified");
        treasury.fundRole(PERSON_ID, 42);
    }

    function test_FundRoleRevertsNonSortition() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("Treasury: only sortition");
        treasury.fundRole(PERSON_ID, 42);
    }

    function test_FundRoleRevertsNoRecipient() public {
        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, PERSON_ID), abi.encode(address(0)));

        vm.prank(sortition);
        vm.expectRevert("Treasury: no recipient");
        treasury.fundRole(PERSON_ID, 42);
    }

    // ── collectLevy ──

    function test_CollectLevy() public {
        vm.prank(levy);
        treasury.collectLevy(ORG_ID, 10_000e18);

        assertEq(treasury.periodLevyCollected(), 10_000e18 * 500 / 10_000);
    }

    function test_CollectLevyRevertsNonLevy() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert("Treasury: only levy");
        treasury.collectLevy(ORG_ID, 1000e18);
    }

    // ── No arbitrary transfer ──

    function test_NoArbitraryTransferFunction() public view {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = ITreasury.streamBaseAllocation.selector;
        selectors[1] = ITreasury.fundRafflePool.selector;
        selectors[2] = ITreasury.payBounty.selector;
        selectors[3] = ITreasury.releaseProjectTranche.selector;
        selectors[4] = ITreasury.fundRole.selector;
        selectors[5] = ITreasury.collectLevy.selector;

        for (uint256 i = 0; i < selectors.length; i++) {
            assertTrue(selectors[i] != bytes4(keccak256("transfer(address,uint256)")));
            assertTrue(selectors[i] != bytes4(keccak256("transferTo(address,uint256)")));
            assertTrue(selectors[i] != bytes4(keccak256("send(address,uint256)")));
        }
    }

    // ── totalCirculating ──

    function test_TotalCirculatingDelegatesToCredit() public {
        vm.mockCall(credit, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(uint256(5000e18)));
        assertEq(treasury.totalCirculating(), 5000e18);
    }

    // ── Period advancement ──

    function test_PeriodAdvances() public {
        vm.prank(levy);
        treasury.collectLevy(ORG_ID, 10_000e18);
        assertEq(treasury.currentPeriod(), 1);
        uint256 levyBefore = treasury.periodLevyCollected();
        assertTrue(levyBefore > 0);

        vm.roll(block.number + 1000);

        vm.prank(levy);
        treasury.collectLevy(ORG_ID, 5_000e18);
        assertEq(treasury.currentPeriod(), 2);
        assertEq(treasury.periodLevyCollected(), 5_000e18 * 500 / 10_000);
    }

    function test_MultiPeriodJump() public {
        vm.roll(block.number + 3000);

        vm.mockCall(personhood, abi.encodeWithSelector(IPersonhood.isUniquePerson.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.isActive.selector, PERSON_ID), abi.encode(true));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.withdraw.selector, PERSON_ID), abi.encode(uint256(100e18)));
        vm.mockCall(baseAllocation, abi.encodeWithSelector(IBaseAllocation.recipientOf.selector, PERSON_ID), abi.encode(recipient));
        vm.mockCall(credit, abi.encodeWithSelector(ICredit.mint.selector), abi.encode());

        treasury.streamBaseAllocation(PERSON_ID);
        assertEq(treasury.currentPeriod(), 4);
    }

    // ── Constructor ──

    function test_ConstructorRevertsZeroCredit() public {
        vm.expectRevert("Treasury: zero credit");
        new Treasury(
            address(0), baseAllocation, parameterStore, personhood,
            raffle, auditContract, sortition, levy,
            completionRegistry, address(mockGradient)
        );
    }

    function test_ConstructorRevertsZeroRegistry() public {
        vm.expectRevert("Treasury: zero registry");
        new Treasury(
            credit, baseAllocation, parameterStore, personhood,
            raffle, auditContract, sortition, levy,
            address(0), address(mockGradient)
        );
    }

    function test_ConstructorRevertsZeroGradient() public {
        vm.expectRevert("Treasury: zero gradient");
        new Treasury(
            credit, baseAllocation, parameterStore, personhood,
            raffle, auditContract, sortition, levy,
            completionRegistry, address(0)
        );
    }
}
