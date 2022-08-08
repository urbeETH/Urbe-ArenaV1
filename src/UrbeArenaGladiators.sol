// SPDX-License-Identifier: MIT

//TO-DO:
//set time-require (block number) for calling closeDailyFight
//thinking a way to handle 1vs1 end fight

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UrbeArenaGladiators is ERC721, Ownable {

    // events
    event Death(
        uint256 indexed gladiatorId,
        address indexed owner,
        uint256 numberOfAttacks,
        uint256 day
    );
    event Attack(
        uint256 indexed gladiatorId,
        uint256 indexed opponentId,
        address attackerAddress,
        address opponentAddress
    );
    event Mint(uint256 indexed gladiatorId, address owner);
    event WoundedGladiator(
        uint256 indexed gladiatorId,
        address indexed owner,
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

    struct Gladiator {
        // stores the last tokenId attacked by the gladiator
        uint64 attackSubmitted;
        // number of attacks received in the last battle
        uint64 numberOfAttacksReceived;
        // stores a mapping with key = day and value = [attackerTokenId: targetTokenId], to track all the attacks submitted day by day
        mapping(uint64 => uint64) attackSubmittedByDay;
        //experience points
        uint64 eps;
        // number of attacks received so far (all the battles)
        uint64 numberOfAttacksEverReceived;
        // records if the gladiator has already attacked
        bool alreadyAttacked;
        // records the gladiator life status
        bool isDead;
    }

    mapping(uint64 => Gladiator) public gladiators;

    // Array of the most attacked gladiators (=tokendIds) in this session
    uint256 internal likelyToDieId;
    uint256 internal likelyToDieEps = type(uint256).max; //if we set it to 0, the second edge case will be always skipped
    uint256 internal likelyToDieAttacksReceived;

    // Parameters for closing the daily fight
    // current day
    uint256 public day;
    // stores a mapping with key = day and value = tokenId, to track all the deaths
    mapping(uint256 => uint256) public deathByDays;
    uint256 lastTimestampClosedFight;
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
        lastTimestampClosedFight = block.timestamp;
        day = 1;
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
            mapping(uint64 => uint64) attackSubmittedByDay;
            gladiators[mintIndex] = Gladiator(999, 0, attackSubmittedByDay, 0, 0, false, false);
        }
    }

    // Getters
    function getGladiator(uint256 tokenId) public view returns (Gladiator memory){
        return gladiators[tokenId];
    }

    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = tokenId == 999 ? type(uint256).max : gladiators[tokenId].eps;
        likelyToDieAttacksReceived = tokenId == 999
        ? 0
        : gladiators[tokenId].numberOfAttacksReceived;
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
        Gladiator attackerGladiator = gladiators[attackerTokenId];
        Gladiator targetGladiator = gladiators[targetTokenId];
        // if gladiator did not yet attack today reward him with EPs and reset his attack status
        if (!(attackerGladiator.attackSubmittedByDay[day] <= totalSupply())) {
            _assignEpsAndResetStatus(attackerTokenId);
        }
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            !attackerGladiator.isDead,
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            !attackerGladiator.attackSubmitted,
            "Gladiators can submit one attack per day only!"
        );
        require(
            !targetGladiator.isDead,
            "You can't attack a gladiator that is already dead!"
        );
        targetGladiator.numberOfAttacksReceived++;
        targetGladiator.numberAttacksEverReceived++;
        // if this gladiator (targetTokenId) received a num of attacks greater than the current likelyToDieId
        // targetTokenId becomes the new likelyToDieId has he received more attacks than everyone else
        if (
            targetGladiator.numberOfAttacksReceived >
            likelyToDieAttacksReceived
        ) {
            setLikelyToDieId(targetTokenId);
        } else if (
            targetGladiator.numberOfAttacksReceived ==
            likelyToDieAttacksReceived
        ) {
            // [Edge Case 1] if this gladiator (targetTokenId) received a num of attacks equal to the current likelyToDieId
            // we need to compare targetTokenId EPs with likelyToDieId EPS
            if (targetGladiator.eps < likelyToDieEps) {
                setLikelyToDieId(targetTokenId);
            } else if (likelyToDieEps == targetGladiator.eps) {
                // [Edge Case 2] if this gladiator (targetTokenId) has the same EPs as the current likelyToDieId
                // we need to compare targetTokenId total received attacks with likelyToDieId total received attacks
                if (
                    targetGladiator.numberAttacksEverReceived >
                    likelyToDieAttacksReceived
                ) {
                    setLikelyToDieId(targetTokenId);
                } else if (
                    targetGladiator.numberAttacksEverReceived ==
                    likelyToDieAttacksReceived
                ) {
                    // Finally, if we are here we have a tie nobody dies and we not re-initialize EPS and total attack received
                    likelyToDieId = 999;
                }
            }
        }
        attackerGladiator.attackSubmitted = targetTokenId;
        attackerGladiator.attackSubmittedByDay[day] = targetTokenId;
        attackerGladiator.alreadyAttacked = true;
        emit Attack(
            attackerTokenId,
            targetTokenId,
            msg.sender,
            ownerOf(targetTokenId)
        );
    }

    function isFightClosable() public view returns (bool) {
        return block.timestamp >= lastTimestampClosedFight + _blockLag;
    }

    modifier fightClosable() {
        require(isFightClosable());
        _;
    }

    /* Process the attacks received, set a gladiator as died, reward winners with EPs */
    function closeDailyFight() public fightClosable {
        uint256 deadGladiatorId = likelyToDieId;
        if (deadGladiatorId != 999) {
            gladiators[deadGladiatorId].isDead = true;
            deathByDays[day] = deadGladiatorId;
            emit Death(
                deadGladiatorId,
                ownerOf(deadGladiatorId),
                gladiators[deadGladiatorId].numberOfAttacksReceived,
                day
            );
        } else {
            emit NoDeath(day);
        }
        setLikelyToDieId(999);
        lastTimestampClosedFight = block.timestamp;
        day++;
    }

    function _assignEpsAndResetStatus(uint256 tokenId) internal {
        Gladiator gladiator = gladiators[tokenId];
        if (
            deadGladiatorId != 999 &&
            gladiator.attacksSubmittedByDay == deadGladiatorId
        ) {
            gladiator.eps++;
        }
        gladiator.alreadyAttacked = false;
        gladiator.numberOfAttacksReceived = 0;
        gladiator.attackSubmitted = 999;
    }
}
