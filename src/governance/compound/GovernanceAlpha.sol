pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import { BCdpManager } from "../../BCdpManager.sol";
import { Math } from "../../Math.sol";

contract GovernorAlpha is Math {

    uint public constant MAX_OPERATIONS = 10; // max 10 function calls
    uint public constant VOTING_PERIOD = 3 days;
    uint public waitingPeriod;

    TimelockInterface public timelock;
    IScoreConnector public scoreConnector;
    BCdpManager public man;

    address public guardian;
    uint public proposalCount;
    uint public deployedTimestamp;

    struct Proposal {
        uint id;
        uint startTime;
        uint eta;

        // function calls to be executed on target
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;

        // votes
        uint forVotes;
        uint againstVotes;
        
        address proposer;
        bool canceled;
        bool executed;

        mapping (uint => Receipt) receipts;
    }

    struct Receipt {
        bool hasVoted;
        bool support;
        uint votes;
    }

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    mapping (uint => Proposal) public proposals;

    event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startTime, string description);
    event VoteCast(address voter, uint proposalId, uint cdp, bool support, uint votes);
    event VoteCancelled(address voter, uint proposalId, uint cdp, uint votes);
    event ProposalCanceled(uint id);
    event ProposalQueued(uint id, uint eta);
    event ProposalExecuted(uint id);

    constructor(address timelock_, address scoreConnector_, address guardian_, uint waitingPeriod_) public {
        timelock = TimelockInterface(timelock_);
        scoreConnector = IScoreConnector(scoreConnector_);
        guardian = guardian_;
        waitingPeriod = waitingPeriod_;
        deployedTimestamp = now;
    }

    function quorumVotes(uint timestamp) public view returns (uint) { 
        return add(scoreConnector.getGlobalScore(timestamp) / 2, uint(1)); // 50% of score
    }

    function proposalThreshold(uint timestamp) public view returns (uint) {
        return add(scoreConnector.getGlobalScore(timestamp) / 100, uint(1)); // 1% of total score
    }

    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint) {
        require(now > add(deployedTimestamp, waitingPeriod), "waiting-period-not-over");
        require(msg.sender == guardian, "only-guardian-allowed-to-propose");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "array-size-mismatch");
        require(targets.length != 0, "no-actions-given");
        require(targets.length <= MAX_OPERATIONS, "too-many-actions");

        // add 15 seconds, to start this proposal from approx next block
        uint startTime = now + 15; 

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            startTime: startTime,
            eta: 0,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            forVotes: 0,
            againstVotes: 0,
            proposer: msg.sender,
            canceled: false,
            executed: false
        });

        proposals[newProposal.id] = newProposal;

        emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startTime, description);
        return newProposal.id;
    }

    function queue(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "proposal-not-succeeded");
        Proposal storage proposal = proposals[proposalId];
        uint eta = add(now, timelock.delay());
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))), "action-already-queued");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) public payable {
        require(state(proposalId) == ProposalState.Queued, "proposal-not-queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction.value(proposal.values[i])(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint proposalId) public {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed, "proposal-already-executed");

        Proposal storage proposal = proposals[proposalId];
        uint proposerTotalScore = scoreConnector.getUserTotalScore(proposal.proposer, proposal.startTime);
        require(msg.sender == guardian || proposerTotalScore < proposalThreshold(proposal.startTime), "proposer-above-threshold");

        proposal.canceled = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.cancelTransaction(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }

        emit ProposalCanceled(proposalId);
    }

    function getActions(uint proposalId) public view returns (address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas) {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function getReceipt(uint proposalId, uint cdp) public view returns (Receipt memory) {
        return proposals[proposalId].receipts[cdp];
    }

    function state(uint proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "invalid-proposal-id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (now <= proposal.startTime) {
            return ProposalState.Pending;
        } else if (now <= add(proposal.startTime, VOTING_PERIOD)) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes(proposal.startTime)) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (now >= add(proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint proposalId, uint cdp, bool support) public {
        return _castVote(msg.sender, proposalId, cdp, support);
    }

    function castVotes(uint[] calldata proposalIds, uint[] calldata cdps, bool[] calldata support) external {
        require(proposalIds.length == cdps.length, "inconsistant-array-length");
        require(cdps.length == support.length, "inconsistant-array-length");
        for(uint i = 0; i < cdps.length; i++) {
            _castVote(msg.sender, proposalIds[i], cdps[i], support[i]);
        }
    }

    function _castVote(address voter, uint proposalId, uint cdp, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "voting-is-closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[cdp];
        require(receipt.hasVoted == false, "voter-already-voted");
        require(voter == man.owns(cdp), "voter-not-owns-cdp");
        
        uint votes = scoreConnector.getPriorVotes(cdp, proposal.startTime);

        if (support) {
            proposal.forVotes = add(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add(proposal.againstVotes, votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, cdp, support, votes);
    }

    function cancelVote(uint proposalId, uint cdp) public {
        _cancelVote(msg.sender, proposalId, cdp);
    }

    function cancelVotes(uint[] calldata proposalIds, uint[] calldata cdps) external {
        require(proposalIds.length == cdps.length, "inconsistant-array-length");
        for(uint i = 0; i < cdps.length; i++) {
            _cancelVote(msg.sender, proposalIds[i], cdps[i]);
        }
    }

    function _cancelVote(address voter, uint proposalId, uint cdp) internal {
        require(state(proposalId) == ProposalState.Active, "voting-is-closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt memory receipt = proposal.receipts[cdp];
        require(receipt.hasVoted == true, "voter-not-voted");
        require(voter == man.owns(cdp), "voter-not-owns-cdp");

        uint votes = receipt.votes;
        bool support = receipt.support;
        if (support) {
            proposal.forVotes = sub(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = sub(proposal.againstVotes, votes);
        }

        delete proposal.receipts[cdp];

        emit VoteCancelled(voter, proposalId, cdp, votes);
    }

    function __acceptAdmin() public {
        require(msg.sender == guardian, "sender-must-be-gov-guardian");
        timelock.acceptAdmin();
    }

    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint eta) public {
        require(msg.sender == guardian, "sender-must-be-gov-guardian");
        timelock.queueTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }

    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint eta) public {
        require(msg.sender == guardian, "=sender-must-be-gov-guardian");
        timelock.executeTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }
}

interface TimelockInterface {
    function delay() external view returns (uint);
    function GRACE_PERIOD() external view returns (uint);
    function acceptAdmin() external;
    function queuedTransactions(bytes32 hash) external view returns (bool);
    function queueTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external returns (bytes32);
    function cancelTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external;
    function executeTransaction(address target, uint value, string calldata signature, bytes calldata data, uint eta) external payable returns (bytes memory);
}

interface IScoreConnector {
    function getPriorVotes(uint cdp, uint proposalTime) external view returns (uint);
    function getGlobalScore(uint endTime) external view returns (uint);
    function getUserTotalScore(address user, uint endTime) external view returns (uint);
}