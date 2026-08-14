# Deployment Guide

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)
- An RPC endpoint for the target chain
- A funded deployer account (private key)
- For mainnet: deployed Personhood, RandomnessBeacon, and PriceOracle contract addresses

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `PRIVATE_KEY` | Always | Deployer private key (hex, no 0x prefix) |
| `PERSONHOOD_ADDRESS` | Mainnet | Address of the Personhood identity contract |
| `BEACON_ADDRESS` | Mainnet | Address of the VRF / randomness beacon |
| `ORACLE_ADDRESS` | Mainnet | Address of the price oracle for basket items |

Testnet deployments deploy mock versions of Personhood, Beacon, and PriceOracle automatically.

## Deployment

### Testnet

Deploys all 14 protocol contracts plus 3 mocks. Registers the deployer as a verified person and enrolls them in BaseAllocation.

```bash
export PRIVATE_KEY=<your_private_key>

forge script script/DeployTestnet.s.sol:DeployTestnet \
  --rpc-url <RPC_URL> \
  --broadcast \
  -vvvv
```

### Mainnet

Requires external infrastructure contracts (Personhood, Beacon, PriceOracle) to already be deployed.

```bash
export PRIVATE_KEY=<your_private_key>
export PERSONHOOD_ADDRESS=<address>
export BEACON_ADDRESS=<address>
export ORACLE_ADDRESS=<address>

forge script script/Deploy.s.sol:Deploy \
  --rpc-url <RPC_URL> \
  --broadcast \
  --verify \
  -vvvv
```

Add `--etherscan-api-key <KEY>` when using `--verify` on chains with Etherscan-compatible explorers.

## What the Scripts Do

### Deploy.s.sol

1. Precomputes all 14 contract addresses using `vm.computeCreateAddress` to resolve circular constructor dependencies (Credit <-> Treasury <-> Levy <-> Audit).
2. Deploys contracts in strict nonce order with no interleaved calls.
3. Verifies every deployed address matches its precomputed value.
4. Authorizes the Audit contract to update Reputation dimensions.
5. Registers two emergency triggers (supply shortage, demand spike) and finalizes the Emergency contract setup.

The deployer EOA becomes the permanent `governance` address for Reputation and BaseAllocation.

### DeployTestnet.s.sol

Inherits from Deploy.s.sol and additionally:
- Deploys `MockPersonhood`, `MockBeacon`, and `MockPriceOracle`
- Registers the deployer as a verified person
- Enrolls the deployer in BaseAllocation

## Contract Deployment Order

Contracts are deployed in this exact sequence (nonce N+0 through N+13):

| Nonce | Contract | Key Constructor Dependencies |
|---|---|---|
| N+0 | Reputation | deployer (as governance) |
| N+1 | MetricRegistry | Sortition, Audit |
| N+2 | ParameterStore | MetricRegistry |
| N+3 | CappedGradient | ParameterStore |
| N+4 | Credit | Treasury, Levy, Audit, MetricRegistry |
| N+5 | Levy | Credit, Treasury, ParameterStore, Oracle |
| N+6 | Audit | Credit, Personhood, Treasury, Reputation, ParameterStore |
| N+7 | Sortition | Personhood, Beacon, ParameterStore, Treasury |
| N+8 | Treasury | Credit, BaseAllocation, ParameterStore, Personhood, Raffle, Audit, Sortition, Levy |
| N+9 | BaseAllocation | Treasury, ParameterStore, Personhood, deployer |
| N+10 | Raffle | Personhood, ParameterStore, Beacon, Sortition, Credit, Treasury |
| N+11 | Emergency | Sortition, MetricRegistry, ParameterStore |
| N+12 | DecayCycle | Sortition, ParameterStore |
| N+13 | BasketDefinition | Sortition, Oracle |

## Address Output

Both scripts log all deployed addresses to stdout. Example:

```
=== Abundance Protocol Deployed ===
Credit:           0x...
Reputation:       0x...
Treasury:         0x...
BaseAllocation:   0x...
CappedGradient:   0x...
Raffle:           0x...
Levy:             0x...
Audit:            0x...
Sortition:        0x...
Emergency:        0x...
DecayCycle:       0x...
MetricRegistry:   0x...
BasketDefinition: 0x...
ParameterStore:   0x...
===================================
```

Broadcast artifacts (with exact addresses and tx hashes) are saved to `broadcast/`.

## Post-Deployment Verification

After deployment, verify the wiring is correct:

```bash
# Verify Credit's treasury matches the deployed Treasury
cast call <CREDIT_ADDR> "treasury()(address)" --rpc-url <RPC_URL>

# Verify Treasury's credit matches the deployed Credit
cast call <TREASURY_ADDR> "credit()(address)" --rpc-url <RPC_URL>

# Verify Audit is authorized on Reputation
cast call <REPUTATION_ADDR> "governance()(address)" --rpc-url <RPC_URL>

# Verify Emergency is finalized
cast call <EMERGENCY_ADDR> "sortition()(address)" --rpc-url <RPC_URL>

# Verify ParameterStore returns genesis defaults
cast call <PARAMETER_STORE_ADDR> "decayPeriod()(uint256)" --rpc-url <RPC_URL>
cast call <PARAMETER_STORE_ADDR> "basketCost()(uint256)" --rpc-url <RPC_URL>
```

## Notes

- All constructor-injected addresses are `immutable`. A wiring mistake requires full redeployment.
- The deployer becomes the permanent `governance` for Reputation (controls `authorize` and `setWeight`) and BaseAllocation. Choose the deployer account accordingly (multisig recommended for production).
- ParameterStore ships with genesis defaults (see contract source). Metrics and parameter overrides are governed through Sortition panels post-deployment.
- Emergency triggers are locked after `finalizeSetup()` -- no new triggers can be added.
