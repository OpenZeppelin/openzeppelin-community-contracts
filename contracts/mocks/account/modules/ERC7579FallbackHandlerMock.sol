// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ERC7579ModuleMock} from "./ERC7579ModuleMock.sol";
import {MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579FallbackHandlerMock is ERC2771Context, ERC7579ModuleMock(MODULE_TYPE_FALLBACK) {
    event ERC7579FallbackHandlerMockCalled(address sender, uint256 value, bytes data);

    error ERC7579FallbackHandlerMockRevert();

    function callRevert() public pure {
        revert ERC7579FallbackHandlerMockRevert();
    }

    function _fallback() internal {
        emit ERC7579FallbackHandlerMockCalled(_msgSender(), msg.value, _msgData());
    }

    fallback() external payable {
        _fallback();
    }

    receive() external payable {
        _fallback();
    }
}
