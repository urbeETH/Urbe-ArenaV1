// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UrbeArenaGladiators is ERC721Enumerable, Ownable {
    using SafeMath for uint256;

    // Token Data
    uint256 public TOKEN_PRICE;
    uint256 public MAX_TOKENS;
    uint256 public MAX_MINTS;

    // Metadata
    string public _baseTokenURI;

    struct Gladiator {
        uint256 attackSubmitted;
        uint256[] attacksReceived;
        uint256 eps;
        uint256 numAttacksEverReceived;
        bool alreadyAttacked;
        bool isDead;
    }

    // Gladiators Data
    mapping(uint256 => Gladiator) public gladiators;

    uint256 _highestNumAttacksReceived;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 tokenPrice,
        uint256 maxTokens,
        uint256 maxMints
    ) ERC721(name, symbol) {
        setTokenPrice(tokenPrice);
        setMaxTokens(maxTokens);
        setMaxMints(maxMints);
        setBaseURI(baseURI);
        setHighestNumAttacks(0);
    }

    /* Setters */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setMaxMints(uint256 maxMints_) public onlyOwner {
        MAX_MINTS = maxMints_;
    }

    function setTokenPrice(uint256 tokenPrice_) public onlyOwner {
        TOKEN_PRICE = tokenPrice_;
    }

    function setMaxTokens(uint256 maxTokens_) public onlyOwner {
        MAX_TOKENS = maxTokens_;
    }

    function setHighestNumAttacks(uint256 value) public onlyOwner {
        _highestNumAttacksReceived = 0;
    }

    /* Getters */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /* Main Sale */
    function mintTokens(uint256 numberOfTokens) public payable {
        require(
            numberOfTokens <= MAX_MINTS,
            "Can only mint max purchase of tokens at a time"
        );
        require(
            totalSupply().add(numberOfTokens) <= MAX_TOKENS,
            "Purchase would exceed max supply of Tokens"
        );
        require(
            TOKEN_PRICE.mul(numberOfTokens) <= msg.value,
            "Ether value sent is not correct"
        );

        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 mintIndex = totalSupply();
            _safeMint(msg.sender, mintIndex);

            gladiators[mintIndex] = Gladiator(
                999,
                new uint256[](0),
                0,
                0,
                false,
                false
            );
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /* Attack another gladiator */
    function attack(uint256 tokenId) public payable {
        uint256 attackerTokenId = ERC721Enumerable.tokenOfOwnerByIndex(
            msg.sender,
            0
        );
        require(attackerTokenId, "You don't own any gladiator");
        require(
            gladiators[attackerTokenId].isDead == false,
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            gladiators[attackerTokenId].alreadyAttacked == false,
            "Gladiators can submit one attack per day only!"
        );
        require(
            gladiators[tokenId].isDead == false,
            "You can't attack a gladiator that is already dead!"
        );

        uint256 previousAttacks = gladiators[tokenId].attacksReceived.length;
        gladiators[tokenId].numGladiatorsSameAttacks += 1;
        gladiators[tokenId].attacksReceived.push(attackerTokenId);
        setHighestNumAttacks(
            max(
                _highestNumAttacksReceived,
                gladiators[tokenId].attacksReceived.length
            )
        );
        gladiators[attackerTokenId].attackSubmitted = tokenId;
        gladiators[attackerTokenId].alreadyAttacked = true;
    }

    /* Process the attacks received, set a gladiator as died, reward winners with EPs */
    function closeDailyFight() public onlyOwner {
        uint256 deadGladiatorId = getDeadGladiatorId();
        if (deadGladiatorId != 999) {
            gladiators[deadGladiatorId].isDead = true;

            // give 1 EP to all the gladiators who attacked deadGladiatorId in this round
            uint256 x = 0;
            for (
                x;
                x < gladiators[deadGladiatorId].attacksReceived.length;
                x++
            ) {
                uint256 winningGladiatorId = gladiators[deadGladiatorId]
                    .attacksReceived[x];
                gladiators[winningGladiatorId].eps += 1;
            }
        }
    }

    /* Get the ID of today's dead gladiator */
    function getDeadGladiatorId() internal returns (uint256) {
        uint256 i = 0;
        uint256[] memory gladiatorsSameAttacks = new uint256[](0);
        // get gladiators IDs who received the same number of attacks to evaluate possible ties
        for (i; i < MAX_TOKENS && gladiators[i].isDead == false; i++) {
            if (
                _highestNumAttacksReceived ==
                gladiators[i].attacksReceived.length
            ) {
                gladiatorsSameAttacks.push(i);
            }
        }

        if (gladiatorsSameAttacks.length > 1) {
            // check gladiator status to break the tie
            uint256 deadGladiatorId = 999;
            uint256 j = 0;
            uint256 maxEP = 0;
            uint256 maxAttacksReceived = 0;
            for (j; j < gladiatorsSameAttacks.length; j++) {
                if (maxEP < gladiators[j].eps) {
                    maxEP = gladiators[j].eps;
                    deadGladiatorId = j;
                } else if (maxEP == gladiators[j].eps) {
                    if (
                        maxAttacksReceived <
                        gladiators[j].numAttacksEverReceived
                    ) {
                        maxAttacksReceived = gladiators[j]
                            .numAttacksEverReceived;
                        deadGladiatorId = j;
                    }
                }
            }
            return deadGladiatorId;
        } else {
            return i;
        }
        setHighestNumAttacks(0);
        resetAliveGladiatorStatus();
    }

    /* Reset the status of the gladiators that are still alive */
    function resetAliveGladiatorStatus() internal {
        uint256 i = 0;
        for (i; i < MAX_TOKENS && gladiators[i].isDead == false; i++) {
            if (gladiators[i].isDead == false) {
                gladiators[i].alreadyAttacked = 0;
                gladiators[i].attacksReceived = new uint256()[0];
                gladiators[i].attackSubmitted = 999;
            }
        }
    }
}
