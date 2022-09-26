// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

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
    event GladiatorsWinner(
        uint256[] gladiatorsWinners,
        address[] ownerOfGladiatorsWinners
    );

    // NFT Data
    uint256 public TOKEN_PRICE;
    uint256 public MAX_TOKENS;
    uint256 public MAX_MINTS;

    // Metadata
    string public _baseTokenURI;

    //Gladiator Data
    struct Gladiator {
        // number of attacks received in the last battle
        uint256 numberOfAttacksReceived;
        //experience points
        uint256 eps;
        // number of attacks received so far (all the battles)
        uint256 numberOfAttacksEverReceived;
        // records the gladiator life status
        bool isAlive;
        // timestamp of the last update for this gladiator
        uint256 lastUpdatedAt;

        uint256 attacksReceivedToday;
        uint256 attackSubmittedToday;
        uint256 attackSubmittedYesterday;
    }

    //stores a mapping with key = NFT id and value = Gladiator struct
    mapping(uint256 => Gladiator) public gladiators;

    // most attacked gladiators (=tokendIds) data in this session
    uint256 likelyToDieId;
    uint256 internal likelyToDieEps = type(uint256).max; //if we set it to 0, the second edge case will be always skipped
    uint256 internal likelyToDieAttacksReceived;

    //token id(s) if the final winner(s) gladiator(s)
    uint256[] public gladiatorsWinners;
    //gameFinished == false -> the game is not finished yet. gameFinished == true -> the game is finished and we have winner(s)
    bool public gameFinished;

    // Parameters for closing the daily fight
    // current day
    uint256 public day;
    // stores a mapping with key = day and value = tokenId, to track all the deaths
    mapping(uint256 => uint256) public deathByDays;
    //total death from the beggining of the game
    uint256 totalDeaths;
    //when the last fight was closed
    uint256 lastTimestampClosedFight;
    // number of days before closing the daily fight
    uint256 _blockLag = 1 days; 

    //constant to maximeze precision when calculating the executor reward percentage
    uint256 public constant ONE_HUNDRED = 1e18;
    //percentage given to the address calling the reward function
    uint256 public executorRewardPercentage;
    //percentage givent to the gladiator winner
    uint256 public winnerRewardPercentage;
    //percentage given to the galdiators winners
    uint256 public halfWinnerRewardPercentage;
    //minimum value of the top
    uint256 topLow;
    //maximum value of the top
    uint256 topHigh;
    //stores a mapping with key = NFT id and value = bool (true if the id already received the reward) 
    mapping(uint256=>bool) split;


    //init data
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

    //Setters 
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

    //Getters 
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }
    function getGladiator(uint256 tokenId) public view returns (Gladiator memory){
        return gladiators[tokenId];
    }

    function getLikelyToDieId() public view returns (uint256) {
        return likelyToDieId;
    }

    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    // Main Sale 
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
            gladiators[mintIndex] = Gladiator(0, 0, 0, true, block.timestamp, 0, 999, 999);
        }
    }

    //utility functions and modifier to clode a figt
    function isFightClosable() public view returns (bool) {
        return block.timestamp >= lastTimestampClosedFight + _blockLag;
    }

    modifier fightClosable() {
        require(isFightClosable());
        _;
    }

    // Attack another gladiator, specifying the tokenId of the target 
    function attack(uint256 attackerTokenId, uint256 targetTokenId) public {
        // if fight is closable, and we don't have yet a dead gladiator for today (deathByDays[day] contains the placeholder 999)
        // we can close the fight
        if (isFightClosable() && deathByDays[day] == 999) {
            closeDailyFight();
        }
        require(
            targetTokenId < totalSupply(),
            "Invalid targetTokenId"
        );
        Gladiator storage attackerGladiator = gladiators[attackerTokenId];
        Gladiator storage targetGladiator = gladiators[targetTokenId];
        if (attackerGladiator.lastUpdatedAt <= block.timestamp + 1 days) {
            attackerGladiator.attackSubmittedYesterday = attackerGladiator.attackSubmittedToday;
            attackerGladiator.attackSubmittedToday = 999;
            attackerGladiator.lastUpdatedAt = block.timestamp;
        }
        // if is not day1 and gladiator did not yet attack today reward him with EPs and reset his attack status
        if (day > 1 && attackerGladiator.attackSubmittedToday == 999) {
            _assignEps(attackerTokenId);
        }
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            attackerGladiator.isAlive == true,
            "You can't submit an attack because your gladiator is already dead!"
        );
        require(
            attackerGladiator.attackSubmittedToday == 999,
            "Gladiators can submit one attack per day only!"
        );
        require(
            targetGladiator.isAlive,
            "You can't attack a gladiator that is already dead!"
        );
        if (targetGladiator.lastUpdatedAt <= block.timestamp + 1 days) {
            targetGladiator.attacksReceivedToday = 1;
        } else {
            targetGladiator.attacksReceivedToday += 1;
        }
        targetGladiator.numberOfAttacksEverReceived += 1;
        targetGladiator.lastUpdatedAt = block.timestamp;
        if (
        // if today this gladiator (targetTokenId) received a num of attacks greater than the current likelyToDieId
        // targetTokenId becomes the new likelyToDieId has he received more attacks than everyone else
            targetGladiator.attacksReceivedToday >
            likelyToDieAttacksReceived
        ) {
            setLikelyToDieId(targetTokenId);
        } else if (
        // [Edge Case 1] if today this gladiator (targetTokenId) received a num of attacks equal to the current likelyToDieId
        // we need to compare targetTokenId EPs with likelyToDieId EPS
            targetGladiator.attacksReceivedToday ==
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
        attackerGladiator.attackSubmittedToday = targetTokenId;
        attackerGladiator.lastUpdatedAt = block.timestamp;
        emit Attack(
            attackerTokenId,
            targetTokenId,
            msg.sender,
            ownerOf(targetTokenId)
        );
    }

    //set the current more likely to die Gladiator

    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = tokenId == 999 ? type(uint256).max : gladiators[tokenId].eps;
        likelyToDieAttacksReceived = tokenId == 999
        ? 0
        : gladiators[tokenId].attacksReceivedToday;
        if (tokenId != 999) {
            emit WoundedGladiator(
                tokenId,
                ownerOf(tokenId),
                likelyToDieAttacksReceived,
                day
            );
        }
    }

    //Process the attacks received, set a gladiator as died, reward winners with EPs */
    function closeDailyFight() public fightClosable {
        require(!gameFinished, "game already finished");
        uint256 deadGladiatorId = likelyToDieId;
        if (deadGladiatorId != 999) {
            gladiators[deadGladiatorId].isAlive = false;
            deathByDays[day] = deadGladiatorId;
            totalDeaths+=1;
            emit Death(
                deadGladiatorId,
                ownerOf(deadGladiatorId),
                gladiators[deadGladiatorId].attacksReceivedToday,
                day
            );
        } else {
            deathByDays[day] = 999;
            emit NoDeath(day);
        }
        // game ended when only one gladiator is alive or when there is a final tie. This function calculates the winner(s) gladiator(s) 
        setLikelyToDieId(999);
        lastTimestampClosedFight = block.timestamp;
        day++;
        deathByDays[day] = 999;
    }

    //utility function to define the Gladiator(s) winner(s) and send him(them) the 50% of the treasury
    function finalizeGameAndSplitTreasuryWinner(uint256 tokenId1, uint256 tokenId2, address executorRewardAddress) public {
        require(!gameFinished, "the game must finish first");
        uint256 availableAmount = address(this).balance;
        require(availableAmount > 0, "balance");
        uint256 receiverAmount = 0;

        if (totalDeaths == totalSupply() - 1) {
            require(gladiators[tokenId1].isAlive = true, "invalid token");
            address winner = ownerOf(tokenId1);
            require(winner!=address(0));
            submit(winner, receiverAmount = _calculatePercentage(availableAmount, winnerRewardPercentage), "");
            gameFinished = true;
        }
        else if(totalDeaths == totalSupply() - 2 && deathByDays[day] == deathByDays[day-1]){
            require(gladiators[tokenId1].isAlive = true, "invalid token");
            require(gladiators[tokenId2].isAlive = true, "invalid token");
            address winnerAddress1 = ownerOf(tokenId1);
            address winnerAddress2 = ownerOf(tokenId2);
            submit(winnerAddress1, receiverAmount = _calculatePercentage(availableAmount, winnerRewardPercentage), "");
            submit(winnerAddress2, receiverAmount = _calculatePercentage(availableAmount, winnerRewardPercentage), "");
            gameFinished = true;
            topHigh-=1; //if there are 2 winners the topHigh value must be -1
        }   

        if(executorRewardPercentage > 0 && address(this).balance < availableAmount) {
            address to = executorRewardAddress == address(0) ? msg.sender : executorRewardAddress;
            submit(to, receiverAmount = _calculatePercentage(availableAmount, executorRewardPercentage), "");
        }
    }

    //after triggering the finalizeGameAndSplitTreasuryWinner, this function can be used to collect the reward for gladiators who fall into a top
    function widthdraw(address executorRewardAddress, uint256 deathDay) public {
        require(gameFinished, "the game must finish first");

        uint256 id = deathByDays[day];
        require(id !=999, "invalid token");
        require(deathDay <= topHigh && deathDay >= topLow, "no reward for you");
        address winner = ownerOf(id);
        require(split[id] == false, "reward already received");

        uint256 availableAmount = address(this).balance;
        require(availableAmount > 0, "balance");
        uint256 receiverAmount = 0;

        if(executorRewardPercentage > 0) {
            address to = executorRewardAddress == address(0) ? msg.sender : executorRewardAddress;
            submit(to, receiverAmount = _calculatePercentage(availableAmount, executorRewardPercentage), "");
            availableAmount -= receiverAmount;
        }
        uint256 remainingAmount = availableAmount;

        (uint256 calculatedAmount) = _calculateTopWinners(remainingAmount, deathDay);
        submit(winner, calculatedAmount, "");
        split[id] = true;
    }

    //utility function to assign EPs to Gladiators
    function _assignEps(uint256 tokenId) internal {
        Gladiator storage gladiator = gladiators[tokenId];
        if (
        // if gladiatorId yesterday attacked the died tokenId
        // we reward him with eps
            gladiator.attackSubmittedYesterday == deathByDays[day - 1]
        ) {
            gladiator.eps++;
        }
    }

    //utility function to calculate the reward for a specific gladiator 
    function _calculateTopWinners(uint256 amount, uint256 deathDay) internal view returns(uint256){
      return ((amount * (deathDay/totalSupply())));
    }

    //utility function to calculate a certain percentage
    function _calculatePercentage(uint256 amount, uint256 percentage) private pure returns(uint256) {
        return (amount * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    function submit(address subject, uint256 value, bytes memory inputData) internal returns(bytes memory returnData) {
        bool result;
        (result, returnData) = subject.call{value : value}(inputData);
        if(!result) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}
