/*
This is an example of deployment of AvalancheRaffleSender and MonadRaffleReceiver on testnet.
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {AvalancheRaffleSender} from "../src/AvalancheRaffleSender.sol";
import {MonadRaffleReceiver} from "../src/MonadRaffleReceiver.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

/// constant values
abstract contract Constants {
    address public constant CCIP_AVALANCHE_FUJINET_ROUTER =
        0xF694E193200268f9a4868e4Aa017A0118C9a8177;
    address public constant CCIP_MONAD_TESTNET_ROUTER =
        0x5f16e51e3Dcb255480F090157DD01bA962a53E54;
    address public constant AVALANCHE_FUJINET_LINK_TOKEN_CONTRACTS =
        0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846;
    address public constant AVALANCHE_FUJINET_VRF_COORDINATOR =
        0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE; //V2.5
    bytes32 public constant AVALANCHE_FUJINET_GAS_LANE =
        0xc799bd1e3bd4d1a41cd4968997a4e03dfd2a3c7c04b695881138580163f42887; // there is only one GAS_LANE for Avalanche's fuji net.
    uint64 public constant DESTINATION_CHAIN_SELECTOR_MONAD_TESTNET =
        2183018362218727504;
}

contract DeployExample is Constants, Script {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 subscriptionId = 0; // get your subscriptionId from the VRF subscription manager
        uint256 interval = 604800; // 7 days
        uint32 callbackGasLimit = 2500000; // max gas limit of VRF on avalanche's fuji net
        uint256 entranceFee = 0.05 ether; // 0.01 ether
        uint256 linkAmount = 5 * 1e18; // fee for CCIP, have to send link to AvalancheRaffleSender
        string memory fujiUrl = "https://api.avax-test.network/ext/bc/C/rpc"; // or get a new rpcurl from alchemy
        string memory monadTestnetUrl = "https://testnet-rpc.monad.xyz"; // or get a new rpcurl from alchemy

        /**
         * step 0: create subscriptionId on vrf.chain.link/fuji
         * url： https://vrf.chain.link/fuji
         * fund it with LINK
         * set subscriptionId
         */

        /**
         * step 1: deploy the AvalancheRaffleSender contract on Avalanche's fuji net
         */
        vm.createSelectFork(fujiUrl);
        vm.startBroadcast();
        AvalancheRaffleSender avalancheRaffleSender = new AvalancheRaffleSender(
            interval,
            CCIP_AVALANCHE_FUJINET_ROUTER,
            AVALANCHE_FUJINET_LINK_TOKEN_CONTRACTS,
            AVALANCHE_FUJINET_VRF_COORDINATOR,
            subscriptionId,
            AVALANCHE_FUJINET_GAS_LANE,
            callbackGasLimit,
            DESTINATION_CHAIN_SELECTOR_MONAD_TESTNET
        );

        /**
         * step 2: fund avalancheRaffleSender with LINK as fee for CCIP
         */
        address senderAddress = address(avalancheRaffleSender);
        IERC20 link = IERC20(AVALANCHE_FUJINET_LINK_TOKEN_CONTRACTS);
        link.safeTransfer(senderAddress, linkAmount);
        vm.stopBroadcast();

        /**
         * step 3: add cosumer to the subscription for using VRF
         * url： https://vrf.chain.link/fuji
         * add the contract address of AvalancheRaffleSender
         */

        /**
         * step 4: deploy the MonadRaffleReceiver contract on Monad testnet
         * you can try enterRaffle() after deploying the contract
         */
        vm.createSelectFork(monadTestnetUrl);
        vm.startBroadcast();
        MonadRaffleReceiver monadRaffleReceiver = new MonadRaffleReceiver(
            CCIP_MONAD_TESTNET_ROUTER,
            entranceFee,
            senderAddress
        );
        address receiverAddress = address(monadRaffleReceiver);
        vm.startBroadcast();

        /**
         * step 5: set the receiver address in AvalancheRaffleSender contract
         */
        vm.createSelectFork(fujiUrl);
        vm.startBroadcast();
        avalancheRaffleSender = AvalancheRaffleSender(senderAddress);
        avalancheRaffleSender.setReceiver(receiverAddress);
        vm.stopBroadcast();

        /**
         * step 6: go to https://automation.chain.link/ for setting up the keepers
         * add the contract address of AvalancheRaffleSender and fund it with LINK
         */
    }
}
