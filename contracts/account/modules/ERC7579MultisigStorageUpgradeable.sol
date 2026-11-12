// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7579MultisigUpgradeable} from "./ERC7579MultisigUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC7579Multisig} that allows storing presigned approvals in storage.
 *
 * This module extends the multisignature module to allow signers to presign operations,
 * which are then stored in a mapping and can be used during validation. This enables
 * more flexible multisignature workflows where signatures can be collected over time
 * without requiring all signers to be online simultaneously.
 *
 * When validating signatures, if a signature is empty, it indicates a presignature
 * and the validation will check the storage mapping instead of cryptographic verification.
 */
abstract contract ERC7579MultisigStorageUpgradeable is Initializable, ERC7579MultisigUpgradeable {
    using SignatureChecker for bytes;

    /// @dev Emitted when a signer signs a hash
    event ERC7579MultisigStoragePresigned(address indexed account, bytes32 indexed hash, bytes signer);

    /// @custom:storage-location erc7201:openzeppelin.storage.ERC7579MultisigStorage
    struct ERC7579MultisigStorageStorage {
        mapping(address account => mapping(bytes signer => mapping(bytes32 hash => bool))) _presigned;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC7579MultisigStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC7579MultisigStorageStorageLocation = 0xbb61fef847b8b1617e09c10fd145ae309a5df23f969de70a2d2ea17d210d5200;

    function _getERC7579MultisigStorageStorage() private pure returns (ERC7579MultisigStorageStorage storage $) {
        assembly {
            $.slot := ERC7579MultisigStorageStorageLocation
        }
    }

    function __ERC7579MultisigStorage_init() internal onlyInitializing {
    }

    function __ERC7579MultisigStorage_init_unchained() internal onlyInitializing {
    }
    /// @dev Returns whether a signer has presigned a specific hash for the account
    function presigned(address account, bytes memory signer, bytes32 hash) public view virtual returns (bool) {
        ERC7579MultisigStorageStorage storage $ = _getERC7579MultisigStorageStorage();
        return $._presigned[account][signer][hash];
    }

    /**
     * @dev Allows a signer to presign a hash by providing a valid signature.
     * The signature will be verified and if valid, the presignature will be stored.
     *
     * Emits {ERC7579MultisigStoragePresigned} if the signature is valid and the hash is not already
     * signed, otherwise acts as a no-op.
     *
     * NOTE: Does not check if the signer is authorized for the account. Valid signatures from
     * invalid signers won't be executable. See {_validateSignatures} for more details.
     */
    function presign(address account, bytes calldata signer, bytes32 hash, bytes calldata signature) public virtual {
        ERC7579MultisigStorageStorage storage $ = _getERC7579MultisigStorageStorage();
        if (!presigned(account, signer, hash) && signer.isValidSignatureNow(hash, signature)) {
            $._presigned[account][signer][hash] = true;
            emit ERC7579MultisigStoragePresigned(account, hash, signer);
        }
    }

    /**
     * @dev See {ERC7579Multisig-_validateSignatures}.
     *
     * If a signature is empty, it indicates a presignature and the validation will check the storage mapping
     * instead of cryptographic verification. See {sign} for more details.
     */
    function _validateSignatures(
        address account,
        bytes32 hash,
        bytes[] memory signingSigners,
        bytes[] memory signatures
    ) internal view virtual override returns (bool valid) {
        uint256 signersLength = signingSigners.length;

        // Check validity of presigned signatures
        uint256 presignedCount = 0;
        for (uint256 i = 0; i < signersLength; i++) {
            if (signatures[i].length == 0) {
                // Presigned signature
                if (!isSigner(account, signingSigners[i]) || !presigned(account, signingSigners[i], hash)) {
                    return false;
                }
                presignedCount++;
            }
        }

        // Filter out presigned signatures
        uint256 regular = signersLength - presignedCount;
        bytes[] memory _signingSigners = new bytes[](regular);
        bytes[] memory _signatures = new bytes[](regular);

        uint256 regularIndex = 0;
        for (uint256 i = 0; i < signersLength; i++) {
            if (signatures[i].length != 0) {
                _signingSigners[regularIndex] = signingSigners[i];
                _signatures[regularIndex] = signatures[i];
                regularIndex++;
            }
        }

        return super._validateSignatures(account, hash, _signingSigners, _signatures);
    }
}
