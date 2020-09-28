pragma solidity ^0.5.12;

import { BCdpScore } from "./BCdpScore.sol";
import { BCdpManager } from "./BCdpManager.sol";
import { Math } from "./Math.sol";

interface GemJoinLike {
    function exit(address, uint) external;
}

interface VatLike {
    function gem(bytes32 ilk, address user) external view returns(uint);
}

contract JarConnector is Math {
    GemJoinLike ethJoin;
    BCdpScore   score;
    BCdpManager man;
    VatLike     vat;
    bytes32     ilk;

    // end of every round
    uint[2] public end;
    // start time of every round
    uint[2] public start;

    uint public round;

    constructor(address _manager, address _ethJoin, bytes32 _ilk, uint[2] memory _duration) public {
        man = BCdpManager(_manager);
        vat = VatLike(address(man.vat()));
        score = BCdpScore(address(man.score()));
        ethJoin = GemJoinLike(_ethJoin);
        ilk = _ilk;

        end[0] = now + _duration[0];
        end[1] = now + _duration[0] + _duration[1];

        round = 0;
    }

    // callable by anyone
    function spin() public {
        if(round == 0) {
            round++;
            score.spin();
            start[0] = score.start();
        }
        if(round == 1 && now > end[0]) {
            round++;
            score.spin();
            start[1] = score.start();
        }
        if(round == 2 && now > end[1]) {
            round++;        
            // score is not counted anymore, and this must be followed by contract upgrade
            score.spin();
        }
    }

    // callable by anyone
    function ethExit(uint wad, bytes32 ilk_) public {
        ilk_; // shh compiler wanring
        ethJoin.exit(address(this), wad);
    }

    function ethExit() public {
        ethExit(vat.gem(ilk, address(this)), ilk);
    }

    function getUserScore(bytes32 user) external view returns (uint) {
        if(round == 0) return 0;

        uint cdp = uint(user);
        if(round == 1) return _getFirstRoundUserScore(cdp, now);

        uint firstRoundScore = _getFirstRoundUserScore(cdp, start[1]);
        uint time = now;
        if(round > 2) time = end[1];

        return score.getArtScore(cdp, ilk, time, start[1]) + firstRoundScore;
    }

    function _getFirstRoundUserScore(uint cdp, uint endTime) internal view returns (uint) {
        return 2 * score.getArtScore(cdp, ilk, endTime, start[0]);
    }

    /**
     * @dev Gets user score from given endTime.
     * @notice Function is used in Governance, to avoid score fluctualtion during voting.
     *         The score is valid only from second round onwards.
     * @param endTime End time of the score
     * @return User's score from endTime to start[0]
     */
    function getUserScore(uint cdp, uint endTime) public view returns (uint) {
        require(round > 2, "governance-period-not-started");
        return score.getArtScore(cdp, ilk, endTime, start[1]) + _getFirstRoundUserScore(cdp, start[1]);
    }

    /**
     * @dev Gets user's total score for all his cdps
     * @notice Function is used in Governance
     * @param user The address of the user
     * @param endTime The end time to get the user's score
     * @return The total score of the user's all cdps
     */
    function getUserTotalScore(address user, uint endTime) public view returns (uint) {
        uint count = man.count(user);
        require(count > 0, "no-cdp-owned-by-user");

        uint first = man.first(user);
        uint totalScore = getUserScore(first, endTime);

        for(uint i = 0; i < count - 1; i++) {
            (, uint cdp) = man.list(first);
            totalScore = add(totalScore, getUserScore(cdp, endTime));
        }
        return totalScore;
    }

    function getGlobalScore() external view returns (uint) {
        if(round == 0) return 0;

        if(round == 1) return _getFirstRoundGlobalScore(now);

        uint firstRoundScore = _getFirstRoundGlobalScore(start[1]);
        uint time = now;
        if(round > 2) time = end[1];

        return score.getArtGlobalScore(ilk, time, start[1]) + firstRoundScore;
    }

    function _getFirstRoundGlobalScore(uint endTime) internal view returns (uint) {
        return 2 * score.getArtGlobalScore(ilk, endTime, start[0]);
    }

    /**
     * @dev Gets global score from given endTime.
     * @notice Function is used in Governance, to avoid score fluctualtion during voting.
     *         The score is valid only from second round onwards.
     * @param endTime End time of the score
     * @return Global score from endTime to start[0]
     */
    function getGlobalScore(uint endTime) external view returns (uint) {
        require(round > 2, "governance-period-not-started");
        return score.getArtGlobalScore(ilk, endTime, start[1]) + _getFirstRoundGlobalScore(start[1]);
    }

    function getPriorVotes(uint cdp, uint proposalTime) external view returns (uint) {
        return getUserScore(cdp, proposalTime);
    }

    function toUser(bytes32 user) external view returns (address) {
        return man.owns(uint(user));
    }
}
