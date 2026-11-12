// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {ERC7739Upgradeable, EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/signers/draft-ERC7739Upgradeable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SignerZKEmailUpgradeable} from "../../utils/cryptography/signers/SignerZKEmailUpgradeable.sol";
import {IDKIMRegistry} from "@zk-email/contracts/interfaces/IDKIMRegistry.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract AccountZKEmailMockUpgradeable is Initializable, Account, SignerZKEmailUpgradeable, ERC7739Upgradeable, ERC7821, ERC721Holder, ERC1155Holder {
    function __AccountZKEmailMock_init(
        bytes32 accountSalt_,
        IDKIMRegistry registry_,
        IGroth16Verifier groth16Verifier_
    ) internal onlyInitializing {
        __EIP712_init_unchained("AccountZKEmailMock", "1");
        __AccountZKEmailMock_init_unchained(accountSalt_, registry_, groth16Verifier_);
    }

    function __AccountZKEmailMock_init_unchained(
        bytes32 accountSalt_,
        IDKIMRegistry registry_,
        IGroth16Verifier groth16Verifier_
    ) internal onlyInitializing {
        _setAccountSalt(accountSalt_);
        _setDKIMRegistry(registry_);
        _setVerifier(groth16Verifier_);
    }

    /// @inheritdoc ERC7821
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == address(entryPoint()) || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
