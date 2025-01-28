// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Account} from "../../../account/Account.sol";
import {ERC7821} from "../../../account/extensions/ERC7821.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract MyAccountECDSA is Initializable, Account, SignerECDSA, ERC7821 {
    constructor() EIP712("MyAccountECDSA", "1") {}

    function initialize(address signerAddr) public initializer {
        _setSigner(signerAddr);
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
