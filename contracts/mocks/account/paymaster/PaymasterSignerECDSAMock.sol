// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterSigner, EIP712} from "../../../account/paymaster/PaymasterSigner.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract PaymasterSignerECDSAMock is PaymasterSigner, SignerECDSA {
    using ERC4337Utils for *;

    constructor(address signerAddr) EIP712("MyPaymasterECDSASigner", "1") {
        _setSigner(signerAddr);
    }

    // WARNING: No access control
    function deposit() external payable {
        _deposit(msg.value);
    }

    // WARNING: No access control
    function addStake(uint256 value, uint32 unstakeDelaySec) external payable {
        _addStake(value, unstakeDelaySec);
    }
}
