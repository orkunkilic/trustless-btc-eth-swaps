// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {IBonsaiRelay} from "bonsai/IBonsaiRelay.sol";
import {BonsaiCallbackReceiver} from "bonsai/BonsaiCallbackReceiver.sol";

/// @title A bitcoin block hash and merkle root tracker using Bonsai Relay
contract LightClient is BonsaiCallbackReceiver {
    // Last verfied and saved blockhash
    bytes32 public lastBlockHash;

    // Last verified work
    uint256 public lastWork;

    // Mapping of blockhashes to merkle roots of that block
    mapping(bytes32 => bytes32) public blockHashToMerkleRoot;

    /// @notice Image ID of the only zkVM binary to accept callbacks from.
    bytes32 public immutable imageId;

    /// @notice Gas limit set on the callback from Bonsai.
    /// @dev Should be set to the maximum amount of gas your callback might reasonably consume.
    uint64 private constant BONSAI_CALLBACK_GAS_LIMIT = 1000000;

    /// @notice Initialize the contract, binding it to a specified Bonsai relay and RISC Zero guest image.
    constructor(IBonsaiRelay bonsaiRelay, bytes32 _imageId) BonsaiCallbackReceiver(bonsaiRelay) {
        imageId = _imageId;
    }

    event VerifyBitcoinBlockCallback(bytes32 indexed blockHash, bytes32 merkleRoot);

    /// @notice Returns the merkle root of the given block.
    function bitcoinMerkleRoot(bytes32 blockHash) external view returns (bytes32) {
        bytes32 result = blockHashToMerkleRoot[blockHash];
        require(result != 0, "value not available in cache");
        return result;
    }

    /// @notice Callback function logic for processing verified journals from Bonsai.
    function storeResult(bytes32 blockHash, bytes32 merkleRoot, bytes32 previousBlockHash, uint256 work)
        external
        onlyBonsaiCallback(imageId)
    {
        require(previousBlockHash == lastBlockHash || lastBlockHash == 0x0, "previous block hash does not match");

        require(work > lastWork || lastWork == 0, "work does not increase");

        emit VerifyBitcoinBlockCallback(blockHash, merkleRoot);

        blockHashToMerkleRoot[blockHash] = merkleRoot;

        lastBlockHash = blockHash;

        lastWork = work;
    }

    /// @notice Sends a request to Bonsai to have have the Bitcoin header verified.
    /// @dev This function sends the request to Bonsai through the on-chain relay.
    ///      The request will trigger Bonsai to run the specified RISC Zero guest program with
    ///      the given input and asynchronously return the verified results via the callback below.
    function verifyBitcoinBlockHeader(bytes calldata header) external {
        bonsaiRelay.requestCallback(
            imageId, header, address(this), this.storeResult.selector, BONSAI_CALLBACK_GAS_LIMIT
        );
    }

    function verifyTransaction(bytes32 blockHash, bytes calldata transaction, bytes32[] calldata merkleProof)
        public
        view
        returns (bool)
    {
        bytes32 merkleRoot = blockHashToMerkleRoot[blockHash];

        require(merkleRoot != 0, "block hash not verified");

        bytes32 txHash = sha256(abi.encodePacked(sha256(abi.encodePacked(transaction))));

        return verifyBitcoinMerkleProof(txHash, merkleProof, merkleRoot);
    }

    function verifyBitcoinMerkleProof(bytes32 txHash, bytes32[] calldata merkleProof, bytes32 merkleRoot)
        internal
        pure
        returns (bool)
    {
        bytes32 computedHash = txHash;

        for (uint256 i = 0; i < merkleProof.length; i++) {
            bytes32 proofElement = merkleProof[i];

            if (computedHash < proofElement) {
                computedHash = sha256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = sha256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == merkleRoot;
    }
}
