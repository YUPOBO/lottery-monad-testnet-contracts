// SPDX-License-Identifier: MIT
/*
This is a web3 lottery automatically executed periodically on monad testnet.
The probability of winning is proportional to the player's invested amount.
In monad testnet, Chainlink has not yet implemented VRF and Keepers, 
but Chainlink's CCIP can be used in monad. Therefore:
    1. Using VRF on Avalanche's fuji net to generate random numbers. 
    2. Using CCIP to send random numbers to Monad testnet (The function of selecting winner is implemented in _ccipReceive).
    3. Using Keepers on Avalanche's fuji net to periodically call the sned function. 
This is the code for the sender deployed on Avalanche's fuji net.
 */
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip@1.5.1-beta.0/src/v0.8/ccip/interfaces/IRouterClient.sol";
//import {OwnerIsCreator} from "@chainlink/contracts-ccip@1.5.1-beta.0/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip@1.5.1-beta.0/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";


/**
 * @title Random number sender on Avalanche fuji net for lottery program on Monad testnet
 * @author XIbo Fan
 * @notice use VRF to get random number, use Keepers to make periodic calls, use CCIP to send data and call function on Monad end
 */

contract AvalancheRaffleSender is VRFConsumerBaseV2Plus, AutomationCompatibleInterface{
//contract AvalancheRaffleSender is OwnerIsCreator {
    using SafeERC20 for IERC20;
    /* Errors */
    error AvalancheRaffleSender__UpkeepNotNeeded(address receiver, uint256 linkTokenBalance);
    error AvalancheRaffleSender__NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); 
    error MonadRaffleReceiver__SetReceiverFirst();

    /* State variables */
    // Lottery Variables
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;

    // Chainlink keepers Variables
    uint256 private s_counter;
    bool private s_firstTime;

    // Chainlink CCIP Variables
    uint64 private immutable i_destinationChainSelector;
    IRouterClient private s_ccipRouter;
    IERC20 private s_linkToken;
    address private s_receiver;
    //destinationChainSelector_MONAD_TESTNET = 2183018362218727504
    //CCIP_AVALANCHE_FUJINET_ROUTER = 0xF694E193200268f9a4868e4Aa017A0118C9a8177
    //AVALANCHE_FUJINET_LINK_Token_Contracts = 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846
    //AVALANCHE_FUJINET vrfCoordinatorV2 = 0x2eD832Ba664535e5886b75D64C46EB9a228C2610


    // Chainlink VRF Variables
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /* Events */
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        uint256 text, // The text being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    constructor(
        uint256 interval,
        address ccipRouter, 
        address _link,
        address vrfCoordinatorV2,
        uint256 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit,
        uint64 destinationChainSelector
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_interval = interval;
        s_ccipRouter = IRouterClient(ccipRouter);
        s_linkToken = IERC20(_link);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        i_destinationChainSelector = destinationChainSelector;
        s_lastTimeStamp = block.timestamp;
        s_firstTime = true;
    }


    /* Functions */
    /// set MonadRaffleReceiver address on Monad
    function setReceiver(address receiver) external onlyOwner{
        s_receiver = receiver;
    }

    /// Chainlink Keeper looks for `upkeepNeeded` to return True.
     function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasReceiver = (s_receiver != 0x0000000000000000000000000000000000000000);
        bool hasLinkBalance  = (s_linkToken.balanceOf(address(this)) > 0);
        if (s_firstTime) {
            upkeepNeeded = (hasReceiver && hasLinkBalance);
            return (upkeepNeeded, "0x0"); 
        }
        upkeepNeeded = (timePassed && hasReceiver && hasLinkBalance);
        return (upkeepNeeded, "0x0"); 
    }

    /// Once `checkUpkeep` is returning `true`, this function is called
    /// Use VRF to get random number. Function fulfillRandomWords will be called.
    function performUpkeep(bytes calldata /* performData */ ) external override {
        if (s_firstTime) {
            s_firstTime = false; 
        }
        s_lastTimeStamp = block.timestamp;
        s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    ///Funciton called by VRF, get random number and send it to MonadRaffleReceiver
    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
        address receiver = s_receiver;
        if (receiver == 0x0000000000000000000000000000000000000000) {
            revert MonadRaffleReceiver__SetReceiverFirst();
        }
        uint256 text = randomWords[0];
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), 
            data: abi.encode(text),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: 200_000, 
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(s_linkToken)
        });
        // Get the fee required to send the message
        uint256 fees = s_ccipRouter.getFee(
            i_destinationChainSelector,
            evm2AnyMessage
        );
        if (fees > s_linkToken.balanceOf(address(this)))
            revert AvalancheRaffleSender__NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);
        // approve the CCIP Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(s_ccipRouter), fees);
        // Send the message through the CCIP router and store the returned message ID
       bytes32 messageId = s_ccipRouter.ccipSend(i_destinationChainSelector, evm2AnyMessage);
        emit MessageSent(
            messageId,
            i_destinationChainSelector,
            receiver,
            text,
            address(s_linkToken),
            fees
        );

    }

    
    function getLinktokenBalance() external view returns (uint256) {
        return s_linkToken.balanceOf(address(this));
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getReceiver() public view returns (address) {
        return s_receiver;
    }

}

