// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IProtocolHandler
/// @notice Interface that all protocol handlers must implement
/// @dev Handlers process protocol-specific logic for Ethscriptions lifecycle events
interface IProtocolHandler {
    /// @notice Called when an Ethscription with this protocol is transferred
    /// @param ethscriptionId The Ethscription ID (L1 tx hash)
    /// @param from The address transferring the Ethscription
    /// @param to The address receiving the Ethscription
    function onTransfer(
        bytes32 ethscriptionId,
        address from,
        address to
    ) external;

    /// @notice Returns human-readable protocol name
    /// @return The protocol name (e.g., "erc-20", "collections")
    function protocolName() external pure returns (string memory);
}
