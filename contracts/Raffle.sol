/* 
Raffle contract

Step by step:
1. Enter the lottery
2. Pay some amount of ETH
3. Pick a random winner
4. Winner will be selected automatically every X minutes

Additional:
I need chainlink oracle -> randomness 
& automated execution (chainlink keeper) 
*/

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

/* Errors */
error Raffle__NotEnoughETHEntered();
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotneeded(
    uint256 currentBalance,
    uint256 numPlayers,
    uint256 raffleState
);

/** @title Just a sample Raffle Contract
 * @author Arslan Galimov
 * @notice This contract is for creating untamperable decentralized smart contract
 * @dev This implements Chainlink VRF V2 and Chainlink Keepers
 *
 */

contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    } // uint256 0 = OPEN, 1 = CALCULATING

    /* State Variables */
    uint256 private immutable entranceFee;
    address payable[] private players;
    VRFCoordinatorV2Interface private immutable vrfCoordinator;
    bytes32 private immutable keyHash;
    uint64 private immutable s_subscriptionId;
    uint32 private immutable callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    // Lottery Variables
    address private s_recentWinner;
    RaffleState private raffleState;
    uint256 private lastTimeStamp;
    uint256 private immutable interval;

    /* Events */
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    /* Functions */
    constructor(
        address vrfCoordinatorV2,
        uint256 _entranceFee,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint256 _interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        entranceFee = _entranceFee;
        vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        keyHash = _keyHash;
        s_subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        raffleState = RaffleState.OPEN;
        lastTimeStamp = block.timestamp;
        interval = _interval;
    }

    function enterRaffle() public payable {
        if (msg.value < entranceFee) {
            revert Raffle__NotEnoughETHEntered();
        }
        if (raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev "checkUpkeep" is the function that the Chainlink Keeper nodes
     * call, they look for the `upkeepNeeded` to return true.
     * The following should be true in order to return true:
     * 1. Our time interval should have passed
     * 2. The lottery should have at least 1 player, and have some ETH
     * 3. Our subscription is funded with LINK
     * 4. The lottery should be in an "open" state.
     */

    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool isOpen = (RaffleState.OPEN == raffleState);
        bool timePassed = ((block.timestamp - lastTimeStamp) > interval);
        bool hasPlayers = (players.length > 0);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotneeded(
                address(this).balance,
                players.length,
                uint256(raffleState)
            );
        }

        raffleState = RaffleState.CALCULATING;
        uint256 requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            s_subscriptionId,
            REQUEST_CONFIRMATIONS,
            callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % players.length;
        address payable recentWinner = players[indexOfWinner];
        s_recentWinner = recentWinner;
        raffleState = RaffleState.OPEN;
        players = new address payable[](0);
        lastTimeStamp = block.timestamp;

        (bool succes, ) = recentWinner.call{value: address(this).balance}("");
        if (!succes) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }

    /* View / Pure functions */
    function getEntranceFee() public view returns (uint256) {
        return entranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return raffleState;
    }

    function getNumwords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return players.length;
    }

    function getLatestTimeStamp() public view returns (uint256) {
        return lastTimeStamp;
    }

    function getRequestComfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getInterval() public view returns (uint256) {
        return interval;
    }
}
