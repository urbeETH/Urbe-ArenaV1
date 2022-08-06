// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../src/UrbeArenaGladiators.sol";

struct Gladiator {
    uint256 attackSubmitted;
    uint256 numberOfAttacksReceived;
    uint256 eps;
    uint256 numAttacksEverReceived;
    bool alreadyAttacked;
    bool isDead;
}

interface urbeArena {
    function mintTokens(uint256) external payable;

    function attack(uint256, uint256) external;

    function getGladiator(uint256) external view returns (Gladiator memory);

    function closeDailyFight() external;

    function blockLag() external view returns (uint256);
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
        urbeArena(deployed).mintTokens{value: 1e18}(1);
    }

    function testAttack() public payable {
        address deployed = testDeploy();
        address user1 = address(1);
        address user2 = address(2);
        vm.deal(user1, 100e18);
        vm.deal(user2, 100e18);
        vm.prank(user1);
        urbeArena(deployed).mintTokens{value: 1e18}(1);
        vm.startPrank(user2);
        urbeArena(deployed).mintTokens{value: 1e18}(1);
        //assume that user2 attacks user1
        //Recall that user1 owns tokenId0 and user2 owns tokenId1
        urbeArena(deployed).attack(1, 0);
        //Now tokenId1 should have "alreadyattacked" set to true, the contrary for token0
        require(
            (urbeArena(deployed).getGladiator(1)).alreadyAttacked,
            "Not attacked!"
        );
        require(
            !(urbeArena(deployed).getGladiator(0)).alreadyAttacked,
            "Attacked!"
        );
    }

    function testCloseDailyFight() public payable {
        address deployed = testDeploy();
        address user1 = address(1);
        address user2 = address(2);
        vm.deal(user1, 100e18);
        vm.deal(user2, 100e18);
        vm.prank(user1);
        urbeArena(deployed).mintTokens{value: 1e18}(1);
        vm.startPrank(user2);
        urbeArena(deployed).mintTokens{value: 1e18}(1);
        //assume that user2 attacks user1
        //Recall that user1 owns tokenId0 and user2 owns tokenId1
        urbeArena(deployed).attack(1, 0);
        //Now tokenId1 should have "alreadyattacked" set to true, the contrary for token0
        require(
            (urbeArena(deployed).getGladiator(1)).alreadyAttacked,
            "Not attacked!"
        );
        require(
            !(urbeArena(deployed).getGladiator(0)).alreadyAttacked,
            "Attacked!"
        );
        //We move to the next session
        emit log_uint(urbeArena(deployed).blockLag());
        vm.roll(urbeArena(deployed).blockLag() + block.number); //recall that block starts from 1
        //Now we close the daily fight
        urbeArena(deployed).closeDailyFight();
        // Now tokenId0 should be dead, while tokenid1 should be alive
        require((urbeArena(deployed).getGladiator(0)).isDead, "Zombie!");
        require(!(urbeArena(deployed).getGladiator(1)).isDead, "Zombie!");
    }

    function testCloseDailyFightWithTie(uint256 max) public {
        vm.assume(max <= 100);
        // A "stress test" to check the gas consumed in the worst case scenario for calling closeDailyFight()
        // In such context you have 100 living gladiators and there will be no deaths (third hedge case)
        address deployed = testDeploy();
        //We mint all the supply
        for (uint256 i = 0; i < max; i++) {
            vm.deal(address(uint160(i + 1)), 100e18);
            vm.prank(address(uint160(i + 1)));
            urbeArena(deployed).mintTokens{value: 1e18}(1);
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
        vm.roll(urbeArena(deployed).blockLag() + block.number); //recall that block starts from 1
        //We reperform the last attack in order to trigger closefight (in the first cycle the gladiator commits suicide)
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
