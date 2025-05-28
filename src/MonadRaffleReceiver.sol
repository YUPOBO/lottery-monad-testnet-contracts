// SPDX-License-Identifier: MIT
/*
This is a web3 lottery automatically executed periodically on monad testnet.
The probability of winning is proportional to the player's invested amount.
In monad testnet, Chainlink has not yet implemented VRF and Keepers, 
but Chainlink's CCIP can be used in monad. Therefore:
    1. Using VRF on Avalanche's fuji net to generate random numbers. 
    2. Using CCIP to send random numbers to Monad testnet (The function of selecting winner is implemented in _ccipReceive).
    3. Using Keepers on Avalanche's fuji net to periodically call the send function. 
This is the code for the monad end.
 */
pragma solidity 0.8.24;

import {Client} from "@chainlink/contracts-ccip@1.5.1-beta.0/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip@1.5.1-beta.0/src/v0.8/ccip/applications/CCIPReceiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


/**
 * @title A Raffle contract on Monad tesetnet(Avalanche's fuji support)
 * @author XIbo Fan
 */

contract MonadRaffleReceiver is CCIPReceiver, ReentrancyGuard, Ownable {

    /* Errors */
    error MonadRaffleReceiver__SendMoreToEnterRaffle();
    error MonadRaffleReceiver__RaffleNotOpen();
    error MonadRaffleReceiver__TransferFailed();
    error MonadRaffleReceiver__NotEnoughTimePassed();
    error MonadRaffleReceiver__NoPlayers();
    error MonadRaffleReceiver__NoAallowedSender();
    
    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING, //1
        CONTRACT_SUSPENDED //2
    }

    /* State variables */
    // Lottery Variables
    uint256 private immutable i_entranceFee;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;
    mapping(address => uint256) private s_playersBalance;



    // Chainlink CCIP Variables
    address private s_allowedSender;
    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    uint256 private s_lastReceivedText; // Store the last received text.
    //address private constant CCIP_MONAD_TESTNET_ROUTER = 0x5f16e51e3Dcb255480F090157DD01bA962a53E54;

    /* Events */
    event RaffleEnter(address indexed player, uint256 value);
    event RaffleReEnter(address indexed player, uint256 value);
    event WinnerPicked(address indexed player);
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        uint256 text // The text that was received.
    );

    constructor(
        address ccipRouter,
        uint256 entranceFee,
        address allowedSender
    ) CCIPReceiver(ccipRouter) Ownable(msg.sender) {
        i_entranceFee = entranceFee;
        s_raffleState = RaffleState.OPEN;
        s_allowedSender = allowedSender;
    }

    /* Functions */
    /// pay MON to enter raffle. Must pay more than entranceFee 
    function enterRaffle() external payable nonReentrant {
        //require(msg.value > 0, "Must send MOD to enter the raffle");
        //require(s_raffleState == RaffleState.OPEN, "Raffle is not open");
        //less gas:
        if (msg.value < i_entranceFee) {
            revert MonadRaffleReceiver__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert MonadRaffleReceiver__RaffleNotOpen();
        }
        if (s_playersBalance[msg.sender] == 0) {
            //entry first time in this round
            s_players.push(payable(msg.sender));
            s_playersBalance[msg.sender] = msg.value;
            emit RaffleEnter(msg.sender, msg.value);
        } else {
            //not first time this round
            uint256 newValue = s_playersBalance[msg.sender] + msg.value;
            s_playersBalance[msg.sender] = newValue;
            emit RaffleReEnter(msg.sender, newValue);
        }
    }

    /// handle a received message(random number) and pick winner.
    //// this function is called periodically
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        if (s_players.length == 0) {
            revert MonadRaffleReceiver__NoPlayers();
        }
        address sender = abi.decode(any2EvmMessage.sender, (address));
        if (sender != s_allowedSender) {
            revert MonadRaffleReceiver__NoAallowedSender();
        }
        s_raffleState = RaffleState.CALCULATING;
        s_lastReceivedMessageId = any2EvmMessage.messageId;
        // get random number
        uint256 lastReceivedText = abi.decode(any2EvmMessage.data, (uint256));
        s_lastReceivedText = lastReceivedText;
        //pick winner with wieght
        uint256 len = s_players.length;
        /* uint256 totalAmount = 0;
        for (uint256 i = 0; i < len; i++) {
            totalAmount += s_playersBalance[s_players[i]];
        } */
        uint256 totalAmount = address(this).balance;
        uint256 winningNumber = lastReceivedText % totalAmount;
        uint256 cumulativeAmount = 0;
        address payable recentWinner = s_players[0];
        for (uint256 i = 0; i < len; i++) {
            cumulativeAmount += s_playersBalance[s_players[i]];
            if (winningNumber < cumulativeAmount) {
                recentWinner = s_players[i];
                break;
            }
        }
        s_recentWinner = recentWinner;
        // reset players informaiton
        for (uint256 i = 0; i < len; i++) {
            s_playersBalance[s_players[i]] = 0;
        }
        s_players = new address payable[](0);

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);
        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            sender, // abi-decoding of the sender address,
            lastReceivedText
        );
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert MonadRaffleReceiver__TransferFailed();
        }
    }

    /// suspend the contract
    function destruct() external onlyOwner {
        s_raffleState = RaffleState.CONTRACT_SUSPENDED;
    }

    /// open the contract
    function restruct() external onlyOwner {
        s_raffleState = RaffleState.OPEN;
    }

    /* Getter Functions */
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, uint256 text)
    {
        return (s_lastReceivedMessageId, s_lastReceivedText);
    }

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getPlayesLength() external view returns (uint256) {
        return s_players.length;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getPlayerBlance(address player) external view returns (uint256) {
        return s_playersBalance[player];
    }

}
