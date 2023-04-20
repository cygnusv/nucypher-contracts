// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../lib/BLS12381.sol";

/**
* @title Coordinator
* @notice Coordination layer for DKG-TDec
*/
contract Coordinator is Ownable {

    // Ritual
    event StartRitual(uint32 indexed ritualId, address indexed initiator, address[] nodes);
    event StartTranscriptRound(uint32 indexed ritualId);
    event StartAggregationRound(uint32 indexed ritualId);
    // TODO: Do we want the public key here? If so, we want 2 events or do we reuse this event?
    event EndRitual(uint32 indexed ritualId, address indexed initiator, RitualState status);

    // Node
    event TranscriptCommitted(uint32 indexed ritualId, address indexed node, bytes32 transcriptDigest);
    event AggregationCommitted(uint32 indexed ritualId, address indexed node, bytes32 aggregatedTranscriptDigest);

    // Admin
    event TimeoutChanged(uint32 oldTimeout, uint32 newTimeout);
    event MaxDkgSizeChanged(uint32 oldSize, uint32 newSize);

    enum RitualState {
        NON_INITIATED,
        AWAITING_TRANSCRIPTS,
        AWAITING_AGGREGATIONS,
        TIMEOUT,
        INVALID,
        FINALIZED
    }

    uint256 public constant PUBLIC_KEY_SIZE = 48;

    struct Participant {
        address node;
        bool aggregated;
        bytes32 transcriptCommitment;
    }

    // TODO: Optimize layout
    struct Ritual {
        uint32 id;  // TODO: Redundant? ID is index of rituals array
        address initiator;
        uint32 dkgSize;
        uint32 initTimestamp;
        uint32 totalTranscripts;
        uint32 totalAggregations;
        BLS12381.G1Point publicKey;
        bytes32 aggregatedTranscriptHash;
        bool aggregationMismatch;
        bytes aggregatedTranscript;
        Participant[] participant;
    }

    Ritual[] public rituals;

    uint32 public timeout;
    uint32 public maxDkgSize;

    constructor(uint32 _timeout, uint32 _maxDkgSize) {
        timeout = _timeout;
        maxDkgSize = _maxDkgSize;
    }

    function getRitualState(uint256 ritualId) external view returns (RitualState){
        // TODO: restrict to ritualID < rituals.length?
        return getRitualState(rituals[ritualId]);
    }

    function getRitualState(Ritual storage ritual) internal view returns (RitualState){
        uint32 t0 = ritual.initTimestamp;
        uint32 deadline = t0 + timeout;
        if(t0 == 0){
            return RitualState.NON_INITIATED;
        } else if (ritual.totalAggregations == ritual.dkgSize){
            return RitualState.FINALIZED;
        } else if (ritual.aggregationMismatch){
            return RitualState.INVALID;
        } else if (block.timestamp > deadline){
            return RitualState.TIMEOUT;
        } else if (ritual.totalTranscripts < ritual.dkgSize) {
            return RitualState.AWAITING_TRANSCRIPTS;
        } else if (ritual.totalAggregations < ritual.dkgSize) {
            return RitualState.AWAITING_AGGREGATIONS;
        } else {
            // TODO: Is it possible to reach this state?
            //   - No public key
            //   - All transcripts and all aggregations
            //   - Still within the deadline
        }
    }
    

    function setTimeout(uint32 newTimeout) external onlyOwner {
        emit TimeoutChanged(timeout, newTimeout);
        timeout = newTimeout;
    }

    function setMaxDkgSize(uint32 newSize) external onlyOwner {
        emit MaxDkgSizeChanged(maxDkgSize, newSize);
        maxDkgSize = newSize;
    }

    function numberOfRituals() external view returns(uint256) {
        return rituals.length;
    }

    function getParticipants(uint32 ritualId) external view returns(Participant[] memory) {
        Ritual storage ritual = rituals[ritualId];
        return ritual.participant;
    }

    function initiateRitual(address[] calldata nodes) external returns (uint32) {
        // TODO: Validate service fees, expiration dates, threshold
        require(nodes.length <= maxDkgSize, "Invalid number of nodes");

        uint32 id = uint32(rituals.length);
        Ritual storage ritual = rituals.push();
        ritual.id = id;  // TODO: Possibly redundant
        ritual.initiator = msg.sender;  // TODO: Consider sponsor model
        ritual.dkgSize = uint32(nodes.length);
        ritual.initTimestamp = uint32(block.timestamp);

        address previousNode = address(0);
        for(uint256 i=0; i < nodes.length; i++){
            Participant storage newParticipant = ritual.participant.push();
            address currentNode = nodes[i];
            newParticipant.node = currentNode;
            require(previousNode < currentNode, "Nodes must be sorted");
            previousNode = currentNode;
            // TODO: Check nodes are eligible (staking, etc)
        }
        // TODO: Compute cohort fingerprint as hash(nodes)

        emit StartRitual(id, msg.sender, nodes);
        emit StartTranscriptRound(id);
        return ritual.id;
    }

    function commitToTranscript(uint32 ritualId, uint256 nodeIndex, bytes32 transcriptCommitment) external {
        Ritual storage ritual = rituals[ritualId];
        require(
            getRitualState(ritual) == RitualState.AWAITING_TRANSCRIPTS,
            "Not waiting for transcripts"
        );
        Participant storage participant = ritual.participant[nodeIndex];
        require(
            participant.node == msg.sender,
            "Node not part of ritual"
        );
        require(
            participant.transcriptCommitment == bytes32(0),
            "Node already posted transcript"
        );

        // Nodes commit to their transcript
        participant.transcriptCommitment = transcriptCommitment;
        emit TranscriptCommitted(ritualId, msg.sender, transcriptCommitment);
        ritual.totalTranscripts++;

        // end round
        if (ritual.totalTranscripts == ritual.dkgSize){
            emit StartAggregationRound(ritualId);
        }
    }

    function commitToAggregation(
        uint32 ritualId,
        uint256 nodeIndex,
        bytes32 aggregatedTranscriptCommittment,
        BLS12381.G1Point calldata publicKey
    ) external {
        Ritual storage ritual = rituals[ritualId];
        require(
            getRitualState(ritual) == RitualState.AWAITING_AGGREGATIONS,
            "Not waiting for aggregations"
        );
        Participant storage participant = ritual.participant[nodeIndex];
        require(
            participant.node == msg.sender,
            "Node not part of ritual"
        );
        require(
            !participant.aggregated,
            "Node already posted aggregation"
        );

        // nodes commit to their aggregation result
        participant.aggregated = true;
        emit AggregationCommitted(ritualId, msg.sender, aggregatedTranscriptCommittment);

        if (ritual.aggregatedTranscriptHash == bytes32(0)){
            ritual.aggregatedTranscriptHash = aggregatedTranscriptCommittment;
            ritual.publicKey = publicKey;
        } else if (
            !BLS12381.eqG1Point(ritual.publicKey, publicKey) || 
            ritual.aggregatedTranscriptHash != aggregatedTranscriptCommittment
        ){
            ritual.aggregationMismatch = true;
            emit EndRitual(ritualId, ritual.initiator, RitualState.INVALID);
            // TODO: Invalid ritual
            // TODO: Consider freeing ritual storage
            return;
        }
        
        ritual.totalAggregations++;
        
        // end round - Last node posting aggregation will finalize 
        if (ritual.totalAggregations == ritual.dkgSize){
            emit EndRitual(ritualId, ritual.initiator, RitualState.FINALIZED);
        }
    }
}
