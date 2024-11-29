// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

/**
 * @dev Base implementation of a cross-chain gateway adapter for the Axelar Network.
 *
 * This contract allows developers to register equivalence between chains (i.e. CAIP-2 chain identifiers
 * to Axelar chain identifiers) and remote gateways (i.e. gateways on other chains) to
 * facilitate cross-chain communication.
 */
abstract contract AxelarGatewayBase is Ownable {
    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(string caip2, string gatewayAddress);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(string caip2, string destinationChain);

    /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedChain(string caip2);

    error ChainEquivalenceAlreadyRegistered(string caip2);
    error RemoteGatewayAlreadyRegistered(string caip2);

    /// @dev Axelar's official gateway for the current chain.
    IAxelarGateway public immutable localGateway;

    mapping(string caip2 => string remoteGateway) private _remoteGateways;
    mapping(string caip2OrAxelar => string axelarOrCaip2) private _chainEquivalence;

    /// @dev Sets the local gateway address (i.e. Axelar's official gateway for the current chain).
    constructor(IAxelarGateway _gateway) {
        localGateway = _gateway;
    }

    /// @dev Returns the equivalent chain given an id that can be either CAIP-2 or an Axelar network identifier.
    function getEquivalentChain(string memory input) public view virtual returns (string memory output) {
        output = _chainEquivalence[input];
        require(bytes(output).length > 0, UnsupportedChain(input));
    }

    /// @dev Returns the address string of the remote gateway for a given CAIP-2 chain identifier.
    function getRemoteGateway(string memory caip2) public view virtual returns (string memory remoteGateway) {
        remoteGateway = _remoteGateways[caip2];
        require(bytes(remoteGateway).length > 0, UnsupportedChain(caip2));
    }

    /// @dev Registers a chain equivalence between a CAIP-2 chain identifier and an Axelar network identifier.
    function registerChainEquivalence(string calldata caip2, string calldata axelarSupported) public virtual onlyOwner {
        require(bytes(_chainEquivalence[caip2]).length == 0, ChainEquivalenceAlreadyRegistered(caip2));
        _chainEquivalence[caip2] = axelarSupported;
        _chainEquivalence[axelarSupported] = caip2;
        emit RegisteredChainEquivalence(caip2, axelarSupported);
    }

    /// @dev Registers the address string of the remote gateway for a given CAIP-2 chain identifier.
    function registerRemoteGateway(string calldata caip2, string calldata remoteGateway) public virtual onlyOwner {
        require(bytes(_remoteGateways[caip2]).length == 0, RemoteGatewayAlreadyRegistered(caip2));
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}
