// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "../../../account/Account.sol";
import {ERC7821} from "../../../account/extensions/ERC7821.sol";
import {SignerP256} from "../../../utils/cryptography/SignerP256.sol";

contract MyAccountP256 is Initializable, Account, SignerP256, ERC7821 {
    constructor() EIP712("MyAccountP256", "1") {}

    function initialize(bytes32 qx, bytes32 qy) public initializer {
        _setSigner(qx, qy);
    }

    /// @dev Allows the entry point as an authorized executor.
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == address(entryPoint()) || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
