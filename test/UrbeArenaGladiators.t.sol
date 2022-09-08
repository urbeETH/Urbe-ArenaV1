// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/UrbeArenaGladiators.sol";

    struct Gladiator {
        // number of attacks received in the last battle
        uint256 numberOfAttacksReceived;
        //experience points
        uint256 eps;
        // number of attacks received so far (all the battles)
        uint256 numberOfAttacksEverReceived;
        // records the gladiator life status
        bool isDead;
    }

interface urbeArena {
    function getLikelyToDieId() external view returns (uint256);

    function mintTokens(uint256) external payable;

    function attack(uint256, uint256) external;

    function getGladiator(uint256) external view returns (Gladiator memory);

    function closeDailyFight() external;

    function blockLag() external view returns (uint256);

    function isFightClosable() external view returns (bool);

    function getDeathByDays(uint256 day) external view returns (uint256);

    function getAttackSubmittedByDays(uint256 day, uint256 tokenId) external view returns (uint256);

    function getAttackReceivedByDays(uint256 day, uint256 tokenId) external view returns (uint256);
}

//We test our contract in the Colosseum
contract Colosseum is Test {
    function testDeploy() public returns (address) {
        return
        address(
            new UrbeArenaGladiators(
                "Ciao",
                "AHO",
                "https://example.com/",
                1e18,
                100,
                3
            )
        );
    }

    function testMint() public payable {
        address deployed = testDeploy();
        address user = address(1);
        vm.deal(user, 100e18);
        vm.startPrank(user);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
    }

    function testAttack() public payable
    {
        address deployed = testDeploy();
        address user1 = address(1);
        address user2 = address(2);
        vm.deal(user1, 100e18);
        vm.deal(user2, 100e18);
        vm.prank(user1);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.startPrank(user2);

        urbeArena(deployed).mintTokens{value : 1e18}(1);
        //assume that user2 attacks user1
        //Recall that user1 owns tokenId0 and user2 owns tokenId1

        urbeArena(deployed).attack(1, 0);

        //Now tokenId1 should have "alreadyattacked" set to true, the contrary for token0
        require(
            urbeArena(deployed).getAttackReceivedByDays(1, 0) == 1,
            "Attacked!"
        );
    }

    function testAttackEdgeCase1() public payable {
        address deployed = testDeploy();
        address user1 = address(1);
        address user2 = address(2);
        address user3 = address(2);
        address user4 = address(2);
        address user5 = address(2);
        address user6 = address(2);
        vm.deal(user1, 100e18);
        vm.deal(user2, 100e18);
        vm.deal(user3, 100e18);
        vm.deal(user4, 100e18);
        vm.deal(user5, 100e18);
        vm.deal(user6, 100e18);
        vm.prank(user1);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.prank(user2);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.prank(user3);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.prank(user4);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.prank(user5);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.prank(user6);
        urbeArena(deployed).mintTokens{value : 1e18}(1);

        vm.prank(user2);
        urbeArena(deployed).attack(1, 2);

        vm.prank(user3);
        urbeArena(deployed).attack(2, 1);

        vm.prank(user4);
        urbeArena(deployed).attack(3, 2);

        vm.prank(user5);
        urbeArena(deployed).attack(4, 1);

        vm.prank(user6);
        urbeArena(deployed).attack(5, 2);

        require(
            urbeArena(deployed).getAttackReceivedByDays(1,2) == 3,
            "Gladiator 2 did not receive 3 attacks!"
        );
        require(
            urbeArena(deployed).getAttackReceivedByDays(1,1) == 2,
            "Gladiator 1 did not receive 2 attacks!"
        );

        vm.warp(urbeArena(deployed).blockLag() + block.timestamp);
        console.log((urbeArena(deployed).getGladiator(3)).eps);

        vm.prank(user2);
        urbeArena(deployed).attack(1, 0);
        require((urbeArena(deployed).getGladiator(2)).isDead, "Gladiator 2 is not dead!");
        vm.prank(user3);
        urbeArena(deployed).attack(3, 0);
        vm.prank(user5);
        urbeArena(deployed).attack(4, 1);
        vm.prank(user6);
        urbeArena(deployed).attack(5, 3);

        vm.warp(urbeArena(deployed).blockLag() + block.timestamp + 1);
        vm.prank(user6);
        urbeArena(deployed).attack(5, 3);

        require((urbeArena(deployed).getGladiator(0)).isDead, "Gladiator 0 is not dead!");
        require((urbeArena(deployed).getGladiator(1)).eps == 1, "Gladiator 1 has not 1 eps!");
        require((urbeArena(deployed).getGladiator(3)).eps == 1, "Gladiator 3 has not 1 eps!");
        require((urbeArena(deployed).getGladiator(4)).eps == 0, "Gladiator 5 has not 0 eps!");
    }

    function testCloseDailyFight() public payable {
        address deployed = testDeploy();
        address user1 = address(1);
        address user2 = address(2);
        vm.deal(user1, 100e18);
        vm.deal(user2, 100e18);
        vm.prank(user1);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        vm.startPrank(user2);
        urbeArena(deployed).mintTokens{value : 1e18}(1);
        //assume that user2 attacks user1
        //Recall that user1 owns tokenId0 and user2 owns tokenId1
        urbeArena(deployed).attack(1, 0);
        //We move to the next session setting a new blockTimestamp through warp
        vm.warp(urbeArena(deployed).blockLag() + block.timestamp);

        //Now we close the daily fight
        urbeArena(deployed).closeDailyFight();
        // Now tokenId0 should be dead, while tokenid1 should be alive
        require((urbeArena(deployed).getGladiator(0)).isDead, "Zombie!");
        require(!(urbeArena(deployed).getGladiator(1)).isDead, "Zombie!");
    }

    function testCloseDailyFightWithTie(uint256 max) public {
        vm.assume(max <= 100);
        if (max == 1) {
            max = 100;
        }
        // A "stress test" to check the gas consumed in the worst case scenario for calling closeDailyFight()
        // In such context you have 100 living gladiators and there will be no deaths (third hedge case)
        address deployed = testDeploy();
        //We mint all the supply
        for (uint256 i = 0; i < max; i++) {
            vm.deal(address(uint160(i + 1)), 100e18);
            vm.prank(address(uint160(i + 1)));
            urbeArena(deployed).mintTokens{value : 1e18}(1);
        }
        //Each dude attacks his pair
        for (uint256 i = 0; i < max; i++) {
            vm.prank(address(uint160(i + 1)));
            if (i == max - 1) {
                urbeArena(deployed).attack(i, 0);
            } else {
                urbeArena(deployed).attack(i, i + 1);
            }
        }
        // We move to the next session
        vm.warp(urbeArena(deployed).blockLag() + block.timestamp);

        //recall that block starts from 1
        //We reperform the last attack in order to trigger closeFight (in the first cycle the gladiator commits suicide)
        if (max > 0) {
            vm.prank(address(uint160(max)));
            urbeArena(deployed).attack(max - 1, 0);
        }
    }

    function testGetReliableEstimationForCloseDailyFightWithTie() public {
        for (uint256 i = 0; i < 100; i++) {
            testCloseDailyFightWithTie(i);
        }
    }
}
