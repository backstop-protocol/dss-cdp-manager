pragma solidity ^0.5.12;

import {BCdpManagerTestBase, Hevm, FakeUser, FakeOSM, BCdpManager} from "./../BCdpManager.t.sol";
import { DssDeployTestBase, Vat, Cat, Spotter, DSValue } from "dss-deploy/DssDeploy.t.base.sol";
import {BCdpScore} from "./../BCdpScore.sol";
import {Pool} from "./../pool/Pool.sol";
import {FakeMember} from "./../pool/Pool.t.sol";
import {LiquidationMachine,PriceFeedLike} from "./../LiquidationMachine.sol";


contract PriceFeed is DSValue {
    function read(bytes32 ilk) external view returns(bytes32) {
        return read();
    }
}

contract VatDeployer {
    Vat public vat;
    Spotter public spotter;
    PriceFeed public pipETH;
    Cat public cat;
    BCdpManager public man;
    Pool public pool;
    FakeOSM public osm;
    FakeMember public member;

    uint public cdpUnsafe;
    uint public cdpUnsafeNext;

    constructor() public {
        vat = new Vat();
        vat.rely(msg.sender);
        //vat.deny(address(this));

        pipETH = new PriceFeed();

        spotter = new Spotter(address(vat));
        spotter.rely(msg.sender);
        //spotter.deny(address(this));

        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        osm = new FakeOSM();
        osm.setPrice(uint(300 * 10 ** 18));
        //pipETH.setOwner(msg.sender);
        spotter.file("ETH-A", "pip", address(pipETH)); // Set pip
        spotter.file("par",1000000000000000000000000000);
        spotter.file("ETH-A", "mat", 1500000000000000000000000000);

        vat.rely(address(spotter));

        cat = new Cat(address(vat));
        //cat.rely(msg.sender);
        cat.file("ETH-A","chop",1130000000000000000000000000);

        // set VAT cfg
        vat.init("ETH-A");
        vat.file("Line",568000000000000000000000000000000000000000000000000000);
        vat.file("ETH-A","spot",260918853648800000000000000000);
        vat.file("ETH-A","line",340000000000000000000000000000000000000000000000000000);
        vat.file("ETH-A","dust",20000000000000000000000000000000000000000000000);
        //vat.fold("ETH-A",address(0),1020041883692153436559184034);

        spotter.poke("ETH-A");

        pool = new Pool(address(vat),address(0x12345678),address(spotter));
        man = new BCdpManager(address(vat), address(cat), address(pool), address(pipETH));
        pool.setCdpManager(man);
        pool.setOsm("ETH-A",address(osm));
        address[] memory members = new address[](2);
        member = new FakeMember();
        members[0] = address(member);
        members[1] = 0xf214dDE57f32F3F34492Ba3148641693058D4A9e;
        pool.setMembers(members);
        pool.setOwner(msg.sender);
    }

    function poke() public {
        member.doHope(vat,address(pool));

        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        spotter.poke("ETH-A");
        osm.setPrice(uint(300 * 10 ** 18));
        // send ton of gem to holder
        vat.slip("ETH-A",msg.sender,1e18 * 1e6);
        vat.slip("ETH-A",address(this),1e18 * 1e20);

        // get tons of dai
        uint cdp = man.open("ETH-A", address(this));
        vat.flux("ETH-A",address(this),man.urns(cdp),1e7 * 1 ether);
        man.frob(cdp,1e6 * 1 ether,1e7 * 10 ether);
        man.move(cdp, address(member), 1e6 * 1 ether * 1e27);
        man.move(cdp, address(0xf214dDE57f32F3F34492Ba3148641693058D4A9e), 1e6 * 1 ether * 1e27);

        cdpUnsafe = man.open("ETH-A", address(this));
        vat.flux("ETH-A",address(this),man.urns(cdpUnsafe),1e7 * 1 ether);
        man.frob(cdpUnsafe,1 ether, 100 ether);

        cdpUnsafeNext = man.open("ETH-A", address(this));
        vat.flux("ETH-A",address(this),man.urns(cdpUnsafeNext),1e7 * 1 ether);
        man.frob(cdpUnsafeNext,1 ether, 98 ether);

        pipETH.poke(bytes32(uint(149 ether)));
        osm.setPrice(uint(146 ether));
        spotter.poke("ETH-A");
    }
}


contract DeploymentTest is BCdpManagerTestBase {
    uint currTime;
    FakeMember member;
    FakeMember[] members;
    FakeMember nonMember;
    address constant JAR = address(0x1234567890);

    VatDeployer deployer;

    function setUp() public {
        super.setUp();

        currTime = now;
        hevm.warp(currTime);

        address[] memory memoryMembers = new address[](4);
        for(uint i = 0 ; i < 5 ; i++) {
            FakeMember m = new FakeMember();
            seedMember(m);
            m.doHope(vat,address(pool));

            if(i < 4) {
                members.push(m);
                memoryMembers[i] = address(m);
            }
            else nonMember = m;
        }

        pool.setMembers(memoryMembers);

        member = members[0];


    }

    function getMembers() internal view returns(address[] memory) {
        address[] memory memoryMembers = new address[](members.length);
        for(uint i = 0 ; i < members.length ; i++) {
            memoryMembers[i] = address(members[i]);
        }

        return memoryMembers;
    }

    function testDeployer() public {

        deployer = new VatDeployer();

        deployer.poke();
        deployer.poke();

        assert(deployer.vat().gem("ETH-A",address(this)) >= 1e18 * 1e6);
        assertEq(deployer.vat().live(),1);

        uint cdp1 = deployer.cdpUnsafe();
        uint cdp2 = deployer.cdpUnsafeNext();

        int dartX;
        (dartX,,) = deployer.pool().topAmount(cdp1);
        assert(dartX > 0);
        (dartX,,) = deployer.pool().topAmount(cdp2);
        assert(dartX > 0);



        FakeMember m = deployer.member();
        Pool p = deployer.pool();
        Vat v = deployer.vat();

        m.doHope(vat,address(p));
        m.doDeposit(p,1e22 * 1e27);
        assertEq(p.rad(address(m)), 1e22 * 1e27);
        m.doTopup(p,cdp1);
        m.doBite(p,cdp1,100 ether,0);

        assertEq(v.gem("ETH-A",address(m)),750805369127516778);

        m.doTopup(p,cdp2);

        return;
        //FakeUser user = deployer.user;

        deployer.vat().hope(address(deployer.man));
        uint cdp = deployer.man().open("ETH-A", address(this));
        assertEq(cdp,2);

        address urn = deployer.man().urns(cdp);
        deployer.vat().flux("ETH-A",address(this),deployer.man().urns(cdp),20e18);
        assertEq(deployer.vat().gem("ETH-A",urn)  ,20e18);
        deployer.man().frob(cdp, int(20e18), int(21e18));

        (uint ink, uint art) = deployer.vat().urns("ETH-A",urn);
        assertEq(ink,20e18);
        assertEq(art,21e18);

        int dart;
        (dart,,) = deployer.pool().topAmount(cdp);
        assertEq(dart,7);
        deployer.osm().setPrice(200 * 10 ** 18);
        (dart,,) = deployer.pool().topAmount(cdp);
        assertEq(dart,7);
        //assertEq(address(deployer.vat),address(0x123));
    }

    function openCdp(uint ink,uint art) internal returns(uint){
        uint cdp = manager.open("ETH", address(this));

        weth.deposit.value(ink)();
        weth.approve(address(ethJoin), ink);
        ethJoin.join(manager.urns(cdp), ink);

        manager.frob(cdp, int(ink), int(art));

        return cdp;
    }

    function seedMember(FakeMember m) internal {
        uint cdp = openCdp(1e3 ether, 1e3 ether);
        manager.move(cdp,address(m),1e3 ether * ONE);
    }

    function timeReset() internal {
        currTime = now;
        hevm.warp(currTime);
    }

    function forwardTime(uint deltaInSec) internal {
        currTime += deltaInSec;
        hevm.warp(currTime);
    }
}
