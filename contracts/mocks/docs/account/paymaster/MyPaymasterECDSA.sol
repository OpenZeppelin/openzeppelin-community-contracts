// contracts/MyPaymasterECDSA.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {SignerPaymaster, EIP712} from "../../../../account/paymaster/SignerPaymaster.sol";
import {SignerECDSA} from "../../../../utils/cryptography/SignerECDSA.sol";

contract MyPaymasterECDSA is SignerPaymaster, SignerECDSA, Ownable {
    constructor(address signer, address withdrawer) EIP712("MyPaymasterECDSA", "1") Ownable(withdrawer) {
        _setSigner(signer);
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}
