pragma solidity ^0.5.12;


import { DSAuth } from "ds-auth/auth.sol";
import { Math } from "./Math.sol";

contract ScoringMachine is DSAuth, Math {
    // get out of the user rating system - TODO - move to scoring machine
    mapping (bytes32 => bool) public out;

    struct AssetScore {
        // total score so far
        uint score;

        // current balance
        uint balance;

        // time when last update was
        uint last;
    }

    // user is bytes32 (will be the sha3 of address or cdp number)
    mapping(bytes32 => mapping(bytes32 => AssetScore[])) checkpoints;

    mapping(bytes32 => mapping(bytes32 => AssetScore)) userScore;

    bytes32 constant public GLOBAL_USER = bytes32(0x0);

    uint public start; // start time of the campaign;

    function spin() external auth { // start a new round
        start = now;
    }

    function assetScore(AssetScore storage score, uint time) internal view returns(uint) {
        uint last = score.last;
        if(last == 0) last = start;

        return add(score.score, mul(score.balance, sub(time,last)));
    }

    function addCheckpoint(bytes32 user, bytes32 asset) internal {
        checkpoints[user][asset].push(userScore[user][asset]);
    }

    function slashAssetScore(bytes32 user, bytes32 asset, int dbalance, uint time) internal {
        AssetScore storage score = userScore[user][asset];
        int dscore = mul(sub(time,start),dbalance);

        score.score = add(score.score, dscore);
        score.balance = add(score.balance, dbalance);
    }

    function updateAssetScore(bytes32 user, bytes32 asset, int dbalance, uint time) internal {
        AssetScore storage score = userScore[user][asset];

        uint last = score.last;
        if(last < start) {
            addCheckpoint(user,asset);
            last = start;
        }

        score.score = assetScore(score, time);
        score.balance = add(score.balance, dbalance);
        score.last = time;
    }

    function updateScore(bytes32 user, bytes32 asset, int dbalance, uint time) internal {
        if(out[user]) return;

        updateAssetScore(user,asset,dbalance,time);
        updateAssetScore(GLOBAL_USER,asset,dbalance,time);
    }

    function getScore(bytes32 user, bytes32 asset, uint time, uint checkPointHint) public view returns(uint score) {
        if(time >= userScore[user][asset].last) return assetScore(userScore[user][asset],time);

        // else - check the checkpoints

        // hint is invalid
        if(checkpoints[user][asset][checkPointHint].last < time) checkPointHint = checkpoints[user][asset].length;

        for(uint i = checkPointHint ; ; i--){
            if(checkpoints[user][asset][i].last <= time) return assetScore(checkpoints[user][asset][i],time);
        }

        // this supposed to be unreachable
        return 0;
    }

    function slash(bytes32 user, bytes32 asset, int dbalance, uint time) external auth {
        slashAssetScore(user,asset,dbalance,time);
        slashAssetScore(GLOBAL_USER,asset,dbalance,time);
    }
}
