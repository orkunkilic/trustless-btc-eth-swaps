// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {LightClient} from "./LightClient.sol";

contract OrderBook {
    LightClient public lightClient;
    uint256 public constant EXTRA_SETTLEMENT_TIME = 3 * 60 * 60; // 3 hours

    event OrderCreated(
        bytes32 btcAddress, bytes32 orderHash, uint256 btcAmount, uint256 etherAmount, uint256 deadline, address buyer
    );
    event OrderSettled(bytes32 orderHash, bytes32 btcAddress, uint256 btcAmount, uint256 etherAmount, address buyer);
    event OrderReclaimed(bytes32 orderHash, bytes32 btcAddress, uint256 btcAmount, uint256 etherAmount, address buyer);

    struct Order {
        bytes32 btcAddress;
        uint256 btcAmount;
        uint256 etherAmount;
        uint256 deadline;
        address payable buyer;
        bool isActive;
        bool isSettled;
    }

    struct BitcoinTransaction {
        uint8 version;
        uint8 lockTime;
        uint8 inputCount;
        uint8 outputCount;
        uint8[] inputAmounts;
        uint8[] outputAmounts;
        bytes32[] inputHashes;
        bytes32[] outputHashes;
        bytes32[] inputScripts;
        bytes32[] outputScripts;
    }

    mapping(bytes32 => Order) public orders;

    constructor(LightClient _lightClient) {
        lightClient = _lightClient;
    }

    function buyBTC(bytes32 btcAddress, uint256 btcAmount, uint256 etherAmount, uint256 deadline) external payable {
        require(msg.value == etherAmount, "etherAmount is not equal to msg.value");
        require(block.timestamp <= deadline, "Deadline has passed");

        bytes32 orderHash = keccak256(abi.encodePacked(btcAddress, btcAmount, etherAmount, deadline, msg.sender));

        orders[orderHash] = Order(btcAddress, btcAmount, etherAmount, deadline, payable(msg.sender), true, false);

        emit OrderCreated(btcAddress, orderHash, btcAmount, etherAmount, deadline, msg.sender);
    }

    function reclaimEther(bytes32 orderHash) external {
        Order memory order = orders[orderHash];

        require(order.buyer == msg.sender, "Only buyer can reclaim ether");
        require(block.timestamp > order.deadline + EXTRA_SETTLEMENT_TIME, "Deadline has not passed yet");

        orders[orderHash].isActive = false;

        payable(msg.sender).transfer(order.etherAmount);

        emit OrderReclaimed(orderHash, order.btcAddress, order.btcAmount, order.etherAmount, order.buyer);
    }

    function settleOrder(
        bytes32 orderHash,
        bytes calldata transaction,
        bytes32[] calldata proof,
        bytes32 blockHash,
        bytes calldata signature
    ) external {
        // Check signature against settlementHash & msg.sender
        bytes32 settlementHash = keccak256(abi.encodePacked(orderHash, transaction, proof, blockHash));
        uint8 v = uint8(signature[0]);
        bytes32 r = bytes32(signature[1:33]);
        bytes32 s = bytes32(signature[33:65]);
        address signer = ecrecover(settlementHash, v, r, s);
        require(signer == msg.sender, "Signature is not valid");

        // Get order
        Order memory order = orders[orderHash];

        require(order.isActive, "Order is not active");
        require(!order.isSettled, "Order is already settled");
        require(block.timestamp <= order.deadline, "Deadline has passed");
        require(block.timestamp > order.deadline + EXTRA_SETTLEMENT_TIME, "Deadline has not passed yet");

        // Verify transaction is in block
        require(lightClient.verifyTransaction(blockHash, transaction, proof), "Transaction is not in block");

        // Verify contents of transaction
        BitcoinTransaction memory bitcoinTransaction = parseTransaction(transaction);
        // Verify amount is correct
        require(bitcoinTransaction.outputAmounts[0] == order.btcAmount, "Transaction change amount is not correct");
        // Verify recipient is correct. Script is p2pkh. pk is order.btcAddress
        bytes32 pkHash = sha256(abi.encodePacked(order.btcAddress));
        require(bitcoinTransaction.outputScripts[0] == pkHash, "Transaction change recipient is not correct");

        // Mark order as settled
        orders[orderHash].isSettled = true;
        orders[orderHash].isActive = false;

        payable(msg.sender).transfer(order.etherAmount);

        emit OrderSettled(orderHash, order.btcAddress, order.btcAmount, order.etherAmount, order.buyer);
    }

    // Parse Bitcoin transaction from bytes
    function parseTransaction(bytes calldata transaction) internal pure returns (BitcoinTransaction memory) {
        uint8 version = uint8(transaction[0]);
        uint8 lockTime = uint8(transaction[4]);

        uint8 inputCount = uint8(transaction[36]);
        uint8 outputCount = uint8(transaction[37]);

        uint8[] memory inputAmounts = new uint8[](inputCount);
        uint8[] memory outputAmounts = new uint8[](outputCount);
        bytes32[] memory inputHashes = new bytes32[](inputCount);
        bytes32[] memory outputHashes = new bytes32[](outputCount);
        bytes32[] memory inputScripts = new bytes32[](inputCount);
        bytes32[] memory outputScripts = new bytes32[](outputCount);

        uint256 offset = 38;

        for (uint256 i = 0; i < inputCount; i++) {
            inputAmounts[i] = uint8(transaction[offset]);
            offset += 8;
        }

        for (uint256 i = 0; i < inputCount; i++) {
            inputHashes[i] = bytes32(transaction[offset:offset + 32]);
            offset += 32;
        }

        for (uint256 i = 0; i < inputCount; i++) {
            inputScripts[i] = bytes32(transaction[offset:offset + 32]);
            offset += 32;
        }

        for (uint256 i = 0; i < outputCount; i++) {
            outputAmounts[i] = uint8(transaction[offset]);
            offset += 8;
        }

        for (uint256 i = 0; i < outputCount; i++) {
            outputHashes[i] = bytes32(transaction[offset:offset + 32]);
            offset += 32;
        }

        for (uint256 i = 0; i < outputCount; i++) {
            outputScripts[i] = bytes32(transaction[offset:offset + 32]);
            offset += 32;
        }

        return BitcoinTransaction(
            version,
            lockTime,
            inputCount,
            outputCount,
            inputAmounts,
            outputAmounts,
            inputHashes,
            outputHashes,
            inputScripts,
            outputScripts
        );
    }
}
