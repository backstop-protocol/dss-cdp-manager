pragma solidity ^0.5.12;

import { DSAuth } from "ds-auth/auth.sol";
import { BCdpManager } from "../BCdpManager.sol";
import { Math } from "../Math.sol";

contract GovernanceExecutor is DSAuth, Math {

    BCdpManager public man;
    uint public delay;
    mapping(address => uint) public requests;

    event RequestPoolUpgrade(address indexed pool);
    event PoolUpgraded(address indexed pool);

    constructor(address man_, uint delay_) public {
        man = BCdpManager(man_);
        delay = delay_;
    }

    // TODO
    function doTransferAdmin(address owner) external auth {
        man.setOwner(owner);
    }

    /**
     * @dev Request pool contract upgrade
     * @param pool Address of new pool contract
     */
    function reqPoolUpgrade(address pool) external auth {
        requests[pool] = now;
        emit RequestPoolUpgrade(pool);
    }

    /**
     * @dev Execute pool contract upgrade after delay
     * @param pool Address of the new pool contract
     */
    function execUpgradePool(address pool) external auth {
        uint reqTime = requests[pool];
        require(reqTime != 0, "request-not-valid");
        require(now >= add(reqTime, delay), "delay-not-over");
        
        delete requests[pool];
        emit PoolUpgraded(pool);
        man.setPoolContract(pool);
    }
}