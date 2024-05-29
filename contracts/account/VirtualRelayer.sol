// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Errors} from "./Errors.sol";

/// @dev Virtual Relayer
///
/// An arbitrary forwarder contract to relay the execution of transactions.
/// Each virtual relayer is accompanied by a private key whose address can sign off-chain operations
/// and is setup at construction.
///
/// Under normal operation, this virtual relayer will sign offchain EIP-712 messages
contract VirtualRelayer is Nonces, ERC1155Holder, ERC721Holder, EIP712 {
    using ECDSA for bytes32;

    address private _signer;

    struct RelayOperationData {
        address to;
        uint256 value;
        uint256 gas;
        uint48 deadline;
        bytes data;
        bytes signature;
    }

    bytes32 internal constant _RELAY_OPERATION_TYPEHASH =
        keccak256("RelayOperation(address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)");

    event RelayOperation(address indexed executor, uint256 nonce, bool success);

    error VirtualRelayerInvalidSigner(address recovered);

    error VirtualRelayerMismatchedValue(uint256 requestedValue, uint256 msgValue);

    error VirtualRelayerExpiredRequest(uint48 deadline);

    constructor(string memory name, address signer_) EIP712(name, "1") {
        _signer = signer_;
    }

    /// @dev Returns the associated signer that can sign operations on behalf of this relayer.
    function signer() public view returns (address) {
        return _signer;
    }

    /// @dev Returns `true` if a request is valid for a provided `signature` at the current block timestamp.
    ///
    /// A transaction is considered valid when the target trusts this forwarder, the request hasn't expired
    /// (deadline is not met), and the signer matches the `from` parameter of the signed request.
    ///
    /// NOTE: A request may return false here but it won't cause {executeBatch} to revert if a refund
    /// receiver is provided.
    function verify(RelayOperationData calldata request) public view virtual returns (bool) {
        (bool active, bool signerMatch, ) = _validate(request);
        return active && signerMatch;
    }

    /// @dev Executes a `request` call authorized by the relayer signer associated to this virtual relayer. The gas
    /// provided to the requested call may not be exactly the amount requested, but the call will not run
    /// out of gas. Will revert if the request is invalid or the call reverts, in this case the nonce is not consumed.
    ///
    /// Requirements:
    ///
    /// - The request value should be equal to the provided `msg.value`.
    /// - The request should be valid according to {verify}.
    function execute(RelayOperationData calldata request) public payable virtual {
        // We make sure that msg.value and request.value match exactly.
        // If the request is invalid or the call reverts, this whole function
        // will revert, ensuring value isn't stuck.
        if (msg.value != request.value) {
            revert VirtualRelayerMismatchedValue(request.value, msg.value);
        }

        if (!_execute(request, true)) {
            revert Errors.FailedCall();
        }
    }

    /// @dev Batch version of {execute} with optional refunding and atomic execution.
    ///
    /// In case a batch contains at least one invalid request (see {verify}), the
    /// request will be skipped and the `refundReceiver` parameter will receive back the
    /// unused requested value at the end of the execution. This is done to prevent reverting
    /// the entire batch when a request is invalid or has already been submitted.
    ///
    /// If the `refundReceiver` is the `address(0)`, this function will revert when at least
    /// one of the requests was not valid instead of skipping it. This could be useful if
    /// a batch is required to get executed atomically (at least at the top-level). For example,
    /// refunding (and thus atomicity) can be opt-out if the relayer is using a service that avoids
    /// including reverted transactions.
    ///
    /// Requirements:
    ///
    /// - The sum of the requests' values should be equal to the provided `msg.value`.
    /// - All of the requests should be valid (see {verify}) when `refundReceiver` is the zero address.
    ///
    /// NOTE: Setting a zero `refundReceiver` guarantees an all-or-nothing requests execution only for
    /// the first-level forwarded calls. In case a forwarded request calls to a contract with another
    /// subcall, the second-level call may revert without the top-level call reverting.
    function executeBatch(
        RelayOperationData[] calldata requests,
        address payable refundReceiver
    ) public payable virtual {
        bool atomic = refundReceiver == address(0);

        uint256 requestsValue;
        uint256 refundValue;

        for (uint256 i; i < requests.length; ++i) {
            requestsValue += requests[i].value;
            bool success = _execute(requests[i], atomic);
            if (!success) {
                refundValue += requests[i].value;
            }
        }

        // The batch should revert if there's a mismatched msg.value provided
        // to avoid request value tampering
        if (requestsValue != msg.value) {
            revert VirtualRelayerMismatchedValue(requestsValue, msg.value);
        }

        // Some requests with value were invalid (possibly due to frontrunning).
        // To avoid leaving ETH in the contract this value is refunded.
        if (refundValue != 0) {
            // We know refundReceiver != address(0) && requestsValue == msg.value
            // meaning we can ensure refundValue is not taken from the original contract's balance
            // and refundReceiver is a known account.
            Address.sendValue(refundReceiver, refundValue);
        }
    }

    /// @dev Validates if the provided request can be executed at current block timestamp with
    /// the given `request.signature` on behalf of the signer associated to this virtual relayer.
    function _validate(
        RelayOperationData calldata request
    ) internal view virtual returns (bool active, bool signerMatch, address signerRecovered) {
        (bool isValid, address recovered) = _recoverRelayOperationSigner(request);

        return (request.deadline >= block.timestamp, isValid && recovered == signer(), recovered);
    }

    /// @dev Returns a tuple with the recovered the signer of an EIP712 forward request message hash
    /// and a boolean indicating if the signature is valid.
    ///
    /// NOTE: The signature is considered valid if {ECDSA-tryRecover} indicates no recover error for it.
    function _recoverRelayOperationSigner(
        RelayOperationData calldata request
    ) internal view virtual returns (bool, address) {
        (address recovered, ECDSA.RecoverError err, ) = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _RELAY_OPERATION_TYPEHASH,
                    request.to,
                    request.value,
                    request.gas,
                    nonces(signer()),
                    request.deadline,
                    keccak256(request.data)
                )
            )
        ).tryRecover(request.signature);

        return (err == ECDSA.RecoverError.NoError, recovered);
    }

    /// @dev Validates and executes a signed request returning the request call `success` value.
    ///
    /// Internal function without msg.value validation.
    ///
    /// Requirements:
    ///
    /// - The caller must have provided enough gas to forward with the call.
    /// - The request must be valid (see {verify}) if the `requireValidRequest` is true.
    ///
    /// Emits an {ExecutedForwardRequest} event.
    ///
    /// IMPORTANT: Using this function doesn't check that all the `msg.value` was sent, potentially
    /// leaving value stuck in the contract.
    function _execute(
        RelayOperationData calldata request,
        bool requireValidRequest
    ) internal virtual returns (bool success) {
        (bool active, bool signerMatch, address recovered) = _validate(request);

        // Need to explicitly specify if a revert is required since non-reverting is default for
        // batches and reversion is opt-in since it could be useful in some scenarios
        if (requireValidRequest) {
            if (!active) {
                revert VirtualRelayerExpiredRequest(request.deadline);
            }

            if (!signerMatch) {
                revert VirtualRelayerInvalidSigner(recovered);
            }
        }

        // Ignore an invalid request because requireValidRequest = false
        if (signerMatch && active) {
            // Nonce should be used before the call to prevent reusing by reentrancy
            uint256 currentNonce = _useNonce(signer());

            uint256 reqGas = request.gas;
            address to = request.to;
            uint256 value = request.value;

            uint256 gasLeft;

            bytes memory data = request.data;

            assembly {
                success := call(reqGas, to, value, add(data, 0x20), mload(data), 0, 0)
                gasLeft := gas()
            }

            _checkForwardedGas(gasLeft, request);

            emit RelayOperation(msg.sender, currentNonce, success);
        }
    }

    /// @dev Same logic as https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.2/contracts/metatx/ERC2771Forwarder.sol#L338
    function _checkForwardedGas(uint256 gasLeft, RelayOperationData calldata request) private pure {
        if (gasLeft < request.gas / 63) {
            assembly ("memory-safe") {
                invalid()
            }
        }
    }

    /// @dev Fallback function to receive ETH.
    receive() external payable {}
}
