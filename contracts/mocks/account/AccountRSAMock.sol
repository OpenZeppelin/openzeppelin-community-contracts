// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AccountRSA} from "../../account/draft-AccountRSA.sol";

contract AccountRSAMock is AccountRSA {
    constructor(string memory name, string memory version, bytes memory e, bytes memory n) EIP712(name, version) {
        _initializeSigner(e, n);
    }
}
