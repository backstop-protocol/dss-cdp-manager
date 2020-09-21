pragma solidity ^0.5.12;

import { BCdpManager } from "../BCdpManager.sol";

contract GovernanceExecutor {

    BCdpManager public man;
    address public poolProxy;
    address public trasferProxy;

    modifier onlyProxy(address proxy) {
        require(msg.sender == proxy, "unauthorized-call");
        _;
    }

    constructor(
        address man_,
        address poolProxy_,
        address trasferProxy_
    ) public {
        man = BCdpManager(man_);
        poolProxy = poolProxy_;
        trasferProxy = trasferProxy_;
    }

    function doTransferAdmin(address owner) external onlyProxy(trasferProxy) {
        man.setOwner(owner);
    }

    function doSetPool(address pool) external onlyProxy(poolProxy) {
        man.setPoolContract(pool);
    }
}