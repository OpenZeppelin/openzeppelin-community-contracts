// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ICAIP2Equivalence} from "../ICAIP2Equivalence.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";

abstract contract GatewayAxelarCAIP2 is ICAIP2Equivalence {
    error AlreadyRegisteredChain(CAIP2.ChainId chain);
    error UnsupportedChain(CAIP2.ChainId chain);

    mapping(CAIP2.Chain chain => AxelarChain chainName) public chainDetails;

    struct AxelarChain {
        string destinationChain;
        string contractAddress;
    }

    function isRegisteredCAIP2(CAIP2.ChainId memory chain) public view override returns (bool) {
        return bytes(chainDetails[chain].destinationChain).length != 0;
    }

    function fromCAIP2(CAIP2.ChainId memory chain) public pure returns (bytes memory) {
        return abi.encode(AxelarChain(chain.destinationChain, chain.contractAddress));
    }

    function registerCAIP2Equivalence(CAIP2.ChainId memory chain, bytes memory custom) public onlyOwner {
        if (isRegisteredCAIP2(chain)) {
            revert AlreadyRegisteredChain(chain);
        }
        chainDetails[chain] = abi.decode(custom, (AxelarChain));
    }
}
