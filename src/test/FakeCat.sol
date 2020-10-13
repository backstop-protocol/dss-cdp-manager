pragma solidity ^0.5.12;

contract FakeCat3 {
    function ilks() public returns (uint,uint,uint){
        return (1,2,3);
    }
}
contract FakeCat4 {
    function ilks() public returns (uint,uint,uint,uint){
        return (4,5,6,7);
    }
}
contract CatLike {
    function ilks() public returns (uint,uint,uint);
}
contract CatTest {
    CatLike cat;
    constructor(address _cat) public {
        cat = CatLike(_cat);
    }
    function testRun() public returns(uint) {
        (, uint b,) = cat.ilks();
        return b;
    }
}