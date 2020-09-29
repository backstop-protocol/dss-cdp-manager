pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import { BCdpManager } from "../../BCdpManager.sol";

contract GovernorAlpha {

    /// @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorumVotes(uint timestamp) public view returns (uint) { 
        return add256(scoreConnector.getGlobalScore(timestamp) / 2, 1); // 50% of score
    }

    /// @notice The number of votes required in order for a voter to become a proposer
    function proposalThreshold(uint timestamp) public view returns (uint) {
        return add256(scoreConnector.getGlobalScore(timestamp) / 100, 1); // 1% of total score
    }

    /// @notice The maximum number of actions that can be included in a proposal
    function proposalMaxOperations() public pure returns (uint) { return 10; } // 10 actions

    /// @notice The delay before voting on a proposal may take place, once proposed
    function votingDelay() public pure returns (uint) { return 1; } // 1 block

    /// @notice The duration of voting on a proposal, in blocks
    function votingPeriod() public pure returns (uint) { return 17280; } // ~3 days in blocks (assuming 15s blocks)

    uint public constant WAITING_PERIOD = 6 * 30 days; // approx 6 months
    
    TimelockInterface public timelock;
    IScoreConnector public scoreConnector;
    BCdpManager public man;

    address public guardian;
    uint public proposalCount;
    uint public deployedTimestamp;

    struct Proposal {
        uint id;
        uint timestamp;
        address proposer;
        uint eta;

        // function calls to be executed on target
        address[] targets;
        uint[] values;
        string[] signatures;
        bytes[] calldatas;

        uint startBlock;
        uint endBlock;

        // votes
        uint forVotes;
        uint againstVotes;

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

    event ProposalCreated(uint id, address proposer, address[] targets, uint[] values, string[] signatures, bytes[] calldatas, uint startBlock, uint endBlock, string description);
    event VoteCast(address voter, uint proposalId, uint cdp, bool support, uint votes);
    event VoteCancelled(address voter, uint proposalId, uint cdp, uint votes);
    event ProposalCanceled(uint id);
    event ProposalQueued(uint id, uint eta);
    event ProposalExecuted(uint id);

    constructor(address timelock_, address scoreConnector_, address guardian_) public {
        timelock = TimelockInterface(timelock_);
        scoreConnector = IScoreConnector(scoreConnector_);
        guardian = guardian_;
        deployedTimestamp = now;
    }

    function propose(address[] memory targets, uint[] memory values, string[] memory signatures, bytes[] memory calldatas, string memory description) public returns (uint) {
        require(now > add256(deployedTimestamp, WAITING_PERIOD), "waiting-period-not-over");
        require(msg.sender == guardian, "only-guardian-allowed-to-propose");
        uint proposerTotalScore = scoreConnector.getUserTotalScore(msg.sender, now);
        require(proposerTotalScore > proposalThreshold(now), "GovernorAlpha::propose: proposer votes below proposal threshold");
        require(targets.length == values.length && targets.length == signatures.length && targets.length == calldatas.length, "GovernorAlpha::propose: proposal function information arity mismatch");
        require(targets.length != 0, "GovernorAlpha::propose: must provide actions");
        require(targets.length <= proposalMaxOperations(), "GovernorAlpha::propose: too many actions");

        uint startBlock = add256(block.number, votingDelay());
        uint endBlock = add256(startBlock, votingPeriod());

        proposalCount++;
        Proposal memory newProposal = Proposal({
            id: proposalCount,
            timestamp: now,
            proposer: msg.sender,
            eta: 0,
            targets: targets,
            values: values,
            signatures: signatures,
            calldatas: calldatas,
            startBlock: startBlock,
            endBlock: endBlock,
            forVotes: 0,
            againstVotes: 0,
            canceled: false,
            executed: false
        });

        proposals[newProposal.id] = newProposal;

        emit ProposalCreated(newProposal.id, msg.sender, targets, values, signatures, calldatas, startBlock, endBlock, description);
        return newProposal.id;
    }

    function queue(uint proposalId) public {
        require(state(proposalId) == ProposalState.Succeeded, "GovernorAlpha::queue: proposal can only be queued if it is succeeded");
        Proposal storage proposal = proposals[proposalId];
        uint eta = add256(block.timestamp, timelock.delay());
        for (uint i = 0; i < proposal.targets.length; i++) {
            _queueOrRevert(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], eta);
        }
        proposal.eta = eta;
        emit ProposalQueued(proposalId, eta);
    }

    function _queueOrRevert(address target, uint value, string memory signature, bytes memory data, uint eta) internal {
        require(!timelock.queuedTransactions(keccak256(abi.encode(target, value, signature, data, eta))), "GovernorAlpha::_queueOrRevert: proposal action already queued at eta");
        timelock.queueTransaction(target, value, signature, data, eta);
    }

    function execute(uint proposalId) public payable {
        require(state(proposalId) == ProposalState.Queued, "GovernorAlpha::execute: proposal can only be executed if it is queued");
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        for (uint i = 0; i < proposal.targets.length; i++) {
            timelock.executeTransaction.value(proposal.values[i])(proposal.targets[i], proposal.values[i], proposal.signatures[i], proposal.calldatas[i], proposal.eta);
        }
        emit ProposalExecuted(proposalId);
    }

    function cancel(uint proposalId) public {
        ProposalState state = state(proposalId);
        require(state != ProposalState.Executed, "GovernorAlpha::cancel: cannot cancel executed proposal");

        Proposal storage proposal = proposals[proposalId];
        uint proposerTotalScore = scoreConnector.getUserTotalScore(proposal.proposer, proposal.timestamp);
        require(msg.sender == guardian || proposerTotalScore < proposalThreshold(proposal.timestamp), "GovernorAlpha::cancel: proposer above threshold");

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
        require(proposalCount >= proposalId && proposalId > 0, "GovernorAlpha::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorumVotes(proposal.timestamp)) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= add256(proposal.eta, timelock.GRACE_PERIOD())) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    function castVote(uint proposalId, uint cdp, bool support) public {
        return _castVote(msg.sender, proposalId, cdp, support);
    }

    function castVotes(uint[] calldata proposalIds, uint[] calldata cdps, bool[] calldata support) external {
        require(proposalIds.length == cdps.length, "GovernorAlpha::castVotes: inconsistant array length");
        require(cdps.length == support.length, "GovernorAlpha::castVotes: inconsistant array length");
        for(uint i = 0; i < cdps.length; i++) {
            _castVote(msg.sender, proposalIds[i], cdps[i], support[i]);
        }
    }

    function _castVote(address voter, uint proposalId, uint cdp, bool support) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[cdp];
        require(receipt.hasVoted == false, "GovernorAlpha::_castVote: voter already voted");
        require(voter == man.owns(cdp), "GovernorAlpha::_castVote: voter not owns cdp");
        
        uint votes = scoreConnector.getPriorVotes(cdp, proposal.timestamp);

        if (support) {
            proposal.forVotes = add256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = add256(proposal.againstVotes, votes);
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
        require(proposalIds.length == cdps.length, "GovernorAlpha::cancelVotes: inconsistant array length");
        for(uint i = 0; i < cdps.length; i++) {
            _cancelVote(msg.sender, proposalIds[i], cdps[i]);
        }
    }

    function _cancelVote(address voter, uint proposalId, uint cdp) internal {
        require(state(proposalId) == ProposalState.Active, "GovernorAlpha::_castVote: voting is closed");
        Proposal storage proposal = proposals[proposalId];
        Receipt memory receipt = proposal.receipts[cdp];
        require(receipt.hasVoted == true, "GovernorAlpha::_castVote: voter not voted");
        require(voter == man.owns(cdp), "GovernorAlpha::_castVote: voter not owns cdp");

        uint votes = receipt.votes;
        bool support = receipt.support;
        if (support) {
            proposal.forVotes = sub256(proposal.forVotes, votes);
        } else {
            proposal.againstVotes = sub256(proposal.againstVotes, votes);
        }

        delete proposal.receipts[cdp];

        emit VoteCancelled(voter, proposalId, cdp, votes);
    }

    function __acceptAdmin() public {
        require(msg.sender == guardian, "GovernorAlpha::__acceptAdmin: sender must be gov guardian");
        timelock.acceptAdmin();
    }

    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint eta) public {
        require(msg.sender == guardian, "GovernorAlpha::__queueSetTimelockPendingAdmin: sender must be gov guardian");
        timelock.queueTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }

    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint eta) public {
        require(msg.sender == guardian, "GovernorAlpha::__executeSetTimelockPendingAdmin: sender must be gov guardian");
        timelock.executeTransaction(address(timelock), 0, "setPendingAdmin(address)", abi.encode(newPendingAdmin), eta);
    }

    function add256(uint256 a, uint256 b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "addition overflow");
        return c;
    }

    function sub256(uint256 a, uint256 b) internal pure returns (uint) {
        require(b <= a, "subtraction underflow");
        return a - b;
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