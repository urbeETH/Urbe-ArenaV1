// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


interface IUrbeArenaGladiators {


    event Death(uint256 indexed gladiatorId, address indexed owner, uint256 numberOfAttacks, uint256 day);
    
    event Mint(uint256 indexed gladiatorId, address owner);
    
    event WoundedGladiator( uint256 indexed gladiatorId, address indexed owner, uint256 dailyAttacks, uint256 day);
    
    event NoDeath(uint256 indexed day);
    
    event Winner(uint256 indexed gladiatorId1, uint256 indexed gladiatorId2, address[] indexed winners, uint256 day);
    
    event WithdrawShare(uint256 indexed id, address indexed ownerId, uint256 day);

    event Attack(
        uint256 indexed gladiatorId, uint256 indexed opponentId, address attackerAddress, address opponentAddress
    );
}