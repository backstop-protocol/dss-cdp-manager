pragma solidity ^0.5.12;

import { Pool } from "../../pool/Pool.sol";

contract EchidnaPool is Pool {

    constructor() 
        public
        Pool(address(0), address(0), address(0), address(0), address(0))
    {
        //this.setProfitParams(10, 100);
    }

    function echidna_test() public returns (bool) {
        return true;
    }

    function echidna_profitParams_always_ok() public returns (bool) {
        return (shrn == 0 && shrd == 0) || shrn < shrd;
    }

}