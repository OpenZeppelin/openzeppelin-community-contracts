// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Account} from "../../account/Account.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {SignerERC7913} from "../../utils/cryptography/SignerERC7913.sol";

abstract contract AccountERC7913Mock is Account, SignerERC7913, ERC7821 {
    constructor(bytes memory _signer) {
        _setSigner(_signer);
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
