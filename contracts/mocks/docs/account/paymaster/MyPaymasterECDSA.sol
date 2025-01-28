// contracts/MyPaymasterECDSA.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PaymasterSigner, EIP712} from "../../../../account/paymaster/PaymasterSigner.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {SignerECDSA} from "../../../../utils/cryptography/SignerECDSA.sol";

contract MyPaymasterECDSA is PaymasterSigner, SignerECDSA {
    constructor(address paymasterSignerAddr) EIP712("MyAccountECDSA", "1") {
        _initializeSigner(paymasterSignerAddr);
    }
}
