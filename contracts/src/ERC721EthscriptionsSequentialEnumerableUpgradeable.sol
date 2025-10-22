// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC721EthscriptionsUpgradeable.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Enumerable mixin for Ethscriptions-style collections where token IDs are
 * sequential, start at zero, and tokens are never burned.
 */
abstract contract ERC721EthscriptionsSequentialEnumerableUpgradeable is ERC721EthscriptionsUpgradeable, IERC721Enumerable {
    /// @dev Raised when a mint attempts to skip or reuse a token ID.
    error ERC721SequentialEnumerableInvalidTokenId(uint256 expected, uint256 actual);
    /// @dev Raised if a contract attempts to remove a token from supply.
    error ERC721SequentialEnumerableTokenRemoval(uint256 tokenId);

    /// @custom:storage-location erc7201:ethscriptions.storage.ERC721SequentialEnumerable
    struct ERC721SequentialEnumerableStorage {
        uint256 _mintCount;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC721SequentialEnumerableStorageLocation")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC721SequentialEnumerableStorageLocation = 0x154e8d00bf5f00755eebdfa0d432d05cad242742a46a00bbdb15798f33342700;

    function _getERC721SequentialEnumerableStorage()
        private
        pure
        returns (ERC721SequentialEnumerableStorage storage $)
    {
        assembly {
            $.slot := ERC721SequentialEnumerableStorageLocation
        }
    }

    /// @inheritdoc ERC165Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721EthscriptionsUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC721Enumerable
    function tokenOfOwnerByIndex(address owner, uint256 index)
        public
        view
        virtual
        override(IERC721Enumerable, ERC721EthscriptionsUpgradeable)
        returns (uint256)
    {
        return super.tokenOfOwnerByIndex(owner, index);
    }

    /// @inheritdoc IERC721Enumerable
    function totalSupply() public view virtual override returns (uint256) {
        ERC721SequentialEnumerableStorage storage $ = _getERC721SequentialEnumerableStorage();
        return $._mintCount;
    }

    /// @inheritdoc IERC721Enumerable
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        if (index >= totalSupply()) {
            revert ERC721OutOfBoundsIndex(address(0), index);
        }
        return index;
    }

    function _afterTokenMint(uint256 tokenId) internal virtual override {
        ERC721SequentialEnumerableStorage storage $ = _getERC721SequentialEnumerableStorage();

        uint256 expectedId = $._mintCount;
        if (tokenId != expectedId) {
            revert ERC721SequentialEnumerableInvalidTokenId(expectedId, tokenId);
        }

        unchecked {
            $._mintCount = expectedId + 1;
        }
    }

    function _beforeTokenRemoval(uint256 tokenId, address) internal virtual override {
        revert ERC721SequentialEnumerableTokenRemoval(tokenId);
    }
}
