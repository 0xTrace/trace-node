// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC20NullOwnerCappedUpgradeable.sol";
import "./libraries/Predeploys.sol";

/// @title FixedFungibleERC20
/// @notice ERC-20 clone whose balances are controlled by the FixedFungible protocol handler
/// @dev User-initiated transfers/approvals are disabled; only the handler can mutate balances.
contract FixedFungibleERC20 is ERC20NullOwnerCappedUpgradeable {

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @notice The FixedFungible protocol handler that controls this token
    address public constant protocolHandler = Predeploys.FIXED_FUNGIBLE_HANDLER;

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @notice The ethscription ID that deployed this token
    bytes32 public deployEthscriptionId;

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyProtocolHandler();
    error TransfersOnlyViaEthscriptions();
    error ApprovalsNotAllowed();

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyProtocolHandler() {
        if (msg.sender != protocolHandler) revert OnlyProtocolHandler();
        _;
    }

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

    /// @notice Initialize the ERC20 token
    /// @param name_ The token name
    /// @param symbol_ The token symbol
    /// @param cap_ The maximum supply cap (in 18 decimals)
    /// @param deployEthscriptionId_ The ethscription ID that deployed this token
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 cap_,
        bytes32 deployEthscriptionId_
    ) external initializer {
        __ERC20_init(name_, symbol_);
        __ERC20Capped_init(cap_);
        deployEthscriptionId = deployEthscriptionId_;
    }

    /// @notice Mint tokens (protocol handler only)
    /// @dev Allows minting to address(0) for null ownership
    /// @param to The recipient address (can be address(0))
    /// @param amount The amount to mint (in 18 decimals)
    function mint(address to, uint256 amount) external onlyProtocolHandler {
        _mint(to, amount);
    }

    /// @notice Force transfer tokens (protocol handler only)
    /// @dev Allows transfers to/from address(0) for null ownership
    /// @param from The sender address (can be address(0))
    /// @param to The recipient address (can be address(0))
    /// @param amount The amount to transfer (in 18 decimals)
    function forceTransfer(address from, address to, uint256 amount) external onlyProtocolHandler {
        _update(from, to, amount);
    }

    // =============================================================
    //                DISABLED ERC20 FUNCTIONS
    // =============================================================

    /// @notice User-initiated transfers are disabled
    /// @dev All transfers must go through the Ethscriptions NFT
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice User-initiated transfers are disabled
    /// @dev All transfers must go through the Ethscriptions NFT
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    /// @notice Approvals are disabled
    /// @dev All transfers are controlled by the FixedFungibleProtocolHandler
    function approve(address, uint256) public pure override returns (bool) {
        revert ApprovalsNotAllowed();
    }
}
