pragma solidity ^0.5.12;

import { Pool } from "../../pool/Pool.sol";

contract EchidnaPool is Pool {

    constructor() 
        public
        Pool(address(0), address(0), address(0), address(0))
    {

    }

    function echidna_test() public returns (bool) {
        return true;
    }

}