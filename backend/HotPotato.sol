//SPDX-License-Identifier: Unlicense

// In my smart cotnract when I only want the minting phase of the game state to only occur once. And once this passes this will never be called again. Also I want users to be able to put money in the smart contract when the game is in queued. This is a choice because at the end of the game the winner gets a percentage of the roundFunds. Please allow users to send money to the contract when the game state is in Queue. And add is to the roundFunds
pragma solidity ^0.8.7;
import "hardhat/console.sol";
import "./Base64.sol";
import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";

interface MetadataHandler {
    function getTokenURI(
        uint16 id_,
        uint8 background_,
        uint8 hand_type_,
        bool hasPotato_,
        uint32 generation_,
        uint8 potato_,
        bool burnt_
    ) external view returns (string memory);

    function getSVGInterface(
        uint8 background_,
        uint8 hand_type_,
        bool hasPotato_,
        uint8 potato_
    ) external view returns (string memory);
}

struct Hand {
    bool hasPotato;
    uint32 generation;
    uint8 background;
    uint8 hand_type;
    uint8 potato;
    bool burnt;
}

enum GameState {
    Queued,
    Minting,
    Playing,
    Paused,
    Ended
}

contract UNKNOWN is
    ERC721A,
    ERC721AQueryable,
    ReentrancyGuard,
    Ownable,
    RrpRequesterV0
{
    using Strings for uint256;

    MetadataHandler public metadataHandler;

    address public _owner;
    address public airnode;
    address public sponsorWallet;

    uint256 public TOTAL_PASSES;
    uint256 public potatoTokenId;
    uint32 public currentGeneration = 0;
    uint256 public price = 0.01 ether;
    uint256 public maxSupply = 1000;
    //Users will be able to mint 1 at initial mint then when the games begin people can list their hand if they want.
    uint256 public maxPerWallet = 1;
    uint256 public activeAddresses = 0;
    uint256 private _currentIndex = 1;
    uint256 public qrngUint256;
    bytes32 internal entropySauce;
    bytes32 public endpointIdUint256;

    mapping(uint256 => Hand) public hands;
    mapping(address => bool) public hasMinted;
    mapping(address => uint256) public successfulPasses;
    mapping(uint256 => uint256) public lastPassTime;
    mapping(address => uint256) public failedPasses;
    mapping(address => uint256) public totalWins;
    mapping(GameState => string) private gameStateStrings;
    mapping(address => uint256[]) public tokensOwnedByUser;
    mapping(address => uint256) public rewards;
    mapping(uint256 => uint256) public projectFunds;
    mapping(address => bool) private uniqueOwners;
    mapping(uint256 => uint256) public teamFunds;
    mapping(uint256 => uint256) public charityFunds;
    mapping(uint256 => uint256) public roundFunds;
    mapping(address => uint256) public addressActiveTokenCount;
    mapping(bytes32 => bool) public waitingFulfillment;
    mapping(address => bool) public hasBet;

    GameState internal gameState;
    GameState internal previousGameState;

    uint256[] public activeTokens;
    address[] public players;
    address[] public winners;

    event MintingStarted(string message);
    event PlayerReadyUp(address indexed player);
    event GameStarted(string message);
    event GamePaused(string message);
    event GameResumed(string message);
    event GameRestarted(string message);
    event PotatoExploded(uint256 tokenId, address player);
    event NewRound(uint256 round);
    event PotatoPassed(uint256 tokenIdFrom, uint256 tokenIdTo, address yielder);
    event PlayerWon(address indexed player);
    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(bytes32 indexed requestId, uint256 response);

    constructor(address _airnodeRrp)
        payable
        ERC721A("UNKNOWN", "UNKNOWN")
        Ownable(msg.sender)
        RrpRequesterV0(_airnodeRrp)
    {
        gameState = GameState.Queued;
        gameStateStrings[GameState.Queued] = "Queued";
        gameStateStrings[GameState.Minting] = "Minting";
        gameStateStrings[GameState.Playing] = "Playing";
        gameStateStrings[GameState.Paused] = "Paused";
        gameStateStrings[GameState.Ended] = "Ended";
        _owner = msg.sender;
        _currentIndex = _startTokenId();
    }

    /*
 _______           __       __ __               ________                              __     __                            
|       \         |  \     |  \  \             |        \                            |  \   |  \                           
| ▓▓▓▓▓▓▓\__    __| ▓▓____ | ▓▓\▓▓ _______     | ▓▓▓▓▓▓▓▓__    __ _______   _______ _| ▓▓_   \▓▓ ______  _______   _______ 
| ▓▓__/ ▓▓  \  |  \ ▓▓    \| ▓▓  \/       \    | ▓▓__   |  \  |  \       \ /       \   ▓▓ \ |  \/      \|       \ /       \
| ▓▓    ▓▓ ▓▓  | ▓▓ ▓▓▓▓▓▓▓\ ▓▓ ▓▓  ▓▓▓▓▓▓▓    | ▓▓  \  | ▓▓  | ▓▓ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓\▓▓▓▓▓▓ | ▓▓  ▓▓▓▓▓▓\ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓
| ▓▓▓▓▓▓▓| ▓▓  | ▓▓ ▓▓  | ▓▓ ▓▓ ▓▓ ▓▓          | ▓▓▓▓▓  | ▓▓  | ▓▓ ▓▓  | ▓▓ ▓▓       | ▓▓ __| ▓▓ ▓▓  | ▓▓ ▓▓  | ▓▓\▓▓    \ 
| ▓▓     | ▓▓__/ ▓▓ ▓▓__/ ▓▓ ▓▓ ▓▓ ▓▓_____     | ▓▓     | ▓▓__/ ▓▓ ▓▓  | ▓▓ ▓▓_____  | ▓▓|  \ ▓▓ ▓▓__/ ▓▓ ▓▓  | ▓▓_\▓▓▓▓▓▓\
| ▓▓      \▓▓    ▓▓ ▓▓    ▓▓ ▓▓ ▓▓\▓▓     \    | ▓▓      \▓▓    ▓▓ ▓▓  | ▓▓\▓▓     \  \▓▓  ▓▓ ▓▓\▓▓    ▓▓ ▓▓  | ▓▓       ▓▓
 \▓▓       \▓▓▓▓▓▓ \▓▓▓▓▓▓▓ \▓▓\▓▓ \▓▓▓▓▓▓▓     \▓▓       \▓▓▓▓▓▓ \▓▓   \▓▓ \▓▓▓▓▓▓▓   \▓▓▓▓ \▓▓ \▓▓▓▓▓▓ \▓▓   \▓▓\▓▓▓▓▓▓▓ 
                                                                                                                                                                                                                                                 
*/

    function mintHand() external payable nonReentrant {
        require(gameState == GameState.Minting, "Game not minting");
        require(!hasMinted[msg.sender], "Only 1 per wallet");
        require(totalSupply() + 1 <= maxSupply, "Max supply reached");
        // decide on price :)

        _mintHand();

        hasMinted[msg.sender] = true;
        hasBet[msg.sender] = true;
        roundFunds[currentGeneration] += msg.value;
    }

    function joinGame(uint256[] calldata tokenIds)
        external
        payable
        nonReentrant
    {
        require(gameState == GameState.Queued, "Game is not in Queued state");

        // Iterate through each tokenId provided
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            require(ownerOf(tokenId) == msg.sender, "You do not own this NFT");
            require(hands[tokenId].burnt == true, "NFT is not burnt");

            // Switch the burnt trait to false, allowing the NFT to rejoin the game
            hands[tokenId].burnt = false;

            // Add the token to active tokens
            activeTokens.push(tokenId);

            // Increment the active addresses if this is the first active token for the owner
            if (addressActiveTokenCount[msg.sender] == 0) {
                activeAddresses += 1;
            }

            // Increment the count of active tokens for this owner
            addressActiveTokenCount[msg.sender] += 1;
        }

        // Handle the betting aspect (only once, not per token)
        if (msg.value > 0) {
            hasBet[msg.sender] = true; // Mark the address as having placed a bet
            roundFunds[currentGeneration] += msg.value; // Add the bet to the round's funds
        }

        emit PlayerReadyUp(msg.sender);
    }

    function passPotato(uint256 tokenIdTo) public {
        require(gameState == GameState.Playing, "Game not playing");
        require(!hands[tokenIdTo].burnt, "Target NFT is burnt");
        require(msg.sender != ownerOf(tokenIdTo), "Cannot pass potato to self");
        require(
            msg.sender == ownerOf(potatoTokenId),
            "You don't have the potato yet"
        );

        uint256 passCount = successfulPasses[ownerOf(potatoTokenId)];
        uint256 explosionChance = 5 + (2 * passCount); // 5% base chance + 2% per pass
        require(explosionChance <= 100, "Explosion chance cannot exceed 100%");
        uint256 randomNumber = qrngUint256 % 100;

        if (block.timestamp - lastPassTime[potatoTokenId] > 2 days) {
            processExplosion();
        } else if (randomNumber < explosionChance) {
            processExplosion();
        } else {
            // SUCCESSFULL PASS
            uint256 newPotatoTokenId = tokenIdTo;
            hands[potatoTokenId].hasPotato = false;
            potatoTokenId = newPotatoTokenId;
            hands[potatoTokenId].hasPotato = true;
            lastPassTime[potatoTokenId] = block.timestamp;
            TOTAL_PASSES += 1;
            successfulPasses[msg.sender] += 1;

            emit PotatoPassed(potatoTokenId, tokenIdTo, ownerOf(potatoTokenId));
        }
    }

    function withdrawWinnersFunds() external nonReentrant {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No reward to claim");

        rewards[msg.sender] = 0; // Reset the reward to avoid reentrancy attacks

        // Send the funds to the user
        payable(msg.sender).transfer(reward);
    }

    function getGameState() public view returns (string memory) {
        return gameStateStrings[gameState];
    }

    function getPlayerStats(address player)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            successfulPasses[player],
            failedPasses[player],
            totalWins[player]
        );
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721A, IERC721A)
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        Hand memory hand = hands[tokenId];

        return
            metadataHandler.getTokenURI(
                uint16(tokenId),
                hand.background,
                hand.hand_type,
                hand.hasPotato,
                hand.generation,
                hand.potato,
                hand.burnt
            );
    }

    function getPotatoOwner() public view returns (address) {
        return ownerOf(potatoTokenId);
    }

    function getImageString(uint256 tokenId)
        public
        view
        returns (string memory)
    {
        require(_exists(tokenId), "Not a valid pair of hands");

        Hand memory hand = hands[tokenId];

        return
            metadataHandler.getSVGInterface(
                hand.background,
                hand.hand_type,
                hand.hasPotato,
                hand.potato
            );
    }

    /* 
  ______                                               ________                              __     __                            
 /      \                                             |        \                            |  \   |  \                           
|  ▓▓▓▓▓▓\__   __   __ _______   ______   ______      | ▓▓▓▓▓▓▓▓__    __ _______   _______ _| ▓▓_   \▓▓ ______  _______   _______ 
| ▓▓  | ▓▓  \ |  \ |  \       \ /      \ /      \     | ▓▓__   |  \  |  \       \ /       \   ▓▓ \ |  \/      \|       \ /       \
| ▓▓  | ▓▓ ▓▓ | ▓▓ | ▓▓ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\    | ▓▓  \  | ▓▓  | ▓▓ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓\▓▓▓▓▓▓ | ▓▓  ▓▓▓▓▓▓\ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓
| ▓▓  | ▓▓ ▓▓ | ▓▓ | ▓▓ ▓▓  | ▓▓ ▓▓    ▓▓ ▓▓   \▓▓    | ▓▓▓▓▓  | ▓▓  | ▓▓ ▓▓  | ▓▓ ▓▓       | ▓▓ __| ▓▓ ▓▓  | ▓▓ ▓▓  | ▓▓\▓▓    \ 
| ▓▓__/ ▓▓ ▓▓_/ ▓▓_/ ▓▓ ▓▓  | ▓▓ ▓▓▓▓▓▓▓▓ ▓▓          | ▓▓     | ▓▓__/ ▓▓ ▓▓  | ▓▓ ▓▓_____  | ▓▓|  \ ▓▓ ▓▓__/ ▓▓ ▓▓  | ▓▓_\▓▓▓▓▓▓\
 \▓▓    ▓▓\▓▓   ▓▓   ▓▓ ▓▓  | ▓▓\▓▓     \ ▓▓          | ▓▓      \▓▓    ▓▓ ▓▓  | ▓▓\▓▓     \  \▓▓  ▓▓ ▓▓\▓▓    ▓▓ ▓▓  | ▓▓       ▓▓
  \▓▓▓▓▓▓  \▓▓▓▓▓\▓▓▓▓ \▓▓   \▓▓ \▓▓▓▓▓▓▓\▓▓           \▓▓       \▓▓▓▓▓▓ \▓▓   \▓▓ \▓▓▓▓▓▓▓   \▓▓▓▓ \▓▓ \▓▓▓▓▓▓ \▓▓   \▓▓\▓▓▓▓▓▓▓ 
                                                                                                                                                                                                                                                           
*/

    function startMint() external onlyOwner {
        gameState = GameState.Minting;
        currentGeneration += 1;
        emit NewRound(currentGeneration);
        emit MintingStarted("Minting");
    }

    function startGame() external onlyOwner {
        require(
            gameState == GameState.Minting || gameState == GameState.Queued,
            "Game already started"
        );
        // Reset activeAddresses to count current owners
        activeAddresses = 0;

        // Reset the uniqueOwners mapping
        for (
            uint256 tokenId = _startTokenId();
            tokenId < _nextTokenId();
            tokenId++
        ) {
            if (_exists(tokenId) && !hands[tokenId].burnt) {
                address owner = ownerOf(tokenId);
                uniqueOwners[owner] = false;
            }
        }

        uint256 uniqueOwnersCount = 0;

        // Iterate over all tokens
        for (
            uint256 tokenId = _startTokenId();
            tokenId < _nextTokenId();
            tokenId++
        ) {
            if (_exists(tokenId) && !hands[tokenId].burnt) {
                address owner = ownerOf(tokenId);
                if (!uniqueOwners[owner]) {
                    uniqueOwners[owner] = true;
                    uniqueOwnersCount++;
                }
            }
        }
        activeAddresses = uniqueOwnersCount;

        //Assign Potato to random Token with ChainLinkVRF2
        require(qrngUint256 > 0, "No Random Number Found Yet");
        potatoTokenId = assignPotato();
        require(potatoTokenId > 0, "Failed to assign potato");
        hands[potatoTokenId].hasPotato = true;
        lastPassTime[potatoTokenId] = block.timestamp;
        gameState = GameState.Playing;
        emit GameStarted("Playing");
    }

    function pauseGame() external onlyOwner {
        require(
            gameState == GameState.Playing || gameState == GameState.Minting,
            "Game not playing"
        );
        previousGameState = gameState;
        gameState = GameState.Paused;
        emit GamePaused("Paused");
    }

    function makeRequestUint256() public onlyOwner {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        waitingFulfillment[requestId] = true;
        emit RequestedUint256(requestId);
    }

    function resumeGame() external onlyOwner {
        require(gameState == GameState.Paused, "Game not paused");
        if (previousGameState == GameState.Playing) {}
        gameState = previousGameState;
        previousGameState = GameState.Queued;
        emit GameResumed("The game has resumed");
    }

    function restartGame() external onlyOwner {
        require(
            gameState == GameState.Paused || gameState == GameState.Ended,
            "Game not paused or ended"
        );

        gameState = GameState.Queued;

        for (uint256 i = 0; i < players.length; i++) {
            uint256[] memory tokens = tokensOwnedByUser[players[i]];
            for (uint256 j = 0; j < tokens.length; j++) {
                hands[tokens[j]].burnt = true;
            }
        }

        potatoTokenId = 0;
        TOTAL_PASSES = 0;
        activeAddresses = 0;

        for (uint256 i = 0; i < players.length; i++) {
            addressActiveTokenCount[players[i]] = 0;
        }

        delete players;
        delete activeTokens; // Clear and reinitialize active tokens array
        roundFunds[currentGeneration] = 0;

        emit GameRestarted("Queued");
    }

    function setInventoryManager(address addy) external onlyOwner {
        metadataHandler = MetadataHandler(addy);
    }

    function withdrawCategoryFunds(uint256 round, string memory category)
        external
        onlyOwner
        nonReentrant
    {
        uint256 amount;
        if (
            keccak256(abi.encodePacked((category))) ==
            keccak256(abi.encodePacked(("project")))
        ) {
            amount = projectFunds[round];
            require(amount > 0, "No funds to withdraw");
            projectFunds[round] = 0;
            payable(msg.sender).transfer(amount);
            return;
        } else if (
            keccak256(abi.encodePacked((category))) ==
            keccak256(abi.encodePacked(("team")))
        ) {
            amount = teamFunds[round];
            require(amount > 0, "No funds to withdraw");
            teamFunds[round] = 0;

            address nonPayableAddr1 = 0x41447b831CBbffb74883eFF27FC5AaA13BE3CA52;
            address nonPayableAddr2 = 0x57b18277B530Fa0C1748C29F9b1887B7691FF701;

            address payable teamMember1 = payable(nonPayableAddr1);
            address payable teamMember2 = payable(nonPayableAddr2);

            uint256 halfAmount = amount / 2;

            teamMember1.transfer(halfAmount);
            teamMember2.transfer(halfAmount);

            return;
        } else if (
            keccak256(abi.encodePacked((category))) ==
            keccak256(abi.encodePacked(("charity")))
        ) {
            amount = charityFunds[round];
            require(amount > 0, "No funds to withdraw");
            charityFunds[round] = 0;

            payable(0x376e50f9036D29038b8aC9Bc12C2E9CF9418d451).transfer(
                amount
            );
            return;
        } else {
            revert("Invalid category");
        }
    }

    /*
 ______            __                                         __      ________                              __     __                            
|      \          |  \                                       |  \    |        \                            |  \   |  \                           
 \▓▓▓▓▓▓_______  _| ▓▓_    ______   ______  _______   ______ | ▓▓    | ▓▓▓▓▓▓▓▓__    __ _______   _______ _| ▓▓_   \▓▓ ______  _______   _______ 
  | ▓▓ |       \|   ▓▓ \  /      \ /      \|       \ |      \| ▓▓    | ▓▓__   |  \  |  \       \ /       \   ▓▓ \ |  \/      \|       \ /       \
  | ▓▓ | ▓▓▓▓▓▓▓\\▓▓▓▓▓▓ |  ▓▓▓▓▓▓\  ▓▓▓▓▓▓\ ▓▓▓▓▓▓▓\ \▓▓▓▓▓▓\ ▓▓    | ▓▓  \  | ▓▓  | ▓▓ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓\▓▓▓▓▓▓ | ▓▓  ▓▓▓▓▓▓\ ▓▓▓▓▓▓▓\  ▓▓▓▓▓▓▓
  | ▓▓ | ▓▓  | ▓▓ | ▓▓ __| ▓▓    ▓▓ ▓▓   \▓▓ ▓▓  | ▓▓/      ▓▓ ▓▓    | ▓▓▓▓▓  | ▓▓  | ▓▓ ▓▓  | ▓▓ ▓▓       | ▓▓ __| ▓▓ ▓▓  | ▓▓ ▓▓  | ▓▓\▓▓    \ 
 _| ▓▓_| ▓▓  | ▓▓ | ▓▓|  \ ▓▓▓▓▓▓▓▓ ▓▓     | ▓▓  | ▓▓  ▓▓▓▓▓▓▓ ▓▓    | ▓▓     | ▓▓__/ ▓▓ ▓▓  | ▓▓ ▓▓_____  | ▓▓|  \ ▓▓ ▓▓__/ ▓▓ ▓▓  | ▓▓_\▓▓▓▓▓▓\
|   ▓▓ \ ▓▓  | ▓▓  \▓▓  ▓▓\▓▓     \ ▓▓     | ▓▓  | ▓▓\▓▓    ▓▓ ▓▓    | ▓▓      \▓▓    ▓▓ ▓▓  | ▓▓\▓▓     \  \▓▓  ▓▓ ▓▓\▓▓    ▓▓ ▓▓  | ▓▓       ▓▓
 \▓▓▓▓▓▓\▓▓   \▓▓   \▓▓▓▓  \▓▓▓▓▓▓▓\▓▓      \▓▓   \▓▓ \▓▓▓▓▓▓▓\▓▓     \▓▓       \▓▓▓▓▓▓ \▓▓   \▓▓ \▓▓▓▓▓▓▓   \▓▓▓▓ \▓▓ \▓▓▓▓▓▓ \▓▓   \▓▓\▓▓▓▓▓▓▓ 
                                                                                                                                                 
*/

    function _mintHand() internal returns (uint64 id) {
        uint8 background;
        uint8 hand_type;

        uint256 seventyPct = (type(uint64).max / 100) * 70;
        uint256 ninetyPct = (type(uint64).max / 100) * 90;

        id = uint64(_nextTokenId());

        uint64 randBackground = uint64(_rarity(_rand(), "BACKGROUND", id));
        background = uint8(
            randBackground >= ninetyPct
                ? (randBackground % 3) + 18 //Legendary 18-20
                : randBackground >= seventyPct
                ? (randBackground % 6) + 12 //Rare 12-17
                : (randBackground % 11) + 1 //Common 1-11
        );

        uint64 randHandType = uint64(_rarity(_rand(), "HAND_TYPE", id));
        hand_type = uint8(
            randHandType >= ninetyPct
                ? (randHandType % 5) + 46 //Legendary 46-50
                : randHandType >= seventyPct
                ? (randHandType % 15) + 31 //Rare 31-45
                : (randHandType % 30) + 1 //Common 1-30
        );

        _safeMint(msg.sender, 1);
        activeTokens.push(id);

        activeAddresses += 1;
        players.push(msg.sender);

        addressActiveTokenCount[msg.sender] += 1;
        tokensOwnedByUser[msg.sender].push(id);

        hands[uint256(id)] = Hand({
            hasPotato: false,
            generation: currentGeneration,
            background: background,
            hand_type: hand_type,
            potato: uint8(1),
            burnt: false
        });

        return id;
    }

    function _rarity(
        uint256 rand,
        string memory val,
        uint256 heat
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(rand, val, heat)));
    }

    function _rand() internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        msg.sender,
                        block.timestamp,
                        block.basefee,
                        block.timestamp,
                        entropySauce
                    )
                )
            );
    }

    function assignPotato() internal view returns (uint256) {
        // Ensure that we have active tokens
        require(activeTokens.length > 0, "No active tokens available");

        // Use the random number to pick an index from the active tokens
        uint256 randomIndex = qrngUint256 % activeTokens.length;

        // Get the token ID from the active tokens array
        uint256 selectedTokenId = activeTokens[randomIndex];

        // Double-check that the selected token is still active
        require(!hands[selectedTokenId].burnt, "Selected token is not active");

        return selectedTokenId;
    }

    function _isTokenActive(uint256 tokenId) public view returns (bool) {
        if (!hands[tokenId].burnt) {
            return false;
        }
        return false;
    }

    function processExplosion() internal {
        require(gameState == GameState.Playing, "Game not playing");

        address failedPlayer = ownerOf(potatoTokenId);
        failedPasses[failedPlayer] += 1;

        // 2. Remove the potato from the exploded NFT & set Burn trait
        hands[potatoTokenId].hasPotato = false;

        // 3. Remove the exploded NFT from the activeTokens array
        hands[potatoTokenId].burnt = true;
        if (activeTokens.length > 0) {
            for (uint256 i = 0; i < activeTokens.length; i++) {
                if (activeTokens[i] == potatoTokenId) {
                    if (i != activeTokens.length - 1) {
                        activeTokens[i] = activeTokens[activeTokens.length - 1];
                    }
                    activeTokens.pop();
                    break;
                }
            }
        }

        // 4. Emit an event to notify that the potato exploded and get ready to assign potato to a rand tokenId
        emit PotatoExploded(potatoTokenId, failedPlayer);
        potatoTokenId = assignPotato();

        hands[potatoTokenId].hasPotato = true;

        // Decrease the count of active tokens for the failed player
        addressActiveTokenCount[failedPlayer] -= 1;

        // Check if the failed player owns any active (not burnt) tokens
        bool hasActiveTokens = false;
        uint256[] memory tokens = tokensOwnedByUser[failedPlayer];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!hands[tokens[i]].burnt) {
                hasActiveTokens = true;
                break;
            }
        }

        // If the failed player has no more active tokens, decrease the count of active addresses
        if (!hasActiveTokens) {
            activeAddresses -= 1;
        }

        // 5. Check if there are still active betters
        uint256 activeBetters = 0;
        address lastBetter;
        for (uint256 i = 0; i < activeTokens.length; i++) {
            address tokenOwner = ownerOf(activeTokens[i]);
            if (!hands[activeTokens[i]].burnt && hasBet[tokenOwner]) {
                activeBetters += 1;
                lastBetter = tokenOwner;

                if (activeBetters >= 2) {
                    break; // Exit the loop early if we find at least 2 active betters
                }
            }
        }

        if (activeBetters < 2) {
            rewards[lastBetter] += (roundFunds[currentGeneration] * 4) / 10;
            projectFunds[currentGeneration] +=
                (roundFunds[currentGeneration] * 1) /
                10;
            teamFunds[currentGeneration] +=
                (roundFunds[currentGeneration] * 3) /
                10;
            charityFunds[currentGeneration] +=
                (roundFunds[currentGeneration] * 2) /
                10;
        }

        // 5. Check if the game should move to the final round or end
        if (activeAddresses == 1) {
            gameState = GameState.Ended;
            emit PlayerWon(ownerOf(activeTokens[1]));
            winners.push(ownerOf(activeTokens[1]));
            totalWins[ownerOf(activeTokens[1])] += 1;
        }
    }

    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256,
        address _sponsorWallet
    ) external {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        sponsorWallet = _sponsorWallet;
    }

    function fulfillUint256(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(waitingFulfillment[requestId], "Request ID not known");
        waitingFulfillment[requestId] = false;
        qrngUint256 = abi.decode(data, (uint256));
        // Do what you want with `qrngUint256` here...
        emit ReceivedUint256(requestId, qrngUint256);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }
}
