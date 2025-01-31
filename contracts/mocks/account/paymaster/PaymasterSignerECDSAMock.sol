// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PaymasterSigner, EIP712} from "../../../account/paymaster/PaymasterSigner.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract PaymasterSignerECDSAMock is PaymasterSigner, SignerECDSA, Ownable {
    constructor(address signerAddr, address withdrawer) EIP712("MyPaymasterECDSASigner", "1") Ownable(withdrawer) {
        _setSigner(signerAddr);
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}
