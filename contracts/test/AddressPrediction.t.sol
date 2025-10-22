// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/libraries/Predeploys.sol";
import "../src/libraries/Proxy.sol";
import "../src/FixedFungibleProtocolHandler.sol";
import "../src/CollectionsProtocolHandler.sol";
import "../src/Ethscriptions.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./TestSetup.sol";

contract AddressPredictionTest is TestSetup {
    // Test predictable address for FixedFungibleProtocolHandler token proxies
    function testPredictFixedFungibleTokenAddress() public {
        // Arrange
        string memory tick = "eths";
        bytes32 deployTxHash = keccak256("deploy-eths");

        // Prepare deploy op data
        FixedFungibleProtocolHandler.DeployOperation memory deployOp = FixedFungibleProtocolHandler.DeployOperation({
            tick: tick,
            maxSupply: 1_000_000,
            mintAmount: 1_000
        });
        bytes memory data = abi.encode(deployOp);

        // Prediction via contract helper
        address predicted = fixedFungibleHandler.predictTokenAddressByTick(tick);

        // Act: call deploy as Ethscriptions (authorized)
        vm.prank(Predeploys.ETHSCRIPTIONS);
        fixedFungibleHandler.op_deploy(deployTxHash, data);

        // Assert actual matches predicted
        address actual = fixedFungibleHandler.getTokenAddressByTick(tick);
        assertEq(actual, predicted, "Predicted token address should match actual deployed proxy");
    }

    // Test predictable address for CollectionsProtocolHandler collection proxies
    function testPredictCollectionsAddress() public {
        // Arrange
        bytes32 collectionId = keccak256("collection-1");

        CollectionsProtocolHandler.CollectionMetadata memory metadata = CollectionsProtocolHandler.CollectionMetadata({
            name: "My Collection",
            symbol: "MYC",
            totalSupply: 1000,
            description: "A test collection",
            logoImageUri: "data:,logo",
            bannerImageUri: "data:,banner",
            backgroundColor: "#000000",
            websiteLink: "https://example.com",
            twitterLink: "",
            discordLink: ""
        });

        // Manually compute predicted proxy address
        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(collectionsHandler)));
        address predicted = Create2.computeAddress(collectionId, keccak256(creationCode), address(collectionsHandler));

        // Act: create collection as Ethscriptions (authorized)
        vm.prank(Predeploys.ETHSCRIPTIONS);
        collectionsHandler.op_create_collection(collectionId, abi.encode(metadata));

        // Assert deployed matches predicted
        (address actual,,,) = collectionsHandler.collectionState(collectionId);
        assertEq(actual, predicted, "Predicted collection address should match actual deployed proxy");
    }
}
