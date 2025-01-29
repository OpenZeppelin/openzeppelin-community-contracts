// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {SignerP256} from "../../utils/cryptography/SignerP256.sol";

abstract contract AccountP256Mock is Account, SignerP256, ERC7821 {
    constructor(bytes32 qx, bytes32 qy) {
        _setSigner(qx, qy);
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
