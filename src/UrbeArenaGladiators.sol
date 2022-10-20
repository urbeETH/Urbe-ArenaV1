// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./IUrbeArenaGladiators.sol";


contract UrbeArenaGladiators is IUrbeArenaGladiators, ERC721Enumerable, Ownable {

     // Gladiator Data
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
        // timestamp of the last attack of this gladiator
        uint256 lastAttack;

        uint256 attacksReceivedToday;
        uint256 attackSubmittedToday;
        uint256 attackSubmittedYesterday;
    }

    // NFT Data
    uint256 public TOKEN_PRICE;
    uint256 public MAX_TOKENS;
    uint256 public MAX_MINTS;

    // Metadata
    string public _baseTokenURI;

    //stores a mapping with key = NFT id and value = Gladiator struct
    mapping(uint256 => Gladiator) public gladiators;

    // most attacked gladiators (=tokendIds) data in this session
    uint256 internal likelyToDieId;
    uint256 internal likelyToDieEps = type(uint256).max; // if we set it to 0, the second edge case will be always skipped
    uint256 internal likelyToDieAttacksReceived;

    // gameFinished == false -> the game is not finished yet. gameFinished == true -> the game is finished and we have winner(s)
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
    //day from which if a gladiator dies he falls into the top x gladiators who are eligible for a reward proportional to its share amount
    uint256 dayTop;
    //stores a mapping with key = id and value = number of shares
    mapping(uint256=>uint256) sharesAmount;
    //all ids eligible for a share
    uint256[] shares;
    //total number of shares
    uint256 _totalShares;
    //available treasury after paying the winner(s)
    uint256 availableTreasury;


    /**
     * @dev Initializes the UrbeArenaGladiators contract.
     * @param name NFT name.
     * @param symbol NFT symbol.
     * @param baseURI NFT base URI.
     * @param tokenPrice starting token price.
     * @param maxTokens maximum amount of tokens (must be less thatn type(uint256).max).
     * @param maxMints maximum amount of mints.
     */
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 tokenPrice,
        uint256 maxTokens,
        uint256 maxMints
    ) ERC721(name, symbol) {
        require(maxTokens <= type(uint256).max, "Invalid maxTokens parameter.");
        setTokenPrice(tokenPrice);
        setMaxTokens(maxTokens);
        setMaxMints(maxMints);
        setBaseURI(baseURI);
        likelyToDieId = MAX_TOKENS + 1;
        lastTimestampClosedFight = block.timestamp;
        day = 1;
        deathByDays[1] = MAX_TOKENS + 1;
        totalDeaths = 0;
    }

    /** SETTERS */

    /**
     * @dev Allows the owner to set the base URI.
     * @param baseURI new base URI for the NFTs.
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Allows the owner to update the block lag.
     * @param _lag new block lag.
     */
    function setBlockLag(uint256 _lag) public onlyOwner {
        _blockLag = _lag;
    }

    /** GETTERS */

    /**
     * @dev Returns the base token URI for the NFTs.
     * @return NFTs base token uri.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Returns the gladiator at the given tokenId.
     * @param tokenId gladiator token id.
     * @return Gladiator at the given tokenId.
     */
    function getGladiator(uint256 tokenId) public view returns (Gladiator memory){
        return gladiators[tokenId];
    }

    /**
     * @dev Returns the id of the token that is "likely to die."
     * @return likelyToId variable.
     */
    function getLikelyToDieId() public view returns (uint256) {
        return likelyToDieId;
    }

    /**
     * @dev Returns the block lag variable.
     * @return _blockLag variable.
     */
    function blockLag() public view returns (uint256) {
        return _blockLag;
    }

    /** READ-ONLY FUNCTIONS */

    /**
     * @dev Calculates the reward for a specific gladiator.
     * @param treasury available treasury.
     * @param sharesGladiator amount of shares.
     * @return Gladiator reward based on its shares.
     */
    function _calculateTopWinners(uint256 treasury, uint256 sharesGladiator) internal view returns(uint256){
        return ((treasury * ((sharesGladiator / _totalShares) * 1e18))) / 1e18;
    }

    /**
     * @dev Calculates a percentage.
     * @param amount total amount.
     * @param percentage percentage amount.
     * @return Percentage calculate on the given amount.
     */
    function _calculatePercentage(uint256 amount, uint256 percentage) private pure returns(uint256) {
        return (amount * ((percentage * 1e18) / ONE_HUNDRED)) / 1e18;
    }

    /**
     * @dev Calculates if at the current block timestamp the current fight is closable.
     * @return True if the fight is closable, false otherwise.
     */
    function isFightClosable() public view returns (bool) {
        return block.timestamp >= lastTimestampClosedFight + _blockLag;
    }

    /** INTERNAL FUNCTIONS */

    /**
     * @dev Sets the currently more likely to die Gladiator.
     * @param tokenId gladiator tokenId.
     */
    function setLikelyToDieId(uint256 tokenId) internal {
        likelyToDieId = tokenId;
        likelyToDieEps = tokenId == MAX_TOKENS + 1 ? type(uint256).max : gladiators[tokenId].eps;
        likelyToDieAttacksReceived = tokenId == MAX_TOKENS + 1 ? 0 : gladiators[tokenId].attacksReceivedToday;
        if (tokenId != MAX_TOKENS + 1) {
            emit WoundedGladiator(tokenId, ownerOf(tokenId), likelyToDieAttacksReceived, day);
        }
    }

    /**
     * @dev Registers a new share for the given tokenId.
     * @param tokenId token id for the new share.
     */
    function _registerShare(uint256 tokenId) internal {
        require(day >= dayTop);
        require(totalDeaths <= totalSupply() - 2);
        require(tokenId != MAX_TOKENS + 1);
        shares.push(tokenId);
    }

    /**
     * @dev Performs the submit of the ETH.
     * @param subject address receiving the ETH.
     * @param value amount of ETH being transferred.
     * @param inputData extra data being sent.
     * @return returnData call return data.
     */
    function submit(address subject, uint256 value, bytes memory inputData) internal returns(bytes memory returnData) {
        bool result;
        (result, returnData) = subject.call{value : value}(inputData);
        if (!result) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    /** PUBLIC FUNCTIONS */

    /**
     * @dev Mints the given amount of NFTs.
     * @param numberOfTokens number of tokens to be minted.
     */
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
            gladiators[mintIndex] = Gladiator(0, 0, 0, true, block.timestamp, 0, 0, MAX_TOKENS + 1, MAX_TOKENS + 1);
        }
    }

    /**
     * @dev Allows the owner of "attackerTokenId" to attack the target gladiator with the "targetTokenId".
     * Both the attackerTokenId and targetTokenId Gladiators must be alive and the attacker must be capable
     * of performing an attack today.
     * @param attackerTokenId tokenId of the attacking gladiator.
     */
    function attack(uint256 attackerTokenId, uint256 targetTokenId) public {
        // if fight is closable, and we don't have yet a dead gladiator for today (deathByDays[day] contains the placeholder MAX_TOKENS + 1)
        // we can close the fight
        if (isFightClosable() && deathByDays[day] == MAX_TOKENS + 1) {
            closeDailyFight();
        }
        require(
            targetTokenId < totalSupply(),
            "Invalid targetTokenId"
        );
        Gladiator storage attackerGladiator = gladiators[attackerTokenId];
        Gladiator storage targetGladiator = gladiators[targetTokenId];
        if (attackerGladiator.lastAttack + 1 days <= block.timestamp) {
            attackerGladiator.attackSubmittedYesterday = attackerGladiator.attackSubmittedToday;
            attackerGladiator.attackSubmittedToday = MAX_TOKENS + 1;
            attackerGladiator.lastAttack = block.timestamp;
        } else {
            revert("Already attacked today.");
        }
        // if is not day1 and gladiator did not yet attack today reward him with EPs and reset his attack status
        if (day > 1 && attackerGladiator.attackSubmittedToday == MAX_TOKENS + 1 && attackerGladiator.attackSubmittedYesterday == deathByDays[day - 1]) {
            attackerGladiator.eps++;
        }
        require(
            ownerOf(attackerTokenId) == msg.sender,
            "You don't own this gladiator"
        );
        require(
            attackerGladiator.isAlive && targetGladiator.isAlive,
            "Both gladitors must be alive!"
        );
        require(
            attackerGladiator.attackSubmittedToday == MAX_TOKENS + 1,
            "Gladiators can submit one attack per day only!"
        );
        if (targetGladiator.lastUpdatedAt + 1 days <= block.timestamp) {
            targetGladiator.attacksReceivedToday = 1;
        } else {
            targetGladiator.attacksReceivedToday++;
        }
        targetGladiator.numberOfAttacksEverReceived += 1;
        targetGladiator.lastUpdatedAt = block.timestamp;
        // if today this gladiator (targetTokenId) received a num of attacks greater than the current likelyToDieId
        // targetTokenId becomes the new likelyToDieId has he received more attacks than everyone else
        if (targetGladiator.attacksReceivedToday > likelyToDieAttacksReceived) {
            setLikelyToDieId(targetTokenId);
        } else if (targetGladiator.attacksReceivedToday == likelyToDieAttacksReceived) {
            // [Edge Case 1] if today this gladiator (targetTokenId) received a num of attacks equal to the current likelyToDieId
            // we need to compare targetTokenId EPs with likelyToDieId EPS
            if (targetGladiator.eps < likelyToDieEps) {
                setLikelyToDieId(targetTokenId);
            } else if (likelyToDieEps == targetGladiator.eps) {
                // [Edge Case 2] if this gladiator (targetTokenId) has the same EPs as the current likelyToDieId
                // we need to compare targetTokenId total received attacks with likelyToDieId total received attacks
                if (targetGladiator.numberOfAttacksEverReceived > likelyToDieAttacksReceived) {
                    setLikelyToDieId(targetTokenId);
                } else if (targetGladiator.numberOfAttacksEverReceived == likelyToDieAttacksReceived) {
                    // Finally, if we are here we have a tie nobody dies
                    likelyToDieId = MAX_TOKENS + 1;
                }
            }
        }
        attackerGladiator.attackSubmittedToday = targetTokenId;
        emit Attack(attackerTokenId, targetTokenId, msg.sender, ownerOf(targetTokenId));
    }


    /**
     * @dev Allows any user to close the daily fight, if possible.
     * This function processes all the attacks receved, sets a Gladiator as dead and 
     * reward the winners with experience points.
     */
    function closeDailyFight() public {
        require(isFightClosable(), "Fight must be closable.");
        require(!gameFinished, "Game already finished");
        uint256 deadGladiatorId = likelyToDieId;
        if (deadGladiatorId != MAX_TOKENS + 1) {
            gladiators[deadGladiatorId].isAlive = false;
            deathByDays[day] = deadGladiatorId;
            totalDeaths++;
            emit Death(deadGladiatorId, ownerOf(deadGladiatorId), gladiators[deadGladiatorId].attacksReceivedToday, day);
        } else {
            deathByDays[day] = MAX_TOKENS + 1;
            emit NoDeath(day);
        }
        // game ended when only one gladiator is alive or when there is a final tie.
        setLikelyToDieId(MAX_TOKENS + 1);
        lastTimestampClosedFight = block.timestamp;
        day++;
        deathByDays[day] = MAX_TOKENS + 1;
        _registerShare(deadGladiatorId);
    }

    //utility function to define the Gladiator(s) winner(s) and send him(them) the 50% of the treasury
    /**
     * @dev Finalizes the game and splits the treasury to the winner/s.
     * @param tokenId1 the first (and maybe only) winner.
     * @param tokenId2 in case of a draw, there may be another winner.
     * @param executorRewardAddress address of the wallet that gets the reward for executing this function.
     */
    function finalizeGameAndSplitTreasuryWinner(uint256 tokenId1, uint256 tokenId2, address executorRewardAddress) public {
        require(!gameFinished, "the game must finish first");
        require(gladiators[tokenId1].isAlive = true, "invalid token");

        address winnerAddress1 = ownerOf(tokenId1);
        require(winnerAddress1 != address(0));

        uint256 availableAmount = address(this).balance;
        require(availableAmount > 0, "balance");

        uint256 receiverAmount1 = 0;
        uint256 receiverAmount2 = 0;
        address[] memory winners = new address[](2);

        if (totalDeaths == totalSupply() - 1) {
            submit(winnerAddress1, receiverAmount1 = _calculatePercentage(availableAmount, winnerRewardPercentage), "");
            shares.push(deathByDays[day-1]);
            gameFinished = true;
            winners[0] = winnerAddress1;
        }
        else if (totalDeaths == totalSupply() - 2 && deathByDays[day] == deathByDays[day-1]) {
            require(gladiators[tokenId2].isAlive = true, "invalid token");
            address winnerAddress2 = ownerOf(tokenId2);
            require(winnerAddress2!=address(0));
            submit(winnerAddress1, receiverAmount1 = _calculatePercentage(availableAmount, halfWinnerRewardPercentage), "");
            submit(winnerAddress2, receiverAmount2 = _calculatePercentage(availableAmount, halfWinnerRewardPercentage), "");
            gameFinished = true;
            winners[0] = winnerAddress1;
            winners[1] = winnerAddress2;
        }
        require(address(this).balance < availableAmount, "no split");   

        if (executorRewardPercentage > 0) {
            address to = executorRewardAddress == address(0) ? msg.sender : executorRewardAddress;
            submit(to, _calculatePercentage(availableAmount, executorRewardPercentage), "");
        }

        availableTreasury = address(this).balance;

        //define top shares 
        for (uint256 i = 0; i <= shares.length; i++) {
            sharesAmount[shares[i]] = i;
            _totalShares+=i;
        }

        emit Winner(tokenId1, tokenId2, winners, day);
    }

    //after triggering the finalizeGameAndSplitTreasuryWinner, this function can be used to collect the reward for gladiators who fall into a top
    /**
     * @dev When the game it's finished, gladiators that were able to finish in the top
     * are rewarded ETH based on their shares.
     * @param tokenId id of the gladiator that wants to withdraw their prize.
     */
    function withdraw(uint256 tokenId) public {
        require(gameFinished, "The game must be finished");
        require(sharesAmount[tokenId] != 0, "Invalid token");

        (uint256 calculatedAmount) = _calculateTopWinners(availableTreasury, sharesAmount[tokenId]);
        submit(ownerOf(tokenId), calculatedAmount, "");
        sharesAmount[tokenId] = 0;

        emit WithdrawShare(tokenId, ownerOf(tokenId), day);
    }
}