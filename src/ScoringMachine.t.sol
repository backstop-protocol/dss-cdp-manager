pragma solidity ^0.5.12;

import {BCdpManagerTestBase, Hevm, FakeUser} from "./BCdpManager.t.sol_";
import {BCdpScore} from "./BCdpScore.sol";

contract ScordingMachineTest is BCdpManagerTestBase {
    FakeUser user1;
    FakeUser user2;
    FakeUser user3;

    uint currTime;

    BCdpScore score;

    function setUp() public {
        super.setUp();

        currTime = now;
        hevm.warp(currTime);

        score = BCdpScore(manager);
    }

    function openCdp(uint ink,uint art) internal returns(uint){
        uint cdp = manager.open("ETH", address(this));

        weth.deposit.value(ink)();
        weth.approve(address(ethJoin), ink);
        ethJoin.join(manager.urns(cdp), ink);

        manager.frob(cdp, int(ink), int(art));

        return cdp;
    }

    function timeReset() internal {
        currTime = now;
        hevm.warp(currTime);
    }

    function forwardTime(uint deltaInSec) internal {
        currTime += deltaInSec;
        hevm.warp(currTime);
    }

    function testOpenCdp() public {
        timeReset();

        uint time = now;

        score.spin();

        uint cdp1 = openCdp(10 ether,1 ether);
        forwardTime(10);
        uint cdp2 = openCdp(20 ether,2 ether);
        forwardTime(10);
        uint cdp3 = openCdp(30 ether,3 ether);
        forwardTime(10);

        assertEq(currTime, time + 30);

        uint expectedTotalInkScore = (30 + 20 * 2 + 10 * 3) * 10 ether;
        uint expectedTotalArtScore = expectedTotalInkScore / 10;

        assertEq(score.getInkScore(cdp1,"ETH",currTime,score.start()), 30 * 10 ether);
        assertEq(score.getInkScore(cdp2,"ETH",currTime,score.start()), 20 * 20 ether);
        assertEq(score.getInkScore(cdp3,"ETH",currTime,score.start()), 10 * 30 ether);
        assertEq(score.getInkGlobalScore("ETH",currTime,score.start()), expectedTotalInkScore);

        assertEq(score.getArtScore(cdp1,"ETH",currTime,score.start()), 30 * 1 ether);
        assertEq(score.getArtScore(cdp2,"ETH",currTime,score.start()), 20 * 2 ether);
        assertEq(score.getArtScore(cdp3,"ETH",currTime,score.start()), 10 * 3 ether);
        assertEq(score.getArtGlobalScore("ETH",currTime,score.start()), expectedTotalArtScore);

        manager.frob(cdp2, -1 * 10 ether, -1 * 1 ether);

        forwardTime(7);

        expectedTotalInkScore += (1 + 2 + 3) * 70 ether - 70 ether;
        expectedTotalArtScore += (1 + 2 + 3) * 7 ether - 7 ether;

        assertEq(score.getInkScore(cdp2,"ETH",currTime,score.start()), 27 * 20 ether - 7 * 10 ether);
        assertEq(score.getArtScore(cdp2,"ETH",currTime,score.start()), 27 * 2 ether - 7 * 1 ether);

        assertEq(score.getInkGlobalScore("ETH",currTime,score.start()), expectedTotalInkScore);
        assertEq(score.getArtGlobalScore("ETH",currTime,score.start()), expectedTotalArtScore);
    }

    function testFrob() public {
        timeReset();

        uint time = now;

        score.spin();

        uint cdp = openCdp(100 ether, 10 ether);
        forwardTime(10);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), 10 * 100 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), 10 * 10 ether);

        manager.frob(cdp, -1 ether, 1 ether);

        forwardTime(15);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), 25 * 100 ether - 15 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), 25 * 10 ether + 15 ether);

        manager.frob(cdp, 1 ether, -1 ether);

        forwardTime(17);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), 25 * 100 ether - 15 ether + 100 * 17 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), 25 * 10 ether + 15 ether + 10 * 17 ether);
    }

    function testSpin() public {
        timeReset();

        uint time = now;

        score.spin();

        uint cdp = openCdp(100 ether, 10 ether);
        forwardTime(10);

        score.spin();

        forwardTime(15);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), 15 * 100 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), 15 * 10 ether);

        score.spin();

        forwardTime(17);

        manager.frob(cdp, -1 ether, 1 ether);

        forwardTime(13);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), (17 + 13) * 100 ether - 13 * 1 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), (17 + 13) * 10 ether + 13 * 1 ether);

        score.spin();

        forwardTime(39);

        assertEq(currTime-score.start(), 39);

        assertEq(score.getInkScore(cdp,"ETH",currTime,score.start()), 39 * 99 ether);
        assertEq(score.getArtScore(cdp,"ETH",currTime,score.start()), 39 * 11 ether);

        // try to calculate past time

        // middle of first round
        assertEq(score.getInkScore(cdp,"ETH",time + 5,time), 5 * 100 ether);

        // middle of second round
        assertEq(score.getInkScore(cdp,"ETH",time + 18,time+10), 8 * 100 ether);

        // middle of third round
        // before the frob
        assertEq(score.getInkScore(cdp,"ETH",time + 25 + 15,time+25), 15 * 100 ether);
        // after the frob
        assertEq(score.getInkScore(cdp,"ETH",time + 25 + 19,time+25), 17 * 100 ether + 2 * 99 ether);
    }


    // TODO - test new round
/*
    function testEnd() public {
        timeReset();

        uint time = now;

        score.spin(currTime,currTime + 3 weeks);

        uint cdp1 = openCdp(1 ether);
        forwardTime(10);

        (uint score1, uint totalScore1) = score.getScore(cdp1, score.round(), currTime);
        assertEq(score1, 10 * 1 ether);

        forwardTime(10 weeks);
        assertEq(time + 10 weeks + 10, currTime);

        (uint score2, uint totalScore2) = score.getScore(cdp1, score.round(), currTime);
        assertEq(score2, 3 weeks * 1 ether);
        assertEq(score2, totalScore2);
    }

    function testNewRound() public {
        timeReset();

        uint time = now;

        score.spin(currTime,currTime + 3 weeks);

        uint cdp = openCdp(1 ether);
        forwardTime(4 weeks);

        (uint score1, uint totalScore1) = score.getScore(cdp, score.round(), currTime);
        assertEq(score1, 3 weeks * 1 ether);

        score.spin(time + 3 weeks,currTime + 3 weeks);
        forwardTime(1 weeks);

        assertEq(score.round(),2);

        (score1, totalScore1) = score.getScore(cdp, score.round(), currTime);
        assertEq(score1, 1 weeks * 1 ether);
        assertEq(score1, totalScore1);
    }*/
}
