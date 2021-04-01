pragma solidity ^0.5.12;

import { BCdpScore } from "./BCdpScore.sol";
import { BCdpManager } from "./BCdpManager.sol";
import { Math } from "./Math.sol";

contract JarConnector is Math {
    BCdpScore   public score;
    BCdpManager public man;
    bytes32[]   public ilks;
    // ilk => supported
    mapping(bytes32 => bool) public milks;

    // end of every round
    uint[2] public end;
    // start time of every round
    uint[2] public start;

    uint public round;

    constructor(
        bytes32[] memory _ilks,
        uint[2] memory _duration
    ) public {
        ilks = _ilks;

        for(uint i = 0; i < _ilks.length; i++) {
            milks[_ilks[i]] = true;
        }

        end[0] = now + _duration[0];
        end[1] = now + _duration[0] + _duration[1];

        round = 0;
    }

    function setManager(address _manager) public {
        require(man == BCdpManager(0), "manager-already-set");
        man = BCdpManager(_manager);
        score = BCdpScore(address(man.score()));
    }

    function getUserScore(bytes32 user) external view returns (uint) {
        // TODO
    }

    function getGlobalScore() external view returns (uint) {
        // TODO
    }

    function toUser(bytes32 user) external view returns (address) {
        return man.owns(uint(user));
    }
}
