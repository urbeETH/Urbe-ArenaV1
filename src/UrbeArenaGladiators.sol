// SPDX-License-Identifier: MIT

//TO-DO:
//set time-require (block number) for calling closeDailyFight
//thinking a way to handle 1vs1 end fight

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract UrbeArenaGladiators is ERC721Enumerable, Ownable {

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
    event NoDeath(uint256 indexed day);

    // Token Data
    uint256 public TOKEN_PRICE;
    uint256 public MAX_TOKENS;
    uint256 public MAX_MINTS;

    // Metadata
    string public _baseTokenURI;

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

    mapping(uint256 => Gladiator) public gladiators;
    // stores a mapping with key = day and value = [attackerTokenId: targetTokenId], to track all the attacks submitted day by day
    mapping(uint256 => mapping(uint256 => uint256)) attackSubmittedByDay;
    mapping(uint256 => mapping(uint256 => uint256)) attackReceivedByDay;

    // Array of the most attacked gladiators (=tokendIds) in this session
    uint256 likelyToDieId;
    uint256 internal likelyToDieEps = type(uint256).max; //if we set it to 0, the second edge case will be always skipped
    uint256 internal likelyToDieAttacksReceived;

    // Parameters for closing the daily fight
    // current day
    uint256 public day;
    // stores a mapping with key = day and value = tokenId, to track all the deaths
    mapping(uint256 => uint256) public deathByDays;
    uint256 totalDeaths;
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
        deathByDays[1] = 999;
        totalDeaths = 0;
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
            totalSupply() + numberOfTokens <= MAX_TOKENS,
            "Purchase would exceed max supply of Tokens"
        );
        require(
            TOKEN_PRICE * numberOfTokens <= msg.value,
            "Ether value sent is not correct"
        );
        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 mintIndex = uint256(totalSupply());
            _safeMint(msg.sender, mintIndex);
            emit Mint(mintIndex, msg.sender);
            attackSubmittedByDay[day][mintIndex] = 999;
            gladiators[mintIndex] = Gladiator(0, 0, 0, false);
        }
    }

    // Getters
    function getGladiator(uint256 tokenId) public view returns (Gladiator memory){
        return gladiators[tokenId];
    }

    function getLikelyToDieId() public view returns (uint256) {
        return likelyToDieId;
    }

    function getDeathByDays(uint256 day) public view returns (uint256) {
        return deathByDays[day];
    }

    function getAttackSubmittedByDays(uint256 day, uint256 tokenId) public view returns (uint256) {
        return attackSubmittedByDay[day][tokenId];
    }

    function getAttackReceivedByDays(uint256 day, uint256 tokenId) public view returns (uint256) {
        return attackReceivedByDay[day][tokenId];
    }

    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = tokenId == 999 ? type(uint256).max : gladiators[tokenId].eps;
        likelyToDieAttacksReceived = tokenId == 999
        ? 0
        : attackReceivedByDay[day][tokenId];
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
        // if fight is closable, and we don't have yet a dead gladiator for today (deathByDays[day] contains the placeholder 999)
        // we can close the fight
        if (isFightClosable() && deathByDays[day] == 999) {
            closeDailyFight();
        }
        Gladiator storage attackerGladiator = gladiators[attackerTokenId];
        Gladiator storage targetGladiator = gladiators[targetTokenId];
        // if is not day1 and gladiator did not yet attack today reward him with EPs and reset his attack status
        if (day > 1 && attackSubmittedByDay[day][attackerTokenId] == 999) {
            _assignEps(attackerTokenId);
        }
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            attackerGladiator.isDead == false,
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            attackSubmittedByDay[day][attackerTokenId] == 999,
            "Gladiators can submit one attack per day only!"
        );
        require(
            !targetGladiator.isDead,
            "You can't attack a gladiator that is already dead!"
        );
        attackReceivedByDay[day][targetTokenId] += 1;
        targetGladiator.numberOfAttacksEverReceived += 1;

        if (
        // if today this gladiator (targetTokenId) received a num of attacks greater than the current likelyToDieId
        // targetTokenId becomes the new likelyToDieId has he received more attacks than everyone else
            attackReceivedByDay[day][targetTokenId] >
            likelyToDieAttacksReceived
        ) {
            setLikelyToDieId(targetTokenId);
        } else if (
        // [Edge Case 1] if today this gladiator (targetTokenId) received a num of attacks equal to the current likelyToDieId
        // we need to compare targetTokenId EPs with likelyToDieId EPS
            attackReceivedByDay[day][targetTokenId] ==
            likelyToDieAttacksReceived
        ) {

            if (targetGladiator.eps < likelyToDieEps) {
                setLikelyToDieId(targetTokenId);
            } else if (likelyToDieEps == targetGladiator.eps) {
                // [Edge Case 2] if this gladiator (targetTokenId) has the same EPs as the current likelyToDieId
                // we need to compare targetTokenId total received attacks with likelyToDieId total received attacks
                if (
                    targetGladiator.numberOfAttacksEverReceived >
                    likelyToDieAttacksReceived
                ) {
                    setLikelyToDieId(targetTokenId);
                } else if (
                    targetGladiator.numberOfAttacksEverReceived ==
                    likelyToDieAttacksReceived
                ) {
                    // Finally, if we are here we have a tie nobody dies
                    likelyToDieId = 999;
                }
            }
        }
        attackSubmittedByDay[day][attackerTokenId] = targetTokenId;
        attackSubmittedByDay[day+1][attackerTokenId] = 999;
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
            totalDeaths+=1;
            emit Death(
                deadGladiatorId,
                ownerOf(deadGladiatorId),
                attackReceivedByDay[day][deadGladiatorId],
                day
            );
        } else {
            deathByDays[day] = 999;
            emit NoDeath(day);
        }
        // game ended when only one gladiator is alive
        if (totalDeaths == totalSupply() - 1) {
            // get the only gladiator alive and send him part of the treasury
        }
        setLikelyToDieId(999);
        lastTimestampClosedFight = block.timestamp;
        day++;
        deathByDays[day] = 999;
    }

    function _assignEps(uint256 tokenId) internal {
        Gladiator storage gladiator = gladiators[tokenId];
        if (
        // if gladiatorId yesterday attacked the died tokenId
        // we reward him with eps
            attackSubmittedByDay[day - 1][tokenId] == deathByDays[day - 1]
        ) {
            gladiator.eps++;
        }
    }
}
