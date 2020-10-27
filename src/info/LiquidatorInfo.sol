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

contract ChainlinkLike {
    function latestAnswer() external view returns (int256);
}

contract LiquidatorInfo is Math {
    struct VaultInfo {
        bytes32 collateralType;
        uint collateralInWei;
        uint debtInDaiWei;
        uint liquidationPrice;
        uint expectedEthReturnWithCurrentPrice;
        bool expectedEthReturnBetterThanChainlinkPrice;
    }

    struct CushionInfo {
        uint cushionSizeInWei;
        uint numLiquidators;

        uint cushionSizeInWeiIfAllHaveBalance;
        uint numLiquidatorsIfAllHaveBalance;

        bool shouldProvideCushion;
        bool shouldProvideCushionIfAllHaveBalance;

        uint minimumTimeBeforeCallingTopup;
        bool canCallTopupNow;

        bool shouldCallUntop;
        bool isToppedUp;
    }

    struct BiteInfo {
        uint availableBiteInArt;
        uint availableBiteInDaiWei;
        uint minimumTimeBeforeCallingBite;
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
    ChainlinkLike chainlink;

    uint constant RAY = 1e27;

    constructor(LiquidationMachine manager_, address chainlink_) public {
        manager = manager_;
        vat = VatLike(address(manager.vat()));
        pool = Pool(manager.pool());
        spot = SpotLike(address(pool.spot()));
        chainlink = ChainlinkLike(chainlink_);
    }

    function getExpectedEthReturn(bytes32 collateralType, uint daiDebt, uint currentPriceFeedValue) public returns(uint) {
        // get chope value
        (,uint chop,) = manager.end().cat().ilks(collateralType);
        uint biteIlk = mul(chop, daiDebt) / currentPriceFeedValue;

        // DAI to USD rate, scale 1e18
        uint d2uPrice = pool.dai2usd().getMarketPrice(pool.DAI_MARKET_ID());
        uint shrn = pool.shrn();
        uint shrd = pool.shrd();

        return mul(mul(biteIlk, shrn), d2uPrice) / mul(shrd, uint(1 ether));
    }

    function getVaultInfo(uint cdp, uint currentPriceFeedValue) public returns(VaultInfo memory info) {
        address urn = manager.urns(cdp);
        info.collateralType = manager.ilks(cdp);

        uint cushion = manager.cushion(cdp);

        uint art;
        (info.collateralInWei, art) = vat.urns(info.collateralType, urn);
        (,uint rate,,,) = vat.ilks(info.collateralType);
        info.debtInDaiWei = mul(add(art, cushion), rate) / RAY;
        (, uint mat) = spot.ilks(info.collateralType);
        info.liquidationPrice = mul(info.debtInDaiWei, mat) / mul(info.collateralInWei, RAY / 1e18);

        if(currentPriceFeedValue > 0) {
            info.expectedEthReturnWithCurrentPrice = getExpectedEthReturn(info.collateralType, info.debtInDaiWei, currentPriceFeedValue);
        }

        int chainlinkPrice = chainlink.latestAnswer();
        uint chainlinkEthReturn = 0;
        if(chainlinkPrice > 0) {
            chainlinkEthReturn = mul(info.debtInDaiWei, uint(chainlinkPrice)) / 1 ether;
        }

        info.expectedEthReturnBetterThanChainlinkPrice =
            info.expectedEthReturnWithCurrentPrice > chainlinkEthReturn;
    }

    function getCushionInfo(uint cdp, address me, uint numMembers) public view returns(CushionInfo memory info) {
        (uint cdpArt,uint cushion, address[] memory cdpWinners,uint[] memory bite) = pool.getCdpData(cdp);
        info.isToppedUp = cushion > 0;

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

        info.canCallTopupNow = !info.isToppedUp && should && info.shouldProvideCushion;
        if(info.isToppedUp) {
            for(uint i = 0 ; i < cdpWinners.length ; i++) {
                if(me == cdpWinners[i]) {
                    uint perUserArt = cdpArt / cdpWinners.length;
                    if(perUserArt > bite[i]) {
                        info.shouldCallUntop = true;
                        break;
                    }
                }
            }
        }

        bytes32 ilk = manager.ilks(cdp);
        uint topupTime = add(uint(pool.osm(ilk).zzz()), uint(pool.osm(ilk).hop())/2);
        info.minimumTimeBeforeCallingTopup = (now >= topupTime) ? 0 : sub(topupTime, now);
    }

    function getBiteInfo(uint cdp, address me) public view returns(BiteInfo memory info) {
        info.availableBiteInArt = pool.availBite(cdp, me);

        bytes32 ilk = manager.ilks(cdp);
        uint priceUpdateTime = add(uint(pool.osm(ilk).zzz()), uint(pool.osm(ilk).hop()));
        info.minimumTimeBeforeCallingBite = (now >= priceUpdateTime) ? 0 : sub(priceUpdateTime, now);

        if(info.availableBiteInArt == 0) return info;

        address u = manager.urns(cdp);
        (,uint rate, uint currSpot,,) = vat.ilks(ilk);

        info.availableBiteInDaiWei = mul(rate, info.availableBiteInArt) / RAY;

        (uint ink, uint art) = vat.urns(ilk, u);
        uint cushion = manager.cushion(cdp);
        info.canCallBiteNow = (mul(ink, currSpot) < mul(add(art, cushion), rate)) || manager.bitten(cdp);
    }

    function getNumMembers() public returns(uint) {
        for(uint i = 0 ; /* infinite loop */ ; i++) {
            (bool result,) = address(pool).call(abi.encodeWithSignature("members(uint256)", i));
            if(! result) return i;
        }
    }

    function getCdpData(uint startCdp, uint endCdp, address me, uint currentPriceFeedValue) public returns(CdpInfo[] memory info) {
        uint numMembers = getNumMembers();
        info = new CdpInfo[](add(sub(endCdp, startCdp), uint(1)));
        for(uint cdp = startCdp ; cdp <= endCdp ; cdp++) {
            uint index = cdp - startCdp;
            info[index].cdp = cdp;
            info[index].vault = getVaultInfo(cdp, currentPriceFeedValue);
            info[index].cushion = getCushionInfo(cdp, me, numMembers);
            info[index].bite = getBiteInfo(cdp, me);
        }
    }
}

contract FlatLiquidatorInfo is LiquidatorInfo {
    constructor(LiquidationMachine manager_, address chainlink_) public LiquidatorInfo(manager_, chainlink_) {}

    function getVaultInfoFlat(uint cdp, uint currentPriceFeedValue) external
        returns(bytes32 collateralType, uint collateralInWei, uint debtInDaiWei, uint liquidationPrice,
                uint expectedEthReturnWithCurrentPrice, bool expectedEthReturnBetterThanChainlinkPrice) {
        VaultInfo memory info = getVaultInfo(cdp, currentPriceFeedValue);
        collateralType = info.collateralType;
        collateralInWei = info.collateralInWei;
        debtInDaiWei = info.debtInDaiWei;
        liquidationPrice = info.liquidationPrice;
        expectedEthReturnWithCurrentPrice = info.expectedEthReturnWithCurrentPrice;
        expectedEthReturnBetterThanChainlinkPrice = info.expectedEthReturnBetterThanChainlinkPrice;
    }

    function getCushionInfoFlat(uint cdp, address me, uint numMembers) external view
        returns(uint cushionSizeInWei, uint numLiquidators, uint cushionSizeInWeiIfAllHaveBalance,
                uint numLiquidatorsIfAllHaveBalance, bool shouldProvideCushion, bool shouldProvideCushionIfAllHaveBalance,
                bool canCallTopupNow, bool shouldCallUntop, uint minimumTimeBeforeCallingTopup,
                bool isToppedUp) {

        CushionInfo memory info = getCushionInfo(cdp, me, numMembers);
        cushionSizeInWei = info.cushionSizeInWei;
        numLiquidators = info.numLiquidators;
        cushionSizeInWeiIfAllHaveBalance = info.cushionSizeInWeiIfAllHaveBalance;
        numLiquidatorsIfAllHaveBalance = info.numLiquidatorsIfAllHaveBalance;
        shouldProvideCushion = info.shouldProvideCushion;
        shouldProvideCushionIfAllHaveBalance = info.shouldProvideCushionIfAllHaveBalance;
        canCallTopupNow = info.canCallTopupNow;
        shouldCallUntop = info.shouldCallUntop;
        minimumTimeBeforeCallingTopup = info.minimumTimeBeforeCallingTopup;
        isToppedUp = info.isToppedUp;
    }

    function getBiteInfoFlat(uint cdp, address me) external view
        returns(uint availableBiteInArt, uint availableBiteInDaiWei, bool canCallBiteNow,uint minimumTimeBeforeCallingBite) {
        BiteInfo memory info = getBiteInfo(cdp, me);
        availableBiteInArt = info.availableBiteInArt;
        availableBiteInDaiWei = info.availableBiteInDaiWei;
        canCallBiteNow = info.canCallBiteNow;
        minimumTimeBeforeCallingBite = info.minimumTimeBeforeCallingBite;
    }
}
