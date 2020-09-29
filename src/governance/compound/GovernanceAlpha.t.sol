pragma solidity ^0.5.16;

import { DSTest } from "ds-test/test.sol";
import { GovernorAlpha } from "./GovernanceAlpha.sol";
import { Timelock } from "./TimeLock.sol";

contract FakeScore {

}

contract GovernanceAlphaTest is DSTest {
    Timelock timelock;
    GovernorAlpha governor;
    FakeScore score;
    address guardian;
    uint constant DELAY = 3 days;
    uint constant WAITING_PERIOD = 6 * 30 days; // 6 months

    function setUp() public {
        timelock = new Timelock(guardian, DELAY);
        score = new FakeScore();
        guardian = msg.sender;

        governor = new GovernorAlpha(address(timelock), address(score), guardian, WAITING_PERIOD);
    }

    function testDeployment() public {

    }

    function testProposeNewProposal() public {

    }

    function testVotersVote() public {

    }
}