// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterSigner, EIP712} from "../../../account/paymaster/PaymasterSigner.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract PaymasterSignerECDSAMock is PaymasterSigner, SignerECDSA, Ownable {
    using ERC4337Utils for *;

    constructor(address signerAddr, address withdrawer) EIP712("MyPaymasterECDSASigner", "1") Ownable(withdrawer) {
        _setSigner(signerAddr);
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}
