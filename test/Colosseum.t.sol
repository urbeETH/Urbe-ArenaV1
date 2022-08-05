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
    bool isDeath;
}

interface urbeArena {
    function mintTokens(uint256) external payable;

    function attack(uint256, uint256) external;

    function getGladiator(uint256) external view returns (Gladiator memory);

    function closeDailyFight() external;
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
        emit log(string(abi.encodePacked(deployed)));
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
        //Now we close the daily fight
        urbeArena(deployed).closeDailyFight();
        // Now tokenId0 should be death, while tokenid1 should be alive
        require((urbeArena(deployed).getGladiator(0)).isDeath, "Zombie!");
        require(!(urbeArena(deployed).getGladiator(1)).isDeath, "Zombie!");
    }
}
