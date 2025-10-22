// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/ERC721EthscriptionsSequentialEnumerableUpgradeable.sol";
import "../src/ERC721EthscriptionsEnumerableUpgradeable.sol";

contract SequentialEnumerableHarness is ERC721EthscriptionsSequentialEnumerableUpgradeable {
    function initialize() external initializer {
        __ERC721_init("SequentialHarness", "SEQH");
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        _setTokenExists(tokenId, false);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

contract EnumerableHarness is ERC721EthscriptionsEnumerableUpgradeable {
    function initialize() external initializer {
        __ERC721_init("EnumerableHarness", "ENUMH");
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
        _setTokenExists(tokenId, false);
    }

    function forceTransfer(address to, uint256 tokenId) external {
        _update(to, tokenId, address(0));
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}

contract ERC721EthscriptionsMixinsTest is Test {
    SequentialEnumerableHarness internal sequential;
    EnumerableHarness internal enumerable;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        sequential = new SequentialEnumerableHarness();
        sequential.initialize();

        enumerable = new EnumerableHarness();
        enumerable.initialize();
    }

    function testSequentialMintEnforcesOrdering() public {
        sequential.mint(alice, 0);
        sequential.mint(alice, 1);

        assertEq(sequential.totalSupply(), 2);
        assertEq(sequential.tokenByIndex(0), 0);
        assertEq(sequential.tokenByIndex(1), 1);
        assertEq(sequential.tokenOfOwnerByIndex(alice, 0), 0);
        assertEq(sequential.tokenOfOwnerByIndex(alice, 1), 1);
    }

    function testSequentialMintRejectsSkippedIds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC721EthscriptionsSequentialEnumerableUpgradeable
                    .ERC721SequentialEnumerableInvalidTokenId
                    .selector,
                0,
                1
            )
        );
        sequential.mint(alice, 1);
    }

    function testSequentialBurnForbidden() public {
        sequential.mint(alice, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC721EthscriptionsSequentialEnumerableUpgradeable
                    .ERC721SequentialEnumerableTokenRemoval
                    .selector,
                0
            )
        );
        sequential.burn(0);
    }

    function testEnumerableTracksSparseIdsAcrossBurns() public {
        enumerable.mint(alice, 10);
        enumerable.mint(alice, 20);
        enumerable.mint(alice, 30);

        assertEq(enumerable.totalSupply(), 3);
        assertEq(enumerable.tokenByIndex(0), 10);
        assertEq(enumerable.tokenByIndex(1), 20);
        assertEq(enumerable.tokenByIndex(2), 30);

        enumerable.burn(20);
        assertEq(enumerable.totalSupply(), 2);
        assertEq(enumerable.tokenByIndex(0), 10);
        assertEq(enumerable.tokenByIndex(1), 30);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC721EthscriptionsUpgradeable.ERC721OutOfBoundsIndex.selector,
                address(0),
                2
            )
        );
        enumerable.tokenByIndex(2);

        enumerable.mint(alice, 40);
        assertEq(enumerable.totalSupply(), 3);
        assertEq(enumerable.tokenByIndex(2), 40);
    }

    function testEnumerableUpdatesOwnerEnumerationOnTransfer() public {
        enumerable.mint(alice, 1);
        enumerable.mint(alice, 2);

        assertEq(enumerable.balanceOf(alice), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 1), 2);

        enumerable.forceTransfer(bob, 1);

        assertEq(enumerable.balanceOf(alice), 1);
        assertEq(enumerable.balanceOf(bob), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(bob, 0), 1);
    }
}
