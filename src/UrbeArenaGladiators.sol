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
    event Death(
        uint256 gladiatorId,
        address owner,
        uint256 numberOfAttacks,
        uint256 day
    ); // (gladiatorId, owner, numberofAttacks)
    event Attack(
        uint256 gladiatorId,
        uint256 opponentId,
        address attackerAddress,
        address opponentAddress
    ); // (gladiatorId, opponentId, attackerAddress, opponentAddress));
    event Mint(uint256 gladiatorId, address owner); // (gladiatorId, owner)
    event WoundedGladiator(
        uint256 gladiatorId,
        address owner,
        uint256 dailyAttacks,
        uint256 day
    ); // (gladiatorId, owner)
    event NoDeath(uint256 day);

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
    mapping(uint256 => bool) public isDead;
    // stores a mapping with key = day and value = [attackerTokenId: targetTokenId], to track all the attacks submitted day by day
    mapping(uint256 => mapping(uint256 => uint256)) attacksSubmittedByDay;

    struct Gladiator {
        uint256 attackSubmitted;
        uint256 numberOfAttacksReceived;
        uint256 eps;
        uint256 numAttacksEverReceived;
        bool alreadyAttacked;
        bool isDead;
    }

    // Array of the most attacked gladiators (=tokendIds) in this session
    uint256 internal likelyToDieId;
    uint256 internal likelyToDieEps = type(uint256).max; //if we set it to 0, the second edge case will be always skipped
    uint256 internal likelyToDieAttacksReceived;

    // Parameters for closing the daily fight
    uint256 public day = 1;
    // stores a mapping with key = day and value = tokenId, to track all the deaths
    mapping(uint256 => uint256) public deathByDays;
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
        likelyToDieId = 999;
        lastBlockClosedFight = block.number;
        // Otherwise the daily fight is immediately closeable
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
            isDead[mintIndex] = false;
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
            isDead[tokenId]
        );
    }

    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = tokenId == 999 ? type(uint256).max : eps[tokenId];
        likelyToDieAttacksReceived = tokenId == 999
        ? 0
        : numberOfAttacksReceived[tokenId];
        if (tokenId != 999) {
            emit WoundedGladiator(
                tokenId,
                ownerOf(tokenId),
                likelyToDieAttacksReceived,
                day
            );
        }
    }

    /* Attack another gladiator, specifying the tokenId of the target */
    function attack(uint256 attackerTokenId, uint256 targetTokenId) public {
        // if fight is closable, and we don't have yet a dead gladiator for today (deathByDays[day] does not contain a valid tokenId)
        // we need to close the fight
        if (isFightClosable() && !(deathByDays[day] <= totalSupply())) {
            closeDailyFight();
        }
        // if gladiator did not yet attack today reward him with EPs and reset his attack status
        if (!(attacksSubmittedByDay[day][attackerTokenId] <= totalSupply())) {
            _assignEpsAndResetStatus(attackerTokenId);
        }
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            !isDead[attackerTokenId],
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            !alreadyAttacked[attackerTokenId],
            "Gladiators can submit one attack per day only!"
        );
        require(
            !isDead[targetTokenId],
            "You can't attack a gladiator that is already dead!"
        );
        numberOfAttacksReceived[targetTokenId]++;
        numAttacksEverReceived[targetTokenId]++;
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
                } else if (
                    numAttacksEverReceived[targetTokenId] ==
                    likelyToDieAttacksReceived
                ) {
                    // Finally, if we are here we have a tie nobody dies and we not re-initialize EPS and total attack received
                    likelyToDieId = 999;
                }
            }
        }
        attackSubmitted[attackerTokenId] = targetTokenId;
        attacksSubmittedByDay[day][attackerTokenId] = targetTokenId;
        alreadyAttacked[attackerTokenId] = true;
        emit Attack(
            attackerTokenId,
            targetTokenId,
            msg.sender,
            ownerOf(targetTokenId)
        );
    }

    function isFightClosable() public view returns (bool) {
        return block.number >= lastBlockClosedFight + _blockLag;
    }

    modifier fightClosable() {
        require(isFightClosable());
        _;
    }

    /* Process the attacks received, set a gladiator as died, reward winners with EPs */
    function closeDailyFight() public fightClosable {
        uint256 deadGladiatorId = likelyToDieId;
        if (deadGladiatorId != 999) {
            isDead[deadGladiatorId] = true;
            deathByDays[day] = deadGladiatorId;
            emit Death(
                deadGladiatorId,
                ownerOf(deadGladiatorId),
                numberOfAttacksReceived[deadGladiatorId],
                day
            );
        } else {
            emit NoDeath(day);
        }
        setLikelyToDieId(999);
        lastBlockClosedFight = block.number;
        day++;
    }

    function _assignEpsAndResetStatus(uint256 gladiatorId) internal {
        if (
            deadGladiatorId != 999 &&
            attacksSubmittedByDay[gladiatorId] == deadGladiatorId
        ) {
            eps[gladiatorId]++;
        }
        alreadyAttacked[gladiatorId] = false;
        numberOfAttacksReceived[gladiatorId] = 0;
        attackSubmitted[gladiatorId] = 999;
    }
}
