pragma solidity ^0.5.12;
pragma experimental ABIEncoderV2;

import { LiquidationMachine } from "./../LiquidationMachine.sol";
import { Pool } from "./../pool/Pool.sol";
import { Math } from "./../Math.sol";

contract VatLike {
    function urns(bytes32 ilk, address u) public view returns (uint ink, uint art);
    function ilks(bytes32 ilk) public view returns(uint Art, uint rate, uint spot, uint line, uint dust);
}

contract SpotLike {
    function ilks(bytes32 ilk) external view returns (address pip, uint mat);
}

contract LiquidatorInfo is Math {
    struct VaultInfo {
        bytes32 collateralType;
        uint collateralInWei;
        uint debtInDaiWei;
        uint liquidationPrice;
    }

    struct CushionInfo {
        uint cushionSizeInWei;
        uint numLiquidators;

        uint cushionSizeInWeiIfAllHaveBalance;
        uint numLiquidatorsIfAllHaveBalance;

        bool shouldProvideCushion;
        bool shouldProvideCushionIfAllHaveBalance;

        bool canCallTopupNow;
    }

    struct BiteInfo {
        uint availableBiteInArt;
        uint availableBiteInDaiWei;
        bool canCallBiteNow;
    }

    struct CdpInfo {
        uint cdp;
        VaultInfo vault;
        CushionInfo cushion;
        BiteInfo bite;
    }

    LiquidationMachine manager;
    VatLike public vat;
    Pool pool;
    SpotLike spot;

    uint constant RAY = 1e27;

    constructor(LiquidationMachine manager_) public {
        manager = manager_;
        vat = VatLike(address(manager.vat()));
        pool = Pool(manager.pool());
        spot = SpotLike(address(pool.spot()));
    }

    function getVaultInfo(uint cdp) public view returns(VaultInfo memory info) {
        address urn = manager.urns(cdp);
        info.collateralType = manager.ilks(cdp);

        uint cushion = manager.cushion(cdp);

        uint art;
        (info.collateralInWei, art) = vat.urns(info.collateralType, urn);
        (,uint rate,,,) = vat.ilks(info.collateralType);
        info.debtInDaiWei = mul(add(art, cushion), rate) / RAY;
        (, uint mat) = spot.ilks(info.collateralType);
        info.liquidationPrice = mul(info.debtInDaiWei, mat) / mul(info.collateralInWei, RAY / 1e18);
    }

    // todo - calc num members externally
    function getCushionInfo(uint cdp, address me, uint numMembers) public view returns(CushionInfo memory info) {
        (uint dart, uint dtab, uint art, bool should, address[] memory winners) = pool.topupInfo(cdp);
        if(dart == 0) return info;

        info.cushionSizeInWei = dtab / RAY;
        info.numLiquidators = winners.length;

        if(art < pool.minArt()) {
            info.cushionSizeInWeiIfAllHaveBalance = info.cushionSizeInWei;
            info.numLiquidatorsIfAllHaveBalance = 1;
            info.shouldProvideCushion = false;
            for(uint i = 0 ; i < winners.length ; i++) {
                if(me == winners[i]) info.shouldProvideCushion = true;
            }

            uint chosen = uint(keccak256(abi.encodePacked(cdp, now / 1 hours))) % numMembers;
            info.shouldProvideCushionIfAllHaveBalance = (pool.members(chosen) == me);
        }
        else {
            info.cushionSizeInWeiIfAllHaveBalance = info.cushionSizeInWei / numMembers;
            info.numLiquidatorsIfAllHaveBalance = numMembers;
            info.shouldProvideCushion = true;
            info.shouldProvideCushionIfAllHaveBalance = true;
        }

        info.canCallTopupNow = should && info.shouldProvideCushion;
    }

    function getBiteInfo(uint cdp, address me) public view returns(BiteInfo memory info) {
        info.availableBiteInArt = pool.availBite(cdp, me);
        if(info.availableBiteInArt == 0) return info;

        bytes32 ilk = manager.ilks(cdp);
        address u = manager.urns(cdp);
        (,uint rate, uint spot,,) = vat.ilks(ilk);
        (uint ink, uint art) = vat.urns(ilk, u);

        info.availableBiteInDaiWei = mul(rate, info.availableBiteInArt) / RAY;
        info.canCallBiteNow = (mul(ink, spot) < mul(art, rate));
    }

    function getNumMembers() public returns(uint) {
        for(uint i = 0 ; /* infinite loop */ ; i++) {
            (bool result,) = address(pool).call(abi.encodeWithSignature("members()", i));
            if(! result) return i;
        }
    }

    function getCdpData(uint startCdp, uint endCdp, address me) public returns(CdpInfo[] memory info) {
        uint numMembers = getNumMembers();
        info = new CdpInfo[](add(sub(endCdp, startCdp), uint(1)));
        for(uint cdp = startCdp ; cdp <= endCdp ; cdp++) {
            uint index = cdp - startCdp;
            info[index].cdp = cdp;
            info[index].vault = getVaultInfo(cdp);
            info[index].cushion = getCushionInfo(cdp, me, numMembers);
            info[index].bite = getBiteInfo(cdp, me);
        }
    }
}
