pragma solidity ^0.5.12;

import { ScoringConfig } from "../user-rating/contracts/score/ScoringConfig.sol";

contract BScoringConfig is ScoringConfig {

    constructor(
        uint256 _debtScoreFactor,
        uint256 _collScoreFactor,
        uint256 _slashedScoreFactor,
        uint256 _slasherScoreFactor,
        address _scoringMachine
    ) 
        public 
        ScoringConfig(
            _debtScoreFactor,
            _collScoreFactor,
            _slashedScoreFactor,
            _slasherScoreFactor,
            _scoringMachine
        )
    {}

    // @override
    function getUserDebtScore(address user, address token) internal view returns (uint256) {

    }

    function getUserCollScore(address user, address token) internal view returns (uint256) {
    }

    function getUserSlashedScore(address user, address token) internal view returns (uint256) {
    }

    function getUserSlasherScore(address user, address token) internal view returns (uint256) {
    }

    function getGlobalDebtScore(address token) internal view returns (uint256) {
    }

    function getGlobalCollScore(address token) internal view returns (uint256) {
    }

    function getGlobalSlashedScore(address token) internal view returns (uint256) {
    }

    function getGlobalSlasherScore(address token) internal view returns (uint256) {
    }

    /**
     * @dev Get instance of ScoringMachine for Compound
     * @return BCdpScoreLike
     */
    function getScoringMachine() internal view returns (BCdpScoreLike) {
        return BCdpScoreLike(scoringMachine);
    }
}

interface BCdpScoreLike {
    
}