pragma solidity ^0.5.12;

import { BCdpManagerTestBase, Hevm, FakeUser, FakeOSM, BCdpManager, FakeDaiToUsdPriceFeed } from "./../BCdpManager.t.sol";
import { DssDeployTestBase, Vat, Cat, Spotter, DSValue } from "dss-deploy/DssDeploy.t.base.sol";
import { BCdpScore } from "./../BCdpScore.sol";
import { Pool } from "./../pool/Pool.sol";
import { LiquidatorInfo } from "./../info/LiquidatorInfo.sol";
import { LiquidationMachine, PriceFeedLike } from "./../LiquidationMachine.sol";
import { DSToken } from "ds-token/token.sol";
import { GemJoin } from "dss/join.sol";
import { Dai } from "dss/dai.sol";
import { DaiJoin } from "dss/join.sol";
import { OSMLike, BudConnector } from "./../bud/BudConnector.sol";

contract FakeMember is FakeUser {
    function doDeposit(Pool pool, uint rad) public {
        pool.deposit(rad);
    }

    function doWithdraw(Pool pool, uint rad) public {
        pool.withdraw(rad);
    }

    function doTopup(Pool pool, uint cdp) public {
        pool.topup(cdp);
    }

    function doUntop(Pool pool, uint cdp) public {
        pool.untop(cdp);
    }

    function doPoolBite(Pool pool, uint cdp, uint dart, uint minInk) public returns(uint){
        return pool.bite(cdp, dart, minInk);
    }

    function doAllowance(Dai dai, address guy, uint wad) public {
        dai.approve(guy, wad);
    }

    function doJoin(DaiJoin join, uint wad) public {
        join.join(address(this), wad);
    }

    function doExit(GemJoin join, uint wad) public {
        join.exit(address(this), wad);
    }
}

contract PriceFeed is DSValue {
    function read(bytes32 ilk) external view returns(bytes32) {
        ilk; //shh
        return read();
    }
}

contract FakeCat {
    function ilks(bytes32 ilk) external pure returns(uint flip, uint chop, uint dunk) {
        ilk; //shh
        return (0, 1130000000000000000, 0);
    }
}

contract FakeJug {
    function ilks(bytes32 ilk) public view returns(uint duty, uint rho) {
        duty = 1e27;
        rho = (now / 1 hours) * 1 hours - 10 minutes;
        ilk; // shhhh
    }
    function base() public pure returns(uint) {
        return 0;
    }
}

contract FakeEnd {
    FakeCat public cat;
    constructor() public {
        cat = new FakeCat();
    }
}

contract FakeScore {
    function updateScore(uint cdp, bytes32 ilk, int dink, int dart, uint time) external {

    }
}

contract FakeChainLink {
    function latestAnswer() external pure returns(int) { return 2549152947092904; }
}

contract WETH is DSToken("WETH") {
}

contract FakeDssDeployer {
    Vat public vat;
    Spotter public spotter;
    PriceFeed public pipETH;
    FakeOSM public osm;
    Dai public dai;
    DaiJoin public daiJoin;
    WETH public weth;
    FakeEnd public end;
    GemJoin public ethJoin;

    constructor() public {
        vat = new Vat();
        vat.rely(msg.sender);
        //vat.deny(address(this));

        weth = new WETH();
        weth.mint(2**128);
        ethJoin = new GemJoin(address(vat), "ETH-A", address(weth));
        vat.rely(address(ethJoin));

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        dai.rely(address(daiJoin));

        weth.approve(address(ethJoin), uint(-1));
        ethJoin.join(address(this), 1e18 * 1e6);
        uint vatBalance = vat.gem("ETH-A",address(this));
        assert(vatBalance == 1e18 * 1e6);

        pipETH = new PriceFeed();

        spotter = new Spotter(address(vat));
        spotter.rely(msg.sender);
        //spotter.deny(address(this));

        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        osm = new FakeOSM();
        osm.setPrice(uint(300 * 10 ** 18));
        //pipETH.setOwner(msg.sender);
        spotter.file("ETH-A", "pip", address(pipETH)); // Set pip
        spotter.file("par", 1000000000000000000000000000);
        spotter.file("ETH-A", "mat", 1500000000000000000000000000);

        vat.rely(address(spotter));

        end = new FakeEnd();
        //cat.rely(msg.sender);
        //cat.file("ETH-A", "chop", 1130000000000000000000000000);

        // set VAT cfg
        vat.init("ETH-A");
        vat.file("Line", 568000000000000000000000000000000000000000000000000000);
        vat.file("ETH-A", "spot", 260918853648800000000000000000);
        vat.file("ETH-A", "line", 340000000000000000000000000000000000000000000000000000);
        vat.file("ETH-A", "dust", 20000000000000000000000000000000000000000000000);
        //vat.fold("ETH-A", address(0), 1020041883692153436559184034);

        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        spotter.poke("ETH-A");

        assert(vat.live() == 1);


        vat.frob("ETH-A",address(this),address(this),address(this),1e18 * 1e6,100e6 * 1e18);

        assert(vat.dai(address(this)) == 100e6 * 1e45);

        vat.hope(address(daiJoin));
        daiJoin.exit(address(this), 100e6 * 1e18);

        assert(100e6 * 1e18 == dai.balanceOf(address(this)));
    }

    function poke(BCdpManager man, address guy, int ink, int art) public returns(uint cdpUnsafeNext, uint cdpCustom){
        pipETH.poke(bytes32(uint(300 * 10 ** 18))); // Price 300 DAI = 1 ETH (precision 18)
        spotter.poke("ETH-A");
        osm.setPrice(uint(300 * 10 ** 18));
        // send ton of gem to holder
        vat.slip("ETH-A", msg.sender, 1e18 * 1e6);
        vat.slip("ETH-A", address(this), 1e18 * 1e20);

        // get tons of dai
        dai.transfer(guy, 100e3 * 1e18);

        cdpUnsafeNext = man.open("ETH-A", address(this));
        vat.flux("ETH-A", address(this), man.urns(cdpUnsafeNext), 1e7 * 1 ether);
        man.frob(cdpUnsafeNext, 1 ether, 100 ether);

        cdpCustom = man.open("ETH-A", address(this));
        vat.flux("ETH-A", address(this), man.urns(cdpCustom), 1e7 * 1 ether);
        man.frob(cdpCustom, ink, art);

        pipETH.poke(bytes32(uint(151 ether)));
        spotter.poke("ETH-A");
        osm.setPrice(uint(146 ether));
        pipETH.poke(bytes32(uint(146 ether)));
    }

    function updatePrice() public {
        spotter.poke("ETH-A");
    }
}

contract BDeployer {
    BCdpManager public man;
    Pool public pool;
    FakeMember public member;
    BCdpScore public score;
    FakeDaiToUsdPriceFeed public dai2usdPriceFeed;
    LiquidatorInfo public info;
    BudConnector public budConnector;

    uint public cdpUnsafeNext;
    uint public cdpCustom;

    FakeDssDeployer public deployer;

    constructor(FakeDssDeployer d) public {
        deployer = d;
        dai2usdPriceFeed = new FakeDaiToUsdPriceFeed();
        pool = new Pool(address(d.vat()), address(0x12345678), address(d.spotter()), address(new FakeJug()), address(dai2usdPriceFeed));
        score = BCdpScore(address(new FakeScore())); //new BCdpScore();
        man = new BCdpManager(address(d.vat()), address(d.end()), address(pool), address(d.pipETH()), address(score));
        //score.setManager(address(man));
        pool.setCdpManager(man);
        budConnector = new BudConnector(OSMLike(address(d.osm())));
        budConnector.setPip(address(d.pipETH()), "ETH-A");
        budConnector.authorize(address(pool));
        pool.setOsm("ETH-A", address(budConnector));
        address[] memory members = new address[](3);
        member = new FakeMember();
        members[0] = address(member);
        members[1] = 0xe6bD52f813D76ff4192058C307FeAffe52aA49FC;
        members[2] = 0x534447900af78B74bB693470cfE7c7dFd54A974c;
        pool.setMembers(members);
        pool.setIlk("ETH-A", true);
        pool.setProfitParams(94, 100);
        pool.setOwner(msg.sender);

        info = new LiquidatorInfo(LiquidationMachine(man), address(new FakeChainLink()));
    }

    function poke(int ink, int art) public {
        (cdpUnsafeNext, cdpCustom) = deployer.poke(man, msg.sender, ink, art);
    }

    function updatePrice() public {
        deployer.updatePrice();
    }
}


contract DeploymentTest is BCdpManagerTestBase {
    uint currTime;
    FakeMember member;
    FakeMember[] members;
    FakeMember nonMember;
    address constant JAR = address(0x1234567890);

    //VatDeployer deployer;

    function setUp() public {
        super.setUp();

        currTime = now;
        hevm.warp(currTime);

        address[] memory memoryMembers = new address[](4);
        for(uint i = 0 ; i < 5 ; i++) {
            FakeMember m = new FakeMember();
            seedMember(m);
            m.doHope(vat, address(pool));

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

    function testGas() public {
        FakeDssDeployer x = new FakeDssDeployer();
        BDeployer b = new BDeployer(x);
    }

    function testDeployer() public {
        FakeDssDeployer ds = new FakeDssDeployer();
        BDeployer b = new BDeployer(ds);

        b.poke(1 ether, 20 ether);
        b.poke(2 ether, 30 ether);

        assertTrue(ds.dai().balanceOf(address(this)) > 1e5 * 1e18);

        assertEq(ds.vat().live(), 1);

        uint cdp2 = b.cdpUnsafeNext();
        uint cdp3 = b.cdpCustom();

        address urn = b.man().urns(cdp3);
        (uint ink, uint art) = ds.vat().urns("ETH-A", urn);
        assertEq(ink, 2 ether);
        assertEq(art, 30 ether);

        uint dartX;
        (dartX,,) = b.pool().topAmount(cdp2);
        assertTrue(dartX > 0);

        Pool p = b.pool();
        Vat v = ds.vat();

        FakeMember m = b.member();
        ds.dai().transfer(address(m), 1e22);

        m.doAllowance(ds.dai(), address(ds.daiJoin()), uint(-1));
        m.doJoin(ds.daiJoin(), 1e22);
        assertEq(v.dai(address(m)), 1e22 * 1e27);

        m.doHope(v, address(p));
        m.doDeposit(p, 1e22 * 1e27);
        assertEq(p.rad(address(m)), 1e22 * 1e27);

        forwardTime(1);
        p.topupInfo(cdp2); // just make sure it does not crash

        m.doTopup(p, cdp2);
        ds.updatePrice();
        m.doBite(p, cdp2, 100 ether, 0);

        assertEq(v.gem("ETH-A", address(m)), 727534246575342465);

        assertEq(ds.weth().balanceOf(address(m)), 0);
        m.doExit(ds.ethJoin(), 727534246575342465);
        assertEq(ds.weth().balanceOf(address(m)), 727534246575342465);
    }

    function openCdp(uint ink, uint art) internal returns(uint){
        uint cdp = manager.open("ETH", address(this));

        weth.mint(ink);
        weth.approve(address(ethJoin), ink);
        ethJoin.join(manager.urns(cdp), ink);

        manager.frob(cdp, int(ink), int(art));

        return cdp;
    }

    function seedMember(FakeMember m) internal {
        uint cdp = openCdp(1e3 ether, 1e3 ether);
        manager.move(cdp, address(m), 1e3 ether * RAY);
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
