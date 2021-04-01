pragma solidity ^0.5.12;

import { ScoringMachine } from "../user-rating/contracts/score/ScoringMachine.sol";
import { BCdpManager } from "./BCdpManager.sol";
import { LiquidationMachine } from "./LiquidationMachine.sol";
import { BCdpScoreConnector } from "./BCdpScoreConnector.sol";

contract BCdpScore is ScoringMachine {
    BCdpManager public manager;

    modifier onlyManager {
        require(msg.sender == address(manager), "not-manager");
        _;
    }

    function setManager(address newManager) external onlyOwner {
        manager = BCdpManager(newManager);
    }

    function user(uint cdp) public pure returns(bytes32) {
        return keccak256(abi.encodePacked("BCdpScore", cdp));
    }

    function artAsset(bytes32 ilk) public pure returns(bytes32) {
        return keccak256(abi.encodePacked("BCdpScore", "art", ilk));
    }

    function updateScore(uint cdp, bytes32 ilk, int dink, int dart, uint time) external onlyManager {
        dink; // shh compiler warning
        time; // ssh compiler warning 

        address urn = manager.urns(cdp);
        (,uint realArt) = manager.vat().urns(ilk, urn);
        uint cushion = LiquidationMachine(manager).cushion(cdp);

        uint128 art = add128(uint128(realArt), uint128(cushion));

        super.updateAssetScore(user(cdp), artAsset(ilk), int128(dart), add128(art, int128(dart)), uint32(block.number));
    }

    // anyone can call. this will work both for slashing, and to add users who didn't do any operation yet.
    function slashScore(uint maliciousCdp) external {
        address urn = manager.urns(maliciousCdp);
        bytes32 ilk = manager.ilks(maliciousCdp);

        (, uint realArt) = manager.vat().urns(ilk, urn);
        uint cushion = LiquidationMachine(manager).cushion(maliciousCdp);

        uint128 art = add128(uint128(realArt), uint128(cushion));        

        uint left = BCdpScoreConnector(address(manager)).left(maliciousCdp);
        if(left > 0) realArt = 0;

        super.updateAssetScore(user(maliciousCdp), artAsset(ilk), 0, art, uint32(block.number));
    }

    // TODO - only governance machine should be able to call
    function claimScore(uint cdp, bytes32 ilk) external onlyOwner returns(uint96) {
        address urn = manager.urns(cdp);
        (,uint realArt) = manager.vat().urns(ilk, urn);
        return super.claimScore(user(cdp), artAsset(ilk), uint128(realArt), uint32(block.number));
    }

    function setSpeed(bytes32 ilk, uint96 speed) external onlyOwner {
        super.setSpeed(artAsset(ilk), speed, uint32(block.number));
    }

    function getArtScore(uint cdp, bytes32 ilk) public view returns(uint) {
        return super.getScore(user(cdp), artAsset(ilk), uint32(block.number));
    }

    function getArtGlobalScore(bytes32 ilk) public view returns(uint) {
        return super.getGlobalScore(artAsset(ilk), uint32(block.number));
    }
}
