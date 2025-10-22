// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC721EthscriptionsUpgradeable.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Enumerable mixin for collections that require general token ID tracking and burns.
 */
abstract contract ERC721EthscriptionsEnumerableUpgradeable is ERC721EthscriptionsUpgradeable, IERC721Enumerable {
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
        ERC721EnumerableStorage storage $ = _getERC721EnumerableStorage();
        return $._allTokens.length;
    }

    /// @inheritdoc IERC721Enumerable
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        ERC721EnumerableStorage storage $ = _getERC721EnumerableStorage();
        if (index >= $._allTokens.length) {
            revert ERC721OutOfBoundsIndex(address(0), index);
        }
        return $._allTokens[index];
    }

    function _afterTokenMint(uint256 tokenId) internal virtual override {
        ERC721EnumerableStorage storage $ = _getERC721EnumerableStorage();
        $._allTokensIndex[tokenId] = $._allTokens.length;
        $._allTokens.push(tokenId);
    }

    function _beforeTokenRemoval(uint256 tokenId, address) internal virtual override {
        ERC721EnumerableStorage storage $ = _getERC721EnumerableStorage();
        uint256 tokenIndex = $._allTokensIndex[tokenId];
        uint256 lastTokenIndex = $._allTokens.length - 1;
        uint256 lastTokenId = $._allTokens[lastTokenIndex];

        $._allTokens[tokenIndex] = lastTokenId;
        $._allTokensIndex[lastTokenId] = tokenIndex;

        delete $._allTokensIndex[tokenId];
        $._allTokens.pop();
    }
}
