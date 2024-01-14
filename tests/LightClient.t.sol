// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.17;

import {BonsaiTest} from "bonsai/BonsaiTest.sol";
import {IBonsaiRelay} from "bonsai/IBonsaiRelay.sol";
import {LightClient} from "contracts/LightClient.sol";

contract LightClientTest is BonsaiTest {
    function setUp() public withRelay {}

    // Test the LightClient contract by mocking an off-chain callback request
    function testOffChainMock2() public {
        bytes32 imageId = queryImageId("BITCOIN_BLOCK_HEADERS");
        // Deploy a new LightClient instance
        LightClient lightClient = new LightClient(
            IBonsaiRelay(bonsaiRelay),
            imageId
        );

        // Anticipate a callback invocation on the starter contract
        vm.expectCall(address(lightClient), abi.encodeWithSelector(LightClient.storeResult.selector));

        bytes32 newBlockHash = bytes32(
            0x0000000000000000000267a992e2ccb9f30bf5f3e50a85e19f20cc635250f631 // blockhash
        );

        bytes32 merkleRoot = bytes32(
            0xccbca30fc807c979a34b53eed5b7d3b9ed7322dfa4f2502056e8e9441a353866 // merkleroot
        );

        bytes32 prevBlockHash = bytes32(
            0x00000000000000000003860b9bb6e7705e01ff312e8483dc53fe24249464c6b7 // prevblockhash
        );

        uint256 work = uint256(0x123123);

        // Relay the solution as a callback
        uint64 BONSAI_CALLBACK_GAS_LIMIT = 1000000;
        runCallbackRequest(
            imageId,
            abi.encode(newBlockHash, merkleRoot, prevBlockHash, work),
            address(lightClient),
            lightClient.storeResult.selector,
            BONSAI_CALLBACK_GAS_LIMIT
        );

        bytes32 ctcLastBlockHash = lightClient.lastBlockHash();
        assertEq(ctcLastBlockHash, newBlockHash);

        bytes32 ctcMerkleRoot = lightClient.blockHashToMerkleRoot(newBlockHash);
        assertEq(ctcMerkleRoot, merkleRoot);

        uint256 ctcWork = lightClient.lastWork();
        assertEq(ctcWork, work);
    }
}
