# The Abundance Protocol — Implementation Plan

**Language:** Solidity ^0.8.24  
**Toolchain:** Foundry (forge, cast, anvil)  
**Target:** EVM (Arbitrum or Base for low gas; Ethereum L1 for final deploy)  
**Standard:** OpenZeppelin 5.x for primitives (AccessControl, ReentrancyGuard, Pausable)

---

## Phase 0: Scaffolding (sequential, one agent)

Set up the Foundry project, install dependencies, configure foundry.toml, and write all interfaces. Every subsequent phase codes against these interfaces — nothing compiles until Phase 0 merges.

```
abundance-protocol/
├── foundry.toml
├── script/
│   └── Deploy.s.sol
├── src/
│   ├── interfaces/        ← Phase 0 deliverable
│   │   ├── IPersonhood.sol
│   │   ├── ICredit.sol
│   │   ├── ITreasury.sol
│   │   ├── IBaseAllocation.sol
│   │   ├── IRaffle.sol
│   │   ├── ICompletionRegistry.sol
│   │   ├── IReputation.sol
│   │   ├── IAudit.sol
│   │   ├── ILevy.sol
│   │   ├── IMetricRegistry.sol
│   │   ├── IParameterStore.sol
│   │   ├── ISortition.sol
│   │   ├── IEmergency.sol
│   │   ├── ICappedGradient.sol
│   │   └── IRandomnessBeacon.sol
│   ├── protocol/          ← Phase 1 (immutable core)
│   ├── metric/            ← Phase 2 (governed parameters)
│   ├── governance/        ← Phase 3 (sortition + emergency)
│   └── libraries/         ← shared math, types, errors
├── test/
│   ├── unit/
│   ├── integration/
│   └── invariant/
└── docs/
```

---

## Interface Specifications

### IPersonhood.sol
Pluggable proof-of-personhood gate. Multiple providers run in parallel.
```solidity
interface IPersonhood {
    function isUniquePerson(bytes32 id) external view returns (bool);
    function attestationEpoch(bytes32 id) external view returns (uint256);
    function provider(bytes32 id) external view returns (address);
    function isRevoked(bytes32 id) external view returns (bool);
}
```

### ICredit.sol
Non-equity unit of account. ERC-20 compatible but yield-free, no governance weight.
```solidity
interface ICredit is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function basketRate() external view returns (uint256);
    function updateBasketRate(uint256 newRate) external;
}
```

### ITreasury.sol
Single contract holding levy revenue and Credit issuance authority. **No arbitrary transfer function.**
```solidity
interface ITreasury {
    function streamBaseAllocation(bytes32 personId) external;
    function fundRafflePool(uint8 tier) external;
    function payBounty(uint256 claimId) external;
    function fundRole(bytes32 personId, uint256 roleId) external;
    function collectLevy(bytes32 orgId, uint256 attestedOutput) external;
    function totalCirculating() external view returns (uint256);
    function periodLevyCollected() external view returns (uint256);
}
```

### IBaseAllocation.sol
Streaming UBI — per-block accrual, soulbound, non-transferable claim.
```solidity
interface IBaseAllocation {
    function register(bytes32 personId, address recipient) external;
    function withdraw(bytes32 personId) external returns (uint256 amount);
    function accrued(bytes32 personId) external view returns (uint256);
    function ratePerBlock() external view returns (uint256);
    function suspend(bytes32 personId) external;
}
```

### IRaffle.sol
Verifiable-random funding allocation across tiered pools.
```solidity
interface IRaffle {
    enum Tier { Micro, Small, Medium, Large, Megaproject }

    struct Proposal {
        bytes32 proposerId;
        bytes32 contentHash;
        uint256 requestedAmount;
        Tier tier;
        uint256 milestonesCount;
    }

    function submit(Proposal calldata proposal) external returns (uint256 proposalId);
    function closeEntries(Tier tier) external;
    function draw(Tier tier) external returns (uint256[] memory winnerIds);
    function overAskWeight(uint256 proposalId) external view returns (uint256);
    function returnSurplus(uint256 proposalId, uint256 amount) external;
}
```

### ICompletionRegistry.sol
Soulbound project records — not tokens, not transferable.
```solidity
interface ICompletionRegistry {
    enum Outcome { InProgress, Delivered, PartialPivot, HonestFailure, Abandoned, Fraudulent }

    struct Project {
        bytes32 orgId;
        uint256 proposalId;
        uint256 budget;
        Outcome outcome;
        uint256 milestonesTotal;
        uint256 milestonesCompleted;
    }

    function registerProject(bytes32 orgId, uint256 proposalId, uint256 budget, uint256 milestones) external;
    function completeMilestone(uint256 projectId, bytes32 evidenceHash) external;
    function finalizeOutcome(uint256 projectId, Outcome outcome) external;
    function releaseTranche(uint256 projectId, uint256 milestoneIndex) external;
    function getProject(uint256 projectId) external view returns (Project memory);
}
```

### IReputation.sol
Soulbound, multidimensional, non-transferable reputation tokens.
```solidity
interface IReputation {
    struct Score {
        uint256 accuracy;
        uint256 volume;
        uint256 novelty;
        uint256 reliability;
    }

    function getScore(bytes32 personId) external view returns (Score memory);
    function updateDimension(bytes32 personId, bytes32 dimension, int256 delta) external;
}
```

### IAudit.sol
Permissionless, bonded, symmetric-stakes auditing.
```solidity
interface IAudit {
    enum Resolution { Pending, Confirmed, Unconfirmed, BadFaith }

    struct Claim {
        bytes32 claimant;
        bytes32 target;
        bytes32 evidenceHash;
        uint256 stake;
        Resolution resolution;
        uint256 reviewCount;
    }

    function fileClaim(bytes32 target, bytes32 evidenceHash) external payable returns (uint256 claimId);
    function review(uint256 claimId, bool upheld) external;
    function resolve(uint256 claimId) external;
    function getClaim(uint256 claimId) external view returns (Claim memory);
}
```

### ILevy.sol
Machine-output levy — digital (automatic) and physical (oracle-attested).
```solidity
interface ILevy {
    function collectDigital(bytes32 orgId, uint256 settledRevenue) external;
    function collectPhysical(bytes32 orgId, uint256 attestedValue, bytes32 oracleProof) external;
    function currentRate() external view returns (uint256);
    function periodTotal() external view returns (uint256);
}
```

### IMetricRegistry.sol
Governed parameter definitions with decay timers.
```solidity
interface IMetricRegistry {
    struct Metric {
        bytes32 key;
        uint256 value;
        uint256 decayDeadline;
        uint256 lastUpdated;
        bytes32 oracleSource;
    }

    function getMetric(bytes32 key) external view returns (uint256);
    function updateMetric(bytes32 key, uint256 newValue) external;
    function isExpired(bytes32 key) external view returns (bool);
    function reratify(bytes32 key) external;
    function fileDivergenceClaim(bytes32 key, bytes32 evidenceHash) external;
}
```

### IParameterStore.sol
Read-only parameter access for protocol contracts.
```solidity
interface IParameterStore {
    function basketCost() external view returns (uint256);
    function gradientCeiling() external view returns (uint256);
    function gradientFloor() external view returns (uint256);
    function levyRate() external view returns (uint256);
    function minAuditStake() external view returns (uint256);
    function poolBudget(uint8 tier) external view returns (uint256);
    function decayPeriod() external view returns (uint256);
}
```

### ISortition.sol
Random-panel governance — one person, one draw, no token voting.
```solidity
interface ISortition {
    struct Panel {
        uint256 panelId;
        bytes32[] members;
        uint256 createdAt;
        uint256 expiresAt;
        bytes32 purpose;
    }

    function drawPanel(bytes32 purpose, uint256 size) external returns (uint256 panelId);
    function vote(uint256 panelId, bytes32 memberId, bool approve) external;
    function isResolved(uint256 panelId) external view returns (bool resolved, bool approved);
    function killSwitch(uint256 panelId) external;
}
```

### IEmergency.sol
Pre-authorized circuit breakers with auto-expiry.
```solidity
interface IEmergency {
    struct Trigger {
        bytes32 metricKey;
        uint256 threshold;
        bytes32 responseAction;
        uint256 duration;
    }

    function activate(bytes32 triggerId) external;
    function isActive(bytes32 triggerId) external view returns (bool);
    function checkExpiry(bytes32 triggerId) external;
    function renew(bytes32 triggerId, uint256 panelId) external;
    function terminateEarly(bytes32 triggerId) external;
    function activateScarcityBreaker(bytes32 goodId, uint256 priceChannel) external;
}
```

### ICappedGradient.sol
Bounded payout arithmetic — enforces floor:ceiling ratio.
```solidity
interface ICappedGradient {
    function clamp(uint256 rawAmount) external view returns (uint256);
    function floor() external view returns (uint256);
    function ceiling() external view returns (uint256);
    function ratio() external view returns (uint256);
}
```

### IRandomnessBeacon.sol
VRF wrapper — seed unknowable at entry close, single-tx draw.
```solidity
interface IRandomnessBeacon {
    function requestSeed() external returns (uint256 requestId);
    function fulfillSeed(uint256 requestId, uint256 seed) external;
    function getSeed(uint256 requestId) external view returns (uint256);
    function isFulfilled(uint256 requestId) external view returns (bool);
}
```

---

## Phase 1-4: Parallel Agent Work

Once interfaces merge, all phases run **simultaneously** — each agent works against interfaces, not implementations.

### Phase 1 — Protocol Layer (Immutable Core)

Three parallel agents, zero cross-dependencies:

| Agent | Contracts | Key Logic | Test Focus |
|-------|-----------|-----------|------------|
| **Agent A: Money** | `Credit.sol`, `Treasury.sol`, `BaseAllocation.sol`, `Levy.sol`, `CappedGradient.sol` | ERC-20 with mint/burn restricted to Treasury; streaming accrual math; levy collection routing; gradient clamp arithmetic | Mint authority locked to Treasury; no arbitrary transfer on Treasury; streaming accrual accuracy over 10k blocks; levy burns from circulation; gradient never exceeds ratio |
| **Agent B: Raffle** | `Raffle.sol`, `RandomnessBeacon.sol` | Tiered pool management; entry freeze before seed; over-ask inverse weighting; single-tx draw over frozen set; surplus return | Manipulation resistance (no last-revealer bias); probability distribution matches over-ask spec; entry after freeze reverts; pool budget enforcement |
| **Agent C: Registry + Audit** | `CompletionRegistry.sol`, `Reputation.sol`, `Audit.sol` | Soulbound project records; milestone tranche release; multidimensional reputation; bonded claims; 3-review resolution; symmetric stake slashing | Reputation non-transferable; milestone tranche only on attestation; bounty > corruption equilibrium; bad-faith slash; good-faith refund |

### Phase 2 — Metric Layer (Governed Parameters)

| Agent | Contracts | Key Logic | Test Focus |
|-------|-----------|-----------|------------|
| **Agent D: Metrics** | `MetricRegistry.sol`, `ParameterStore.sol`, `BasketDefinition.sol` | Decay timers; re-ratification; oracle integration points; metric-divergence audit routing; parameter read interface for protocol contracts | Expired metric returns zero/reverts; re-ratification resets timer; divergence claim routes correctly; updates require sortition approval |

### Phase 3 — Governance Layer

| Agent | Contracts | Key Logic | Test Focus |
|-------|-----------|-----------|------------|
| **Agent E: Governance** | `Sortition.sol`, `Emergency.sol`, `DecayCycle.sol` | Panel draw from personhood registry via beacon; supermajority math; panel expiry; emergency auto-expire + kill switch; scarcity circuit breaker; 10-year decay schedule | One person one draw; no token weight; panel expires on timer; emergency auto-expires; kill switch works from minority; decay cycle triggers re-founding window |

### Phase 4 — Integration + Invariant Tests

Two agents, run after Phases 1-3 complete:

| Agent | Work | Focus |
|-------|------|-------|
| **Agent F: Integration** | End-to-end scenario tests | Full lifecycle: register person -> receive base allocation -> submit proposal -> win raffle -> complete milestones -> reputation accrues. Levy -> Treasury -> base allocation loop. Audit claim -> resolution -> bounty/slash. Emergency activation -> expiry. |
| **Agent G: Invariant** | Foundry invariant/fuzz tests | Treasury never has arbitrary outflow; Credit supply = minted - burned; reputation never transfers; gradient ratio always <= ceiling; no entry after freeze; total base allocation <= Treasury capacity; emergency never rewrites protocol |

---

## Dependency Graph

```
Phase 0 (Interfaces — sequential)
    |
    |--- Agent A: Money (Credit, Treasury, BaseAllocation, Levy, CappedGradient)
    |--- Agent B: Raffle (Raffle, RandomnessBeacon)
    |--- Agent C: Registry (CompletionRegistry, Reputation, Audit)
    |--- Agent D: Metrics (MetricRegistry, ParameterStore, BasketDefinition)
    |--- Agent E: Governance (Sortition, Emergency, DecayCycle)
    |         |
    |         all five complete
    |              |
    |         Agent F: Integration tests
    |         Agent G: Invariant + fuzz tests
    |              |
    |         both complete
    |              |
    |         Deploy script + testnet deployment (sequential)
```

**Critical path:** Phase 0 -> Phases 1/2/3 (parallel) -> Phase 4 (parallel) -> Deploy.

---

## Protocol Invariants (enforced across all agents)

Non-negotiable — every agent's code is verified against these:

1. **No arbitrary transfer on Treasury.** There is no `transferTo(address)` or equivalent.
2. **Credit supply identity.** `totalSupply == totalMinted - totalBurned` at every block.
3. **Reputation is soulbound.** Any transfer attempt reverts unconditionally.
4. **Gradient bounds.** Every payout function returns `floor <= result <= ceiling`.
5. **Raffle integrity.** No entry accepted after freeze; draw uses only the frozen set and a post-freeze seed.
6. **Base allocation is non-transferable.** The claim itself cannot be sold, assigned, or delegated.
7. **Emergency cannot rewrite protocol.** Emergency functions can pause flows and redirect budgets; they cannot modify protocol contract state or logic.
8. **Decay timers expire.** An un-re-ratified metric returns zero or reverts after its deadline.
9. **No token-weighted governance.** No function accepts a balance as a vote weight.
10. **Personhood uniqueness.** One person = one base allocation, one raffle identity, one sortition draw.

---

## Estimated Scope

| Component | Files | Est. Lines |
|-----------|-------|-----------|
| Interfaces | 15 | ~600 |
| Protocol layer (Agent A) | 5 + tests | ~2,500 |
| Raffle system (Agent B) | 2 + tests | ~1,200 |
| Registry + Audit (Agent C) | 3 + tests | ~2,000 |
| Metric layer (Agent D) | 3 + tests | ~1,000 |
| Governance (Agent E) | 3 + tests | ~1,500 |
| Integration tests (Agent F) | ~5 | ~1,500 |
| Invariant tests (Agent G) | ~3 | ~800 |
| Deploy scripts | 1 | ~300 |
| **Total** | **~40** | **~11,400** |
