// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGenericGateway {
    // TODO: use uint96 chain id so that Account fit in a single word ?
    struct Account {
        uint256 chain;
        address instance;
    }

    // TODO: (address,uint256)[] tokens?
    // TODO: put value in tokens?
    struct Message {
        Account destination;
        uint256 value;
        bytes data;
    }

    struct Request {
        Account source;
        Message message;
        bytes32 salt;
    }

    // ============================================ relay instrumentation ============================================

    function crossChainSender() external view returns (uint256 chainId, address sender);

    // =============================================== cost estimation ===============================================

    function defaultCost(Message memory message) external view returns (address, uint256);

    /// @dev Returns the (minimum) cost (in a given asset) of performing a cross-chain operation. If asset is not supported for payment, returns type(uint256).max
    function estimateCost(Message memory message, address asset) external view returns (uint256);

    // ================================================= 1 step mode =================================================

    /// @dev Perform a cross-chain call using the canonical payment method for this bridge. The provided value is
    /// passed along the request, minus anything that would be part of the canonical payment method.
    function sendRequest(
        uint256 chain,
        address target,
        uint256 value,
        bytes memory data,
        bytes32 salt
    ) external payable returns (bytes32);

    /// @dev Perform a cross-chain call using the specified payment method. If feeAsset is 0, then feeValue will be
    /// deduced from the provided value to cover costs. The rest of the value is passed along the request.
    function sendRequest(
        uint256 chain,
        address target,
        uint256 value,
        bytes memory data,
        bytes32 salt,
        address feeAsset,
        uint256 feeValue
    ) external payable returns (bytes32);

    // ================================================= 2 step mode =================================================

    /// @dev Register a cross-chain call that will later be forwarded using {forwardRequest}. Any value passed here
    /// will be escrowed. It will then be passed along the request be forwarding happens.
    function createRequest(
        uint256 chain,
        address target,
        bytes memory data,
        bytes32 salt
    ) external payable returns (bytes32);

    /// @dev Forwards a cross-chain request using the canonical payment method for this bridge. Any value provided
    /// here will be used for the payment. It will not be forwarded with the cross-chain call.
    function forwardRequest(Request memory req) external payable;

    /// @dev Forwards a cross-chain request using using the specified payment method. Any value provided here will be
    /// used for the payment. It will not be forwarded with the cross-chain call. This means that value should only be
    /// used with `feeAsset = address(0)` and with `feeValue = msg.value`.
    function forwardRequest(Request memory req, address feeAsset, uint256 feeValue) external payable;
}
