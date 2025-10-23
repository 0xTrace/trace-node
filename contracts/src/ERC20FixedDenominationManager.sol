// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/Create2.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./ERC20FixedDenomination.sol";
import "./libraries/Proxy.sol";
import "./Ethscriptions.sol";
import "./libraries/Predeploys.sol";
import "./interfaces/IProtocolHandler.sol";

/// @title ERC20FixedDenominationManager
/// @notice Manages ERC-20 tokens that move in a fixed denomination per mint/transfer lot.
/// @dev Deploys and controls ERC20FixedDenomination proxies; callable only by the Ethscriptions contract.
contract ERC20FixedDenominationManager is IProtocolHandler {
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
        uint256 amount;                // How many tokens this ethscription represents
    }

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

    /// @dev Implementation contract used for proxy deployments
    address public constant tokenImplementation = Predeploys.ERC20_FIXED_DENOMINATION_IMPLEMENTATION;
    address public constant ethscriptions = Predeploys.ETHSCRIPTIONS;

    string public constant protocolName = "erc-20-fixed-denomination";

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    mapping(bytes32 => TokenInfo) internal tokensByTick;
    mapping(bytes32 => bytes32) public deployToTick;
    mapping(bytes32 => TokenItem) internal tokenItems;

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

    event ERC20FixedDenominationTokenDeployed(
        bytes32 indexed deployEthscriptionId,
        address indexed tokenAddress,
        string tick,
        uint256 maxSupply,
        uint256 mintAmount
    );

    event ERC20FixedDenominationTokenMinted(
        bytes32 indexed deployEthscriptionId,
        address indexed to,
        uint256 amount,
        bytes32 ethscriptionId
    );

    event ERC20FixedDenominationTokenTransferred(
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

    /// @notice Handles a deploy inscription for a fixed-denomination ERC-20.
    /// @param ethscriptionId The deploy inscription hash (also used as CREATE2 salt).
    /// @param data ABI-encoded DeployOperation parameters (tick, maxSupply, mintAmount).
    function op_deploy(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        DeployOperation memory deployOp = abi.decode(data, (DeployOperation));

        bytes32 tickKey = _getTickKey(deployOp.tick);
        TokenInfo storage token = tokensByTick[tickKey];

        if (token.deployEthscriptionId != bytes32(0)) revert TokenAlreadyDeployed();
        if (deployOp.maxSupply == 0) revert InvalidMaxSupply();
        if (deployOp.mintAmount == 0) revert InvalidMintAmount();
        if (deployOp.maxSupply % deployOp.mintAmount != 0) revert MaxSupplyNotDivisibleByMintAmount();

        Proxy tokenProxy = new Proxy{salt: tickKey}(address(this));

        string memory name = deployOp.tick;
        string memory symbol = deployOp.tick.upper();

        bytes memory initCalldata = abi.encodeWithSelector(
            ERC20FixedDenomination.initialize.selector,
            name,
            symbol,
            deployOp.maxSupply * 10**18,
            ethscriptionId
        );

        tokenProxy.upgradeToAndCall(tokenImplementation, initCalldata);
        tokenProxy.changeAdmin(Predeploys.PROXY_ADMIN);

        tokensByTick[tickKey] = TokenInfo({
            tokenContract: address(tokenProxy),
            deployEthscriptionId: ethscriptionId,
            tick: deployOp.tick,
            maxSupply: deployOp.maxSupply,
            mintAmount: deployOp.mintAmount,
            totalMinted: 0
        });

        deployToTick[ethscriptionId] = tickKey;

        emit ERC20FixedDenominationTokenDeployed(
            ethscriptionId,
            address(tokenProxy),
            deployOp.tick,
            deployOp.maxSupply,
            deployOp.mintAmount
        );
    }

    /// @notice Processes a mint inscription and mints the fixed denomination to the inscription owner.
    /// @param ethscriptionId The mint inscription hash.
    /// @param data ABI-encoded MintOperation parameters (tick, id, amount).
    function op_mint(bytes32 ethscriptionId, bytes calldata data) external virtual onlyEthscriptions {
        MintOperation memory mintOp = abi.decode(data, (MintOperation));

        bytes32 tickKey = _getTickKey(mintOp.tick);
        TokenInfo storage token = tokensByTick[tickKey];

        if (token.deployEthscriptionId == bytes32(0)) revert TokenNotDeployed();
        if (mintOp.amount != token.mintAmount) revert MintAmountMismatch();

        uint256 maxId = token.maxSupply / token.mintAmount;
        if (mintOp.id < 1 || mintOp.id > maxId) revert InvalidMintId();

        Ethscriptions ethscriptionsContract = Ethscriptions(ethscriptions);
        Ethscriptions.Ethscription memory ethscription = ethscriptionsContract.getEthscription(ethscriptionId);
        address initialOwner = ethscription.initialOwner;

        tokenItems[ethscriptionId] = TokenItem({
            deployEthscriptionId: token.deployEthscriptionId,
            amount: mintOp.amount
        });

        ERC20FixedDenomination(token.tokenContract).mint(initialOwner, mintOp.amount * 10**18);
        token.totalMinted += mintOp.amount;

        emit ERC20FixedDenominationTokenMinted(token.deployEthscriptionId, initialOwner, mintOp.amount, ethscriptionId);
    }

    /// @notice Mirrors ERC-20 balances when a mint inscription NFT transfers.
    /// @param ethscriptionId The mint inscription hash being transferred.
    /// @param from The previous owner of the inscription NFT.
    /// @param to The new owner of the inscription NFT.
    function onTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) external virtual override onlyEthscriptions {
        TokenItem memory item = tokenItems[ethscriptionId];

        if (item.deployEthscriptionId == bytes32(0)) return;

        bytes32 tickKey = deployToTick[item.deployEthscriptionId];
        TokenInfo storage token = tokensByTick[tickKey];

        ERC20FixedDenomination(token.tokenContract).forceTransfer(from, to, item.amount * 10**18);

        emit ERC20FixedDenominationTokenTransferred(item.deployEthscriptionId, from, to, item.amount, ethscriptionId);
    }

    // =============================================================
    //                  EXTERNAL VIEW FUNCTIONS
    // =============================================================

    function getTokenAddress(bytes32 deployEthscriptionId) external view returns (address) {
        bytes32 tickKey = deployToTick[deployEthscriptionId];
        return tokensByTick[tickKey].tokenContract;
    }

    function getTokenAddressByTick(string memory tick) external view returns (address) {
        bytes32 tickKey = _getTickKey(tick);
        return tokensByTick[tickKey].tokenContract;
    }

    function getTokenInfo(bytes32 deployEthscriptionId) external view returns (TokenInfo memory) {
        bytes32 tickKey = deployToTick[deployEthscriptionId];
        return tokensByTick[tickKey];
    }

    function getTokenInfoByTick(string memory tick) external view returns (TokenInfo memory) {
        bytes32 tickKey = _getTickKey(tick);
        return tokensByTick[tickKey];
    }

    function predictTokenAddressByTick(string memory tick) external view returns (address) {
        bytes32 tickKey = _getTickKey(tick);

        if (tokensByTick[tickKey].tokenContract != address(0)) {
            return tokensByTick[tickKey].tokenContract;
        }

        bytes memory creationCode = abi.encodePacked(type(Proxy).creationCode, abi.encode(address(this)));
        return Create2.computeAddress(tickKey, keccak256(creationCode), address(this));
    }

    function isTokenItem(bytes32 ethscriptionId) external view returns (bool) {
        return tokenItems[ethscriptionId].deployEthscriptionId != bytes32(0);
    }

    function getTokenItem(bytes32 ethscriptionId) external view returns (TokenItem memory) {
        return tokenItems[ethscriptionId];
    }

    // =============================================================
    //                    PRIVATE FUNCTIONS
    // =============================================================

    function _getTickKey(string memory tick) private pure returns (bytes32) {
        return keccak256(abi.encode(protocolName, tick));
    }
}
