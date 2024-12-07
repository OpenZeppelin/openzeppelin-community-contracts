// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AccountP256} from "../../account/draft-AccountP256.sol";

contract AccountP256Mock is AccountP256 {
    constructor(string memory name, string memory version, bytes32 qx, bytes32 qy) EIP712(name, version) {
        _initializeSigner(qx, qy);
    }
}
