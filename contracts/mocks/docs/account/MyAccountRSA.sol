// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "../../../account/Account.sol";
import {ERC7821} from "../../../account/extensions/ERC7821.sol";
import {SignerRSA} from "../../../utils/cryptography/SignerRSA.sol";

contract MyAccountRSA is Initializable, Account, SignerRSA, ERC7821 {
    constructor() EIP712("MyAccountRSA", "1") {}

    function initialize(bytes memory e, bytes memory n) public initializer {
        _setSigner(e, n);
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
