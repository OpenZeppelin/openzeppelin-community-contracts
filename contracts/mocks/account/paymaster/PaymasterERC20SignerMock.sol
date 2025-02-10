// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {PaymasterERC20, IERC20} from "../../../account/paymaster/PaymasterERC20.sol";

/**
 * NOTE: struct or the expected paymaster data is:
 * * [0x00:0x14                      ] token                 (IERC20)
 * * [0x14:0x1a                      ] validAfter            (uint48)
 * * [0x1a:0x20                      ] validUntil            (uint48)
 * * [0x20:0x40                      ] tokenPrice            (uint256)
 * * [0x40:0x54                      ] oracle                (address)
 * * [0x54:0x68                      ] guarantor             (address) (optional: 0 if no guarantor)
 * * [0x68:0x6a                      ] oracleSignatureLength (uint16)
 * * [0x6a:0x6a+oracleSignatureLength] oracleSignature       (bytes)
 * * [0x6a+oracleSignatureLength:    ] guarantorSignature    (bytes)
 */
abstract contract PaymasterERC20SignerMock is EIP712, PaymasterERC20, AccessControl {
    using ERC4337Utils for PackedUserOperation;

    bytes32 private constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 private constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    bytes32 private constant TOKEN_PRICE_TYPEHASH =
        keccak256("TokenPrice(address token,uint48 validAfter,uint48 validUntil,uint256 tokenPrice)");
    bytes32 private constant PACKED_USER_OPERATION_TYPEHASH =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
        );

    function _authorizeWithdraw() internal override onlyRole(WITHDRAWER_ROLE) {}

    function _fetchDetails(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */
    )
        internal
        view
        virtual
        override
        returns (IERC20 token, uint48 validAfter, uint48 validUntil, uint256 tokenPrice, address guarantor)
    {
        (token, validAfter, validUntil, tokenPrice) = _fetchOracleDetails(userOp);
        guarantor = _fetchGuarantorDetails(userOp);
    }

    function _fetchOracleDetails(
        PackedUserOperation calldata userOp
    ) private view returns (IERC20 token, uint48 validAfter, uint48 validUntil, uint256 tokenPrice) {
        bytes calldata paymasterData = userOp.paymasterData();

        // parse repayment details
        token = IERC20(address(bytes20(paymasterData[0x00:0x14])));
        validAfter = uint48(bytes6(paymasterData[0x14:0x1a]));
        validUntil = uint48(bytes6(paymasterData[0x1a:0x20]));
        tokenPrice = uint256(bytes32(paymasterData[0x20:0x40]));

        // parse oracle and oracle signature
        address oracle = address(bytes20(paymasterData[0x40:0x54]));
        uint16 oracleSignatureLength = uint16(bytes2(paymasterData[0x68:0x6a]));
        bytes calldata oracleSignature = paymasterData[0x6c:0x6c + oracleSignatureLength];

        // check oracle is registered
        _checkRole(ORACLE_ROLE, oracle);

        // check oracle signature is valid
        require(
            SignatureChecker.isValidSignatureNow(
                oracle,
                _hashTypedDataV4(
                    keccak256(abi.encode(TOKEN_PRICE_TYPEHASH, token, validAfter, validUntil, tokenPrice))
                ),
                oracleSignature
            )
        );
    }

    function _fetchGuarantorDetails(PackedUserOperation calldata userOp) private view returns (address guarantor) {
        bytes calldata paymasterData = userOp.paymasterData();

        // parse guarantor details
        guarantor = address(bytes20(paymasterData[0x54:0x68]));

        if (guarantor != address(0)) {
            // parse guarantor signature
            uint16 oracleSignatureLength = uint16(bytes2(paymasterData[0x68:0x6a]));
            bytes calldata guarantorSignature = paymasterData[0x6c + oracleSignatureLength:];

            // check guarantor signature is valid
            require(
                SignatureChecker.isValidSignatureNow(
                    guarantor,
                    _hashTypedDataV4(_getStructHashWithoutOracleAndGuarantorSignature(userOp)),
                    guarantorSignature
                )
            );
        }
    }

    function _getStructHashWithoutOracleAndGuarantorSignature(
        PackedUserOperation calldata userOp
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    PACKED_USER_OPERATION_TYPEHASH,
                    userOp.sender,
                    userOp.nonce,
                    keccak256(userOp.initCode),
                    keccak256(userOp.callData),
                    userOp.accountGasLimits,
                    userOp.preVerificationGas,
                    userOp.gasFees,
                    keccak256(userOp.paymasterAndData[:0x9c]) // 0x34 (paymasterDataOffset) + 0x68 (token + validAfter + validUntil + tokenPrice + oracle + guarantor)
                )
            );
    }
}
