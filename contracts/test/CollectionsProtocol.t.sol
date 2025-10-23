// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ERC721EthscriptionsCollectionManager.sol";
import "../src/Ethscriptions.sol";
import "../src/libraries/Predeploys.sol";
import "./TestSetup.sol";

contract CollectionsProtocolTest is TestSetup {
    address alice = makeAddr("alice");
    
    function test_CreateCollection() public {
        // Encode collection metadata as ABI tuple
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata = ERC721EthscriptionsCollectionManager.CollectionMetadata({
            name: "Test Collection",
            symbol: "TEST",
            totalSupply: 100,
            description: "A test collection",
            logoImageUri: "https://example.com/logo.png",
            bannerImageUri: "",
            backgroundColor: "",
            websiteLink: "",
            twitterLink: "",
            discordLink: ""
        });

        bytes memory encodedMetadata = abi.encode(metadata);

        // Create the ethscription
        bytes32 txHash = keccak256("create_collection_tx");

        vm.prank(address(ethscriptions));
        collectionsHandler.op_create_collection(txHash, encodedMetadata);

        // Verify collection was created
        bytes32 collectionId = txHash;

        // Use the getter functions instead of direct mapping access
        ERC721EthscriptionsCollectionManager.CollectionState memory state = collectionsHandler.getCollectionState(collectionId);
        assertNotEq(state.collectionContract, address(0), "Collection contract should be deployed");
        assertEq(state.createEthscriptionId, txHash, "Create ethscription ID should match");
        assertEq(state.currentSize, 0, "Initial size should be 0");
        assertEq(state.locked, false, "Should not be locked");

        // Verify metadata
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory storedMetadata = collectionsHandler.getCollectionMetadata(collectionId);
        assertEq(storedMetadata.name, "Test Collection", "Name should match");
        assertEq(storedMetadata.symbol, "TEST", "Symbol should match");
        assertEq(storedMetadata.totalSupply, 100, "Total supply should match");
        assertEq(storedMetadata.description, "A test collection", "Description should match");
    }

    function test_CreateCollectionEndToEnd() public {
        // Full end-to-end test: create ethscription with JSON, let it call the protocol handler

        // The JSON data
        string memory json = '{"p":"erc-721-ethscriptions-collection","op":"create_collection","name":"Test NFTs","symbol":"TEST","totalSupply":"100","description":"","logoImageUri":"","bannerImageUri":"","backgroundColor":"","websiteLink":"","twitterLink":"","discordLink":""}';

        // Encode the metadata as the protocol handler expects
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata = ERC721EthscriptionsCollectionManager.CollectionMetadata({
            name: "Test NFTs",
            symbol: "TEST",
            totalSupply: 100,
            description: "",
            logoImageUri: "",
            bannerImageUri: "",
            backgroundColor: "",
            websiteLink: "",
            twitterLink: "",
            discordLink: ""
        });

        bytes memory encodedProtocolData = abi.encode(metadata);

        // Create the ethscription with protocol params
        bytes32 txHash = keccak256(abi.encodePacked("test_collection_tx", block.timestamp));

        Ethscriptions.CreateEthscriptionParams memory params = Ethscriptions.CreateEthscriptionParams({
            ethscriptionId: txHash,
            contentUriHash: keccak256(bytes(json)),
            initialOwner: alice,
            content: bytes(json),
            mimetype: "application/json",
            esip6: false,
            protocolParams: Ethscriptions.ProtocolParams({
                protocolName: "erc-721-ethscriptions-collection",
                operation: "create_collection",
                data: encodedProtocolData
            })
        });

        // Create the ethscription - this will call the protocol handler automatically
        vm.prank(alice);
        ethscriptions.createEthscription(params);

        bytes32 collectionId = txHash;

        // Read back the state
        ERC721EthscriptionsCollectionManager.CollectionState memory state = collectionsHandler.getCollectionState(collectionId);

        console.log("Collection exists:", state.collectionContract != address(0));
        console.log("Collection contract:", state.collectionContract);
        console.log("Current size:", state.currentSize);

        // Verify the collection was created
        assertTrue(state.collectionContract != address(0), "Collection should exist");
        assertEq(state.createEthscriptionId, txHash);
        assertEq(state.currentSize, 0);
        assertEq(state.locked, false);

        // Read metadata
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory storedMetadata = collectionsHandler.getCollectionMetadata(collectionId);
        assertEq(storedMetadata.name, "Test NFTs");
        assertEq(storedMetadata.symbol, "TEST");
        assertEq(storedMetadata.totalSupply, 100);
    }

    function test_ReadCollectionStateViaEthCall() public {
        // Create a collection first
        ERC721EthscriptionsCollectionManager.CollectionMetadata memory metadata = ERC721EthscriptionsCollectionManager.CollectionMetadata({
            name: "Call Test",
            symbol: "CALL",
            totalSupply: 50,
            description: "",
            logoImageUri: "",
            bannerImageUri: "",
            backgroundColor: "",
            websiteLink: "",
            twitterLink: "",
            discordLink: ""
        });

        bytes32 txHash = keccak256("call_test_tx");

        vm.prank(address(ethscriptions));
        collectionsHandler.op_create_collection(txHash, abi.encode(metadata));

        // Now simulate an eth_call to read the state
        bytes32 collectionId = txHash;

        // Encode the function call: getCollectionState(bytes32)
        bytes memory callData = abi.encodeWithSelector(
            collectionsHandler.getCollectionState.selector,
            collectionId
        );

        console.log("Call data:");
        console.logBytes(callData);

        // Make the call
        (bool success, bytes memory result) = address(collectionsHandler).staticcall(callData);
        assertTrue(success, "Static call should succeed");

        console.log("Result:");
        console.logBytes(result);

        // Decode the result
        ERC721EthscriptionsCollectionManager.CollectionState memory state = abi.decode(result, (ERC721EthscriptionsCollectionManager.CollectionState));

        assertTrue(state.collectionContract != address(0), "Should have collection contract");
        assertEq(state.createEthscriptionId, txHash);
        assertEq(state.currentSize, 0);
        assertEq(state.locked, false);

        console.log("Successfully read collection state via eth_call!");
    }
}
