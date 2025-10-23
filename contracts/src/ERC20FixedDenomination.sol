// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ERC20NullOwnerCappedUpgradeable.sol";
import "./libraries/Predeploys.sol";

/// @title ERC20FixedDenomination
/// @notice ERC-20 proxy whose supply is managed in a fixed denomination by the manager contract.
/// @dev User-initiated transfers/approvals are disabled; only the manager can mutate balances.
contract ERC20FixedDenomination is ERC20NullOwnerCappedUpgradeable {

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /// @notice The manager contract that controls this token
    address public constant manager = Predeploys.ERC20_FIXED_DENOMINATION_MANAGER;

    // =============================================================
    //                      STATE VARIABLES
    // =============================================================

    /// @notice The ethscription ID that deployed this token
    bytes32 public deployEthscriptionId;

    // =============================================================
    //                      CUSTOM ERRORS
    // =============================================================

    error OnlyManager();
    error TransfersOnlyViaEthscriptions();
    error ApprovalsNotAllowed();

    // =============================================================
    //                         MODIFIERS
    // =============================================================

    modifier onlyManager() {
        if (msg.sender != manager) revert OnlyManager();
        _;
    }

    // =============================================================
    //                    EXTERNAL FUNCTIONS
    // =============================================================

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

    /// @notice Mint tokens (manager only)
    function mint(address to, uint256 amount) external onlyManager {
        _mint(to, amount);
    }

    /// @notice Force transfer tokens (manager only)
    function forceTransfer(address from, address to, uint256 amount) external onlyManager {
        _update(from, to, amount);
    }

    // =============================================================
    //                DISABLED ERC20 FUNCTIONS
    // =============================================================

    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersOnlyViaEthscriptions();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert ApprovalsNotAllowed();
    }
}
