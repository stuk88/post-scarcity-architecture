// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISortition} from "../interfaces/ISortition.sol";
import {IPersonhood} from "../interfaces/IPersonhood.sol";
import {IRandomnessBeacon} from "../interfaces/IRandomnessBeacon.sol";
import {IParameterStore} from "../interfaces/IParameterStore.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";

contract Sortition is ISortition {
    IPersonhood public immutable personhood;
    IRandomnessBeacon public immutable beacon;
    IParameterStore public immutable params;
    ITreasury public immutable treasury;

    uint256 internal _panelCount;
    mapping(uint256 => Panel) internal _panels;
    mapping(uint256 => mapping(bytes32 => bool)) internal _voted;
    mapping(uint256 => mapping(bytes32 => bool)) internal _isMember;
    mapping(uint256 => uint256) internal _seedRequestId;
    mapping(uint256 => bool) internal _panelApproved;
    mapping(uint256 => uint256) internal _requestedSize;

    bytes32[] internal _registeredPersons;
    mapping(bytes32 => bool) internal _isRegistered;
    mapping(bytes32 => address) internal _personToAddress;

    error PanelNotActive(uint256 panelId);
    error NotPanelMember(uint256 panelId, bytes32 memberId);
    error AlreadyVoted(uint256 panelId, bytes32 memberId);
    error PanelNotExpired(uint256 panelId);
    error PanelSizeZero();
    error SeedNotFulfilled(uint256 requestId);
    error NotEnoughRegisteredPersons(uint256 required, uint256 available);
    error PanelAlreadyResolved(uint256 panelId);
    error NotEnoughVotesForKill(uint256 panelId);
    error NotAuthorized();
    error AlreadyRegistered();
    error NotVerifiedPerson();
    error SelectionFailed();
    error ZeroAddress();
    error PanelNotPendingDraw(uint256 panelId);

    constructor(address _personhood, address _beacon, address _params, address _treasury) {
        if (_personhood == address(0)) revert ZeroAddress();
        if (_beacon == address(0)) revert ZeroAddress();
        if (_params == address(0)) revert ZeroAddress();
        if (_treasury == address(0)) revert ZeroAddress();
        personhood = IPersonhood(_personhood);
        beacon = IRandomnessBeacon(_beacon);
        params = IParameterStore(_params);
        treasury = ITreasury(_treasury);
    }

    function registerForSortition(bytes32 personId) external {
        if (personId != bytes32(uint256(uint160(msg.sender)))) revert NotAuthorized();
        if (!personhood.isUniquePerson(personId)) revert NotVerifiedPerson();
        if (_isRegistered[personId]) revert AlreadyRegistered();
        _personToAddress[personId] = msg.sender;
        _isRegistered[personId] = true;
        _registeredPersons.push(personId);
    }

    function requestPanel(bytes32 purpose, uint256 size) public returns (uint256 panelId) {
        if (size == 0) revert PanelSizeZero();
        uint256 poolSize = _registeredPersons.length;
        if (poolSize < size) revert NotEnoughRegisteredPersons(size, poolSize);

        uint256 requestId = beacon.requestSeed();

        panelId = _panelCount++;
        _requestedSize[panelId] = size;
        _seedRequestId[panelId] = requestId;

        _panels[panelId] = Panel({
            panelId: panelId,
            members: new bytes32[](0),
            createdAt: 0,
            expiresAt: 0,
            purpose: purpose,
            state: PanelState.PendingDraw,
            votesFor: 0,
            votesAgainst: 0
        });

        emit PanelRequested(panelId, purpose, size);
    }

    function finalizePanel(uint256 panelId) public {
        Panel storage panel = _panels[panelId];
        if (panel.state != PanelState.PendingDraw) revert PanelNotPendingDraw(panelId);

        uint256 requestId = _seedRequestId[panelId];
        if (!beacon.isFulfilled(requestId)) revert SeedNotFulfilled(requestId);
        uint256 seed = beacon.getSeed(requestId);

        uint256 size = _requestedSize[panelId];
        uint256 poolSize = _registeredPersons.length;
        bytes32[] memory members = _selectMembers(seed, size, poolSize);

        uint256 duration = params.emergencyDuration();
        panel.members = members;
        panel.createdAt = block.number;
        panel.expiresAt = block.number + duration;
        panel.state = PanelState.Active;

        for (uint256 i = 0; i < members.length; i++) {
            _isMember[panelId][members[i]] = true;
            treasury.fundRole(members[i], panelId);
        }

        emit PanelDrawn(panelId, panel.purpose, size, seed);
    }

    function drawPanel(bytes32 purpose, uint256 size) external returns (uint256 panelId) {
        panelId = requestPanel(purpose, size);
        finalizePanel(panelId);
    }

    function vote(uint256 panelId, bytes32 memberId, bool approve) external {
        Panel storage panel = _panels[panelId];
        if (panel.state != PanelState.Active) revert PanelNotActive(panelId);
        if (block.number >= panel.expiresAt) revert PanelNotActive(panelId);
        if (!_isMember[panelId][memberId]) revert NotPanelMember(panelId, memberId);
        if (_voted[panelId][memberId]) revert AlreadyVoted(panelId, memberId);
        if (_personToAddress[memberId] != msg.sender) revert NotAuthorized();

        _voted[panelId][memberId] = true;

        if (approve) {
            panel.votesFor++;
        } else {
            panel.votesAgainst++;
        }

        emit VoteCast(panelId, memberId, approve);
        _checkResolution(panelId);
    }

    function killSwitch(uint256 panelId) external {
        Panel storage panel = _panels[panelId];
        if (panel.state != PanelState.Active) revert PanelNotActive(panelId);
        uint256 totalMembers = panel.members.length;
        if (panel.votesAgainst * 10_000 <= totalMembers * 3333) {
            revert NotEnoughVotesForKill(panelId);
        }
        panel.state = PanelState.Resolved;
        _panelApproved[panelId] = false;
        emit PanelKilled(panelId, bytes32(uint256(uint160(msg.sender))));
        emit PanelResolved(panelId, false);
    }

    function expirePanel(uint256 panelId) external {
        Panel storage panel = _panels[panelId];
        if (panel.state != PanelState.Active) revert PanelAlreadyResolved(panelId);
        if (block.number < panel.expiresAt) revert PanelNotExpired(panelId);
        panel.state = PanelState.Expired;
        emit PanelExpired(panelId);
    }

    function isResolved(uint256 panelId) external view returns (bool resolved, bool approved) {
        Panel storage panel = _panels[panelId];
        if (panel.state == PanelState.Resolved) {
            resolved = true;
            approved = _panelApproved[panelId];
        }
    }

    function getPanel(uint256 panelId) external view returns (Panel memory) {
        return _panels[panelId];
    }

    function hasVoted(uint256 panelId, bytes32 memberId) external view returns (bool) {
        return _voted[panelId][memberId];
    }

    function panelCount() external view returns (uint256) {
        return _panelCount;
    }

    function registeredCount() external view returns (uint256) {
        return _registeredPersons.length;
    }

    function _checkResolution(uint256 panelId) internal {
        Panel storage panel = _panels[panelId];
        uint256 totalVotes = panel.votesFor + panel.votesAgainst;
        if (totalVotes == panel.members.length) {
            panel.state = PanelState.Resolved;
            uint256 threshold = params.supermajorityThreshold();
            bool approved = panel.votesFor * 10_000 >= panel.members.length * threshold;
            _panelApproved[panelId] = approved;
            emit PanelResolved(panelId, approved);
        }
    }

    function _selectMembers(uint256 seed, uint256 size, uint256 poolSize)
        internal
        view
        returns (bytes32[] memory members)
    {
        members = new bytes32[](size);
        uint256 selected = 0;
        uint256 maxIter = poolSize * 3;

        for (uint256 nonce = 0; selected < size; nonce++) {
            if (nonce >= maxIter) revert SelectionFailed();
            uint256 index = uint256(keccak256(abi.encode(seed, nonce))) % poolSize;
            bytes32 candidate = _registeredPersons[index];

            if (!personhood.isUniquePerson(candidate)) continue;

            bool dup = false;
            for (uint256 j = 0; j < selected; j++) {
                if (members[j] == candidate) {
                    dup = true;
                    break;
                }
            }
            if (dup) continue;

            members[selected++] = candidate;
        }
    }
}
