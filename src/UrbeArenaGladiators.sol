// SPDX-License-Identifier: MIT

//TO-DO:
//set time-require (block number) for calling closeDailyFight
//thinking a way to handle 1vs1 end fight

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UrbeArenaGladiators is ERC721Enumerable, Ownable {
    using SafeMath for uint256;

    // events
    event Death(uint256 gladiatorId, address owner, uint256 numberOfAttacks); // (gladiatorId, owner, numberofAttacks)
    event Attack(
        uint256 gladiatorId,
        uint256 opponentId,
        address attackerAddress,
        address opponentAddress
    ); // (gladiatorId, opponentId, attackerAddress, opponentAddress));
    event Mint(uint256 gladiatorId, address owner); // (gladiatorId, owner)
    event NoDeath();

    // Token Data
    uint256 public TOKEN_PRICE;
    uint256 public MAX_TOKENS;
    uint256 public MAX_MINTS;

    // Metadata
    string public _baseTokenURI;

    //tokenId => gladiator attributes
    mapping(uint256 => uint256) public attackSubmitted; // records the lastToken id that the gladiator submitted an attack on
    mapping(uint256 => uint256) public numberOfAttacksReceived;
    mapping(uint256 => bool) public alreadyAttacked; // records if the gladiator has already attacked
    mapping(uint256 => uint256) public eps; //experience points
    mapping(uint256 => uint256) public numAttacksEverReceived;
    mapping(uint256 => bool) public isDeath;

    struct Gladiator {
        uint256 attackSubmitted;
        uint256 numberOfAttacksReceived;
        uint256 eps;
        uint256 numAttacksEverReceived;
        bool alreadyAttacked;
        bool isDeath;
    }

    // Array of the most attacked gladiators (=tokendIds) in this session
    uint256 internal likelyToDieId;
    uint256 internal likelyToDieEps;
    uint256 internal likelyToDieAttacksReceived;

    // Parameters for closing the daily fight
    uint256 lastBlockClosedFight;
    uint256 _blockLag = 6000; // number of blocks before closing the daily fight

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
        setLikelyToDieId(999);
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

    function setBlockLag(uint256 _lag) public onlyOwner {
        _blockLag = _lag;
    }

    function setLikelyToDieId(uint256 _likelyToDieId) internal {
        likelyToDieId = _likelyToDieId;
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
            emit Mint(mintIndex, msg.sender);
            attackSubmitted[mintIndex] = 999;
            numberOfAttacksReceived[mintIndex] = 0;
            eps[mintIndex] = 0;
            numAttacksEverReceived[mintIndex] = 0;
            alreadyAttacked[mintIndex] = false;
            isDeath[mintIndex] = false;
        }
    }

    // Getters
    function getGladiator(uint256 tokenId)
        public
        view
        returns (Gladiator memory)
    {
        return
            Gladiator(
                attackSubmitted[tokenId],
                numberOfAttacksReceived[tokenId],
                eps[tokenId],
                numAttacksEverReceived[tokenId],
                alreadyAttacked[tokenId],
                isDeath[tokenId]
            );
    }

    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = eps[tokenId];
        likelyToDieAttacksReceived = numberOfAttacksReceived[tokenId];
    }

    /* Attack another gladiator, specifying the tokenid of the target */
    function attack(uint256 attackerTokenId, uint256 targetTokenId) public {
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            !isDeath[attackerTokenId],
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            !alreadyAttacked[attackerTokenId],
            "Gladiators can submit one attack per day only!"
        );
        require(
            !isDeath[targetTokenId],
            "You can't attack a gladiator that is already dead!"
        );
        // If the target is the died dude of the previous game, instead of attacking him he definitely kills him.
        if (targetTokenId == likelyToDieId && isFightClosable()) {
            closeDailyFight();
        } else {
            numberOfAttacksReceived[targetTokenId] += 1;
            numAttacksEverReceived[targetTokenId] += 1;
            // if this gladiator (targetTokenId) received a num of attacks greater than the current likelyToDieId
            // targetTokenId becomes the new likelyToDieId has he received more attacks than everyone else
            if (
                numberOfAttacksReceived[targetTokenId] >
                likelyToDieAttacksReceived
            ) {
                setLikelyToDieId(targetTokenId);
            } else if (
                numberOfAttacksReceived[targetTokenId] ==
                likelyToDieAttacksReceived
            ) {
                // [Edge Case 1] if this gladiator (targetTokenId) received a num of attacks equal to the current likelyToDieId
                // we need to compare targetTokenId EPs with likelyToDieId EPS
                if (eps[targetTokenId] < likelyToDieEps) {
                    setLikelyToDieId(targetTokenId);
                } else if (likelyToDieEps == eps[targetTokenId]) {
                    // [Edge Case 2] if this gladiator (targetTokenId) has the same EPs as the current likelyToDieId
                    // we need to compare targetTokenId total received attacks with likelyToDieId total received attacks
                    if (
                        numAttacksEverReceived[targetTokenId] >
                        likelyToDieAttacksReceived
                    ) {
                        setLikelyToDieId(targetTokenId);
                    } else if (numAttacksEverReceived[targetTokenId] = likelyToDieAttacksReceived) {
                        likelyToDieId = 999;
                        likelyToDieEps = 0;
                        likelyToDieAttacksReceived = 0;
                    }
                }
            }
            attackSubmitted[attackerTokenId] = targetTokenId;
            alreadyAttacked[attackerTokenId] = true;
            emit Attack(
                attackerTokenId,
                targetTokenId,
                msg.sender,
                ownerOf(targetTokenId)
            );
        }
    }

    function isFightClosable() public view returns (bool) {
        return block.number >= lastBlockClosedFight + _blockLag;
    }

    /* Process the attacks received, set a gladiator as died, reward winners with EPs */
    function closeDailyFight() public {
        require(isFightClosable(), "The fight is still open!");
        uint256 deadGladiatorId = likelyToDieId;
        if (deadGladiatorId != 999) {
            isDeath[deadGladiatorId] = true;
            emit Death(
                deadGladiatorId,
                ownerOf(deadGladiatorId),
                numberOfAttacksReceived[deadGladiatorId]
            );
            // give 1 EP to all the gladiators who attacked deadGladiatorId in this round and prepare values for the next game
            for (uint256 i = 0; i < totalSupply(); i++) {
                if (isDeath[i] == false) {
                    if (attackSubmitted[i] == deadGladiatorId) {
                        eps[i] += 1;
                    }
                    alreadyAttacked[i] = false;
                    numberOfAttacksReceived[i] = 0;
                    attackSubmitted[i] = 999;
                }
            }
        } else {
            emit NoDeath();
        }
        likelyToDieAttacksReceived = 0;
        lastBlockClosedFight = block.number;
    }
}
