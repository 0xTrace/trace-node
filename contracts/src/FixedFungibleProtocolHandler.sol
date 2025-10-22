// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./FixedFungibleERC20.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import "./interfaces/IProtocolHandler.sol";

/// @title FixedFungibleProtocolHandler
/// @notice Implements the fixed-fungible token protocol enforced via Ethscriptions transfers
/// @dev Deploys and controls FixedFungible ERC-20 clones; callable only by the Ethscriptions contract
contract FixedFungibleProtocolHandler is IProtocolHandler {
    using Clones for address;
    using LibString for string;

    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct TokenInfo {
        address tokenContract;
        bytes32 deployEthscriptionId;
        string tick;
        uint256 maxSupply;
        uint256 mintAmount;
        uint256 totalMinted;
    }

    struct TokenItem {
        bytes32 deployEthscriptionId;  // Which token this ethscription belongs to
        uint256 amount;                 // How many tokens this ethscription represents
    }

    // Protocol operation structs for cleaner decoding
    struct DeployOperation {
        string tick;
        uint256 maxSupply;
        uint256 mintAmount;
    }

    struct MintOperation {
        string tick;
        uint256 id;
        uint256 amount;
    }

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @dev Deterministic template contract used for clone deployments
    address public constant fixedFungibleTemplate = Predeploys.FIXED_FUNGIBLE_TEMPLATE_IMPLEMENTATION;
    address public constant ethscriptions = Predeploys.ETHSCRIPTIONS;
    string public constant CANONICAL_PROTOCOL = "fixed-fungible";
    string public constant PRETTY_PROTOCOL = "Fixed-Fungible";

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @dev Track deployed tokens by protocol+tick for find-or-create
    mapping(bytes32 => TokenInfo) internal tokensByTick;  // keccak256(abi.encode(protocol, tick)) => TokenInfo

    /// @dev Map deploy ethscription ID to tick key for lookups
    mapping(bytes32 => bytes32) public deployToTick;    // deployEthscriptionId => tickKey

    /// @dev Track which ethscription is a token item
    mapping(bytes32 => TokenItem) internal tokenItems;    // ethscription tx hash => TokenItem

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyEthscriptions();
    error TokenAlreadyDeployed();
    error TokenNotDeployed();
    error MintAmountMismatch();
    error InvalidMintId();
    error InvalidMaxSupply();
    error InvalidMintAmount();
    error MaxSupplyNotDivisibleByMintAmount();

    // =============================================================
    //                          EVENTS
    // =============================================================

    event FixedFungibleTokenDeployed(
        bytes32 indexed deployEthscriptionId,
        address indexed tokenAddress,
        string tick,
        uint256 maxSupply,
        uint256 mintAmount
    );

    event FixedFungibleTokenMinted(
        bytes32 indexed deployEthscriptionId,
        address indexed to,
        uint256 amount,
        bytes32 ethscriptionId
    );

    event FixedFungibleTokenTransferred(
        bytes32 indexed deployEthscriptionId,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 ethscriptionId
    );

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyEthscriptions() {
        if (msg.sender != ethscriptions) revert OnlyEthscriptions();
        _;
    }

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Handle deploy operation
    /// @param ethscriptionId The ethscription ID
    /// @param data The encoded DeployOperation data
    function op_deploy(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        // Decode the operation data
        DeployOperation memory deployOp = abi.decode(data, (DeployOperation));

        bytes32 tickKey = _getTickKey(deployOp.tick);
        TokenInfo storage token = tokensByTick[tickKey];

        // Revert if token already exists
        if (token.deployEthscriptionId != bytes32(0)) revert TokenAlreadyDeployed();

        // Validate deployment parameters
        if (deployOp.maxSupply == 0) revert InvalidMaxSupply();
        if (deployOp.mintAmount == 0) revert InvalidMintAmount();
        if (deployOp.maxSupply % deployOp.mintAmount != 0) revert MaxSupplyNotDivisibleByMintAmount();

        // Deploy ERC20 clone with CREATE2 using tickKey as salt for deterministic address
        address tokenAddress = fixedFungibleTemplate.cloneDeterministic(tickKey);

        // Initialize the clone
        string memory name = string.concat(PRETTY_PROTOCOL, " ", deployOp.tick);
        string memory symbol = LibString.upper(deployOp.tick);

        // Initialize with max supply in 18 decimals
        // User maxSupply "1000000" means 1000000 * 10^18 smallest units
        FixedFungibleERC20(tokenAddress).initialize(
            name,
            symbol,
            deployOp.maxSupply * 10**18,
            ethscriptionId
        );

        // Store token info
        tokensByTick[tickKey] = TokenInfo({
            tokenContract: tokenAddress,
            deployEthscriptionId: ethscriptionId,
            tick: deployOp.tick,
            maxSupply: deployOp.maxSupply,
            mintAmount: deployOp.mintAmount,
            totalMinted: 0
        });

        // Map deploy ID to tick key for lookups
        deployToTick[ethscriptionId] = tickKey;

        emit FixedFungibleTokenDeployed(
            ethscriptionId,
            tokenAddress,
            deployOp.tick,
            deployOp.maxSupply,
            deployOp.mintAmount
        );
    }

    /// @notice Handle mint operation
    /// @param ethscriptionId The ethscription ID
    /// @param data The encoded MintOperation data
    function op_mint(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        // Decode the operation data
        MintOperation memory mintOp = abi.decode(data, (MintOperation));

        bytes32 tickKey = _getTickKey(mintOp.tick);
        TokenInfo storage token = tokensByTick[tickKey];

        // Token must exist to mint
        if (token.deployEthscriptionId == bytes32(0)) revert TokenNotDeployed();

        // Validate mint amount matches token's configured limit
        if (mintOp.amount != token.mintAmount) revert MintAmountMismatch();

        // Validate mint ID is within valid range (1 to maxId)
        // maxId = maxSupply / mintAmount (both are in user units, not 18 decimals)
        uint256 maxId = token.maxSupply / token.mintAmount;
        if (mintOp.id < 1 || mintOp.id > maxId) revert InvalidMintId();

        // Get the initial owner from the Ethscriptions contract
        Ethscriptions ethscriptionsContract = Ethscriptions(ethscriptions);
        Ethscriptions.Ethscription memory ethscription = ethscriptionsContract.getEthscription(ethscriptionId);
        address initialOwner = ethscription.initialOwner;

        // Track this ethscription as a token item
        tokenItems[ethscriptionId] = TokenItem({
            deployEthscriptionId: token.deployEthscriptionId,
            amount: mintOp.amount
        });

        // Mint tokens to the initial owner - convert to 18 decimals
        FixedFungibleERC20(token.tokenContract).mint(initialOwner, mintOp.amount * 10**18);

        // Update total minted after successful mint
        token.totalMinted += mintOp.amount;

        emit FixedFungibleTokenMinted(token.deployEthscriptionId, initialOwner, mintOp.amount, ethscriptionId);
    }

    /// @notice Handle transfer notification from Ethscriptions contract
    /// @dev Implementation of IProtocolHandler interface
    /// @param ethscriptionId The ethscription ID being transferred
    /// @param from The address transferring from
    /// @param to The address transferring to
    function onTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) external virtual override onlyEthscriptions {
        TokenItem memory item = tokenItems[ethscriptionId];

        // Not a token item, nothing to do
        if (item.deployEthscriptionId == bytes32(0)) return;

        bytes32 tickKey = deployToTick[item.deployEthscriptionId];
        TokenInfo storage token = tokensByTick[tickKey];

        // Force transfer tokens (shadow transfer) - convert to 18 decimals
        FixedFungibleERC20(token.tokenContract).forceTransfer(from, to, item.amount * 10**18);

        emit FixedFungibleTokenTransferred(item.deployEthscriptionId, from, to, item.amount, ethscriptionId);
    }

    // =============================================================
    //                  EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /// @notice Get token contract address by deploy ethscription ID
    /// @param deployEthscriptionId The deployment ethscription ID
    /// @return The token contract address
    function getTokenAddress(bytes32 deployEthscriptionId) external view returns (address) {
        bytes32 tickKey = deployToTick[deployEthscriptionId];
        return tokensByTick[tickKey].tokenContract;
    }

    /// @notice Get token contract address by tick
    /// @param tick The token tick symbol
    /// @return The token contract address
    function getTokenAddressByTick(string memory tick) external view returns (address) {
        bytes32 tickKey = _getTickKey(tick);
        return tokensByTick[tickKey].tokenContract;
    }

    /// @notice Get complete token information by deploy ethscription ID
    /// @param deployEthscriptionId The deployment ethscription ID
    /// @return The TokenInfo struct
    function getTokenInfo(bytes32 deployEthscriptionId) external view returns (TokenInfo memory) {
        bytes32 tickKey = deployToTick[deployEthscriptionId];
        return tokensByTick[tickKey];
    }

    /// @notice Get complete token information by tick
    /// @param tick The token tick symbol
    /// @return The TokenInfo struct
    function getTokenInfoByTick(string memory tick) external view returns (TokenInfo memory) {
        bytes32 tickKey = _getTickKey(tick);
        return tokensByTick[tickKey];
    }

    /// @notice Predict token address for a tick (before deployment)
    /// @param tick The token tick symbol
    /// @return The predicted or actual token address
    function predictTokenAddressByTick(string memory tick) external view returns (address) {
        bytes32 tickKey = _getTickKey(tick);

        // Check if already deployed
        if (tokensByTick[tickKey].tokenContract != address(0)) {
            return tokensByTick[tickKey].tokenContract;
        }

        // Predict using CREATE2
        return Clones.predictDeterministicAddress(fixedFungibleTemplate, tickKey, address(this));
    }

    /// @notice Check if an ethscription is a token item
    /// @param ethscriptionId The ethscription ID
    /// @return True if the ethscription represents tokens
    function isTokenItem(bytes32 ethscriptionId) external view returns (bool) {
        return tokenItems[ethscriptionId].deployEthscriptionId != bytes32(0);
    }

    /// @notice Get token amount for an ethscription
    /// @param ethscriptionId The ethscription ID
    /// @return The amount of tokens this ethscription represents
    function getTokenAmount(bytes32 ethscriptionId) external view returns (uint256) {
        return tokenItems[ethscriptionId].amount;
    }

    /// @notice Get complete token item information
    /// @param ethscriptionId The ethscription ID
    /// @return The TokenItem struct
    function getTokenItem(bytes32 ethscriptionId) external view returns (TokenItem memory) {
        return tokenItems[ethscriptionId];
    }

    // =============================================================
    //                   PUBLIC VIEW FUNCTIONS
    // =============================================================

    /// @notice Returns human-readable protocol name
    /// @return The protocol name
    function protocolName() public pure override returns (string memory) {
        return CANONICAL_PROTOCOL;
    }

    // =============================================================
    //                    PRIVATE FUNCTIONS
    // =============================================================

    /// @notice Generate tick key for storage mapping
    /// @param tick The token tick symbol
    /// @return The tick key for storage lookups
    function _getTickKey(string memory tick) private pure returns (bytes32) {
        // Use the protocol name from this handler
        return keccak256(abi.encode(CANONICAL_PROTOCOL, tick));
    }
}
