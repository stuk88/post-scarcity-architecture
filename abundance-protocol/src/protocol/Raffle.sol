// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRaffle} from "../interfaces/IRaffle.sol";
import {IRandomnessBeacon} from "../interfaces/IRandomnessBeacon.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {ISortition} from "../interfaces/ISortition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Raffle is IRaffle, ReentrancyGuard {
    IPersonhood public immutable personhood;
    IParameterStore public immutable parameterStore;
    IRandomnessBeacon public immutable beacon;
    ISortition public immutable sortition;
    IERC20 public immutable credit;
    address public immutable treasury;

    uint256 internal constant WAD = 1e18;

    uint256 private _nextProposalId = 1;
    uint256 private _period = 1;

    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => uint256) private _proposalPeriod;

    struct PoolData {
        PoolState state;
        uint256[] proposalIds;
        uint256 median;
        uint256 seedRequestId;
    }

    mapping(uint8 => mapping(uint256 => PoolData)) private _pools;

    mapping(uint256 => bool) private _winners;

    mapping(bytes32 => uint256) private _megaprojectPanelIds;

    mapping(uint8 => mapping(uint256 => uint256)) private _poolOpenedAt;

    constructor(
        address personhood_,
        address parameterStore_,
        address beacon_,
        address sortition_,
        address credit_,
        address treasury_
    ) {
        require(personhood_ != address(0), "Raffle: zero personhood");
        require(parameterStore_ != address(0), "Raffle: zero parameterStore");
        require(beacon_ != address(0), "Raffle: zero beacon");
        require(sortition_ != address(0), "Raffle: zero sortition");
        require(credit_ != address(0), "Raffle: zero credit");
        require(treasury_ != address(0), "Raffle: zero treasury");

        personhood = IPersonhood(personhood_);
        parameterStore = IParameterStore(parameterStore_);
        beacon = IRandomnessBeacon(beacon_);
        sortition = ISortition(sortition_);
        credit = IERC20(credit_);
        treasury = treasury_;
    }

    function submit(Proposal calldata proposal) external returns (uint256 proposalId) {
        require(
            proposal.proposerId == bytes32(uint256(uint160(msg.sender))),
            "Raffle: not proposer"
        );
        require(personhood.isUniquePerson(proposal.proposerId), "Raffle: proposer not verified");
        require(proposal.contentHash != bytes32(0), "Raffle: content hash required");
        require(proposal.requestedAmount > 0, "Raffle: amount required");
        require(proposal.milestonesCount > 0, "Raffle: milestones required");
        require(uint8(proposal.tier) <= uint8(Tier.Megaproject), "Raffle: invalid tier");

        uint8 tierIdx = uint8(proposal.tier);
        PoolData storage pool = _pools[tierIdx][_period];
        require(pool.state == PoolState.Open, "Raffle: pool not open");

        if (proposal.tier == Tier.Megaproject) {
            uint256 panelId = _megaprojectPanelIds[proposal.contentHash];
            require(panelId != 0, "Raffle: megaproject not approved");
        }

        proposalId = _nextProposalId++;
        _proposals[proposalId] = Proposal({
            proposerId: proposal.proposerId,
            contentHash: proposal.contentHash,
            requestedAmount: proposal.requestedAmount,
            tier: proposal.tier,
            milestonesCount: proposal.milestonesCount,
            submittedAt: block.timestamp
        });
        _proposalPeriod[proposalId] = _period;

        pool.proposalIds.push(proposalId);

        if (pool.proposalIds.length == 1) {
            _poolOpenedAt[tierIdx][_period] = block.timestamp;
        }

        emit ProposalSubmitted(proposalId, proposal.proposerId, proposal.tier, proposal.requestedAmount);

        if (proposal.tier == Tier.Megaproject) {
            emit MegaprojectApproved(proposalId, _megaprojectPanelIds[proposal.contentHash]);
        }
    }

    function closeEntries(Tier tier) external {
        uint8 tierIdx = uint8(tier);
        PoolData storage pool = _pools[tierIdx][_period];
        require(pool.state == PoolState.Open, "Raffle: pool not open");
        require(pool.proposalIds.length > 0, "Raffle: no entries");

        uint256 openedAt = _poolOpenedAt[tierIdx][_period];
        require(block.timestamp >= openedAt + 86400, "Raffle: pool still in submission window");

        pool.state = PoolState.Frozen;

        uint256 n = pool.proposalIds.length;
        uint256[] memory asks = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            asks[i] = _proposals[pool.proposalIds[i]].requestedAmount;
        }
        pool.median = _computeMedian(asks);

        pool.seedRequestId = beacon.requestSeed();

        emit EntriesClosed(tier, _period, n);
    }

    function draw(Tier tier) external nonReentrant returns (uint256[] memory winnerIds) {
        PoolData storage pool = _pools[uint8(tier)][_period];

        require(pool.state == PoolState.Frozen, "Raffle: entries not frozen");
        require(beacon.isFulfilled(pool.seedRequestId), "Raffle: seed not fulfilled");

        uint256 seed = beacon.getSeed(pool.seedRequestId);
        uint256[] memory ids = pool.proposalIds;
        uint256 median = pool.median;

        uint256 numSlots = parameterStore.poolBudget(uint8(tier)) / median;
        if (numSlots > ids.length) {
            numSlots = ids.length;
        }

        (uint256[] memory weights, uint256 totalWeight) = _computeWeights(ids, median);
        winnerIds = _selectWinners(ids, seed, numSlots, weights, totalWeight);

        pool.state = PoolState.Drawn;
        emit DrawCompleted(tier, _period, winnerIds, seed);
    }

    function returnSurplus(uint256 proposalId, uint256 amount) external nonReentrant {
        require(_winners[proposalId], "Raffle: not a winner");
        require(amount > 0, "Raffle: zero amount");
        require(credit.transferFrom(msg.sender, treasury, amount), "Raffle: transfer failed");
        emit SurplusReturned(proposalId, amount);
    }

    // ── Views ──

    function overAskWeight(uint256 proposalId) external view returns (uint256) {
        Proposal storage p = _proposals[proposalId];
        require(p.requestedAmount > 0, "Raffle: proposal not found");

        uint256 period = _proposalPeriod[proposalId];
        PoolData storage pool = _pools[uint8(p.tier)][period];
        require(pool.state != PoolState.Open, "Raffle: pool not frozen yet");

        if (p.requestedAmount <= pool.median) {
            return WAD;
        }
        return (pool.median * WAD) / p.requestedAmount;
    }

    function poolState(Tier tier) external view returns (PoolState) {
        return _pools[uint8(tier)][_period].state;
    }

    function entryCount(Tier tier) external view returns (uint256) {
        return _pools[uint8(tier)][_period].proposalIds.length;
    }

    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return _proposals[proposalId];
    }

    function currentPeriod() external view returns (uint256) {
        return _period;
    }

    // ── Megaproject approval ──

    function registerMegaprojectApproval(bytes32 contentHash, uint256 panelId) external {
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        require(resolved, "Raffle: panel not resolved");
        require(approved, "Raffle: panel not approved");

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("raffle.megaproject", contentHash));
        require(panel.purpose == expectedPurpose, "Raffle: wrong panel purpose");

        _megaprojectPanelIds[contentHash] = panelId;
    }

    // ── Period management ──

    function advancePeriod(uint256 panelId) external {
        (bool resolved, bool approved) = sortition.isResolved(panelId);
        require(resolved && approved, "Raffle: panel not approved");

        ISortition.Panel memory panel = sortition.getPanel(panelId);
        bytes32 expectedPurpose = keccak256(abi.encode("raffle.advancePeriod", _period));
        require(panel.purpose == expectedPurpose, "Raffle: wrong panel purpose");

        _period++;
    }

    // ── Internal ──

    function _computeWeights(uint256[] memory ids, uint256 median)
        internal
        view
        returns (uint256[] memory weights, uint256 totalWeight)
    {
        weights = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 ask = _proposals[ids[i]].requestedAmount;
            if (ask <= median) {
                weights[i] = WAD;
            } else {
                weights[i] = (median * WAD) / ask;
            }
            totalWeight += weights[i];
        }
    }

    function _selectWinners(
        uint256[] memory ids,
        uint256 seed,
        uint256 numSlots,
        uint256[] memory weights,
        uint256 totalWeight
    ) internal returns (uint256[] memory winnerIds) {
        winnerIds = new uint256[](numSlots);
        bool[] memory selected = new bool[](ids.length);
        uint256 winnersFound;

        for (uint256 drawIndex; drawIndex < numSlots * 10 && winnersFound < numSlots; drawIndex++) {
            uint256 randomPoint = uint256(keccak256(abi.encode(seed, drawIndex))) % totalWeight;

            uint256 cumulative;
            for (uint256 i; i < ids.length; i++) {
                cumulative += weights[i];
                if (randomPoint < cumulative) {
                    if (!selected[i]) {
                        selected[i] = true;
                        winnerIds[winnersFound] = ids[i];
                        _winners[ids[i]] = true;
                        winnersFound++;
                    }
                    break;
                }
            }
        }

        if (winnersFound < numSlots) {
            assembly {
                mstore(winnerIds, winnersFound)
            }
        }
    }

    function _computeMedian(uint256[] memory values) internal pure returns (uint256) {
        uint256 n = values.length;
        if (n == 1) return values[0];
        if (n == 2) return (values[0] >> 1) + (values[1] >> 1) + (values[0] & values[1] & 1);

        uint256 mid = n / 2;
        _nthElement(values, 0, n, mid);

        if (n % 2 == 1) {
            return values[mid];
        }
        uint256 leftMax = values[0];
        for (uint256 i = 1; i < mid; i++) {
            if (values[i] > leftMax) leftMax = values[i];
        }
        return (leftMax >> 1) + (values[mid] >> 1) + (leftMax & values[mid] & 1);
    }

    function _nthElement(uint256[] memory arr, uint256 lo, uint256 hi, uint256 k) internal pure {
        while (hi - lo > 1) {
            uint256 pivotIdx = _partition(arr, lo, hi);
            if (k == pivotIdx) return;
            if (k < pivotIdx) {
                hi = pivotIdx;
            } else {
                lo = pivotIdx + 1;
            }
        }
    }

    function _partition(uint256[] memory arr, uint256 lo, uint256 hi) internal pure returns (uint256) {
        uint256 mid = lo + (hi - lo) / 2;
        (arr[mid], arr[hi - 1]) = (arr[hi - 1], arr[mid]);
        uint256 pivot = arr[hi - 1];
        uint256 i = lo;
        for (uint256 j = lo; j < hi - 1; j++) {
            if (arr[j] <= pivot) {
                (arr[i], arr[j]) = (arr[j], arr[i]);
                i++;
            }
        }
        (arr[i], arr[hi - 1]) = (arr[hi - 1], arr[i]);
        return i;
    }
}
