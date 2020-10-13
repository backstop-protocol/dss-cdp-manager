pragma solidity ^0.5.16;

import {DSTest} from "ds-test/test.sol";
import {FakeCat3, FakeCat4, CatTest} from "./FakeCat.sol";

contract FakeCatTest is DSTest {
    FakeCat3 cat3;
    FakeCat4 cat4;
    function setUp() public {
        cat3 = new FakeCat3();
        cat4 = new FakeCat4();
    }
    function testWithThree() public {
        CatTest ct = new CatTest(address(cat3));
        uint b = ct.testRun();
        assertEq(b, 2);
    }
    function testWithFour() public {
        CatTest ct = new CatTest(address(cat4));
        uint b = ct.testRun();
        assertEq(b, 5);
    }
}