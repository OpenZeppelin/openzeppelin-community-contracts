// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ERC7579ModuleMock} from "./ERC7579ModuleMock.sol";
import {MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579FallbackHandlerMock is ERC2771Context(address(0)), ERC7579ModuleMock(MODULE_TYPE_FALLBACK) {
    event ERC7579FallbackHandlerMockCalled(address sender, uint256 value, bytes data);

    error ERC7579FallbackHandlerMockRevert();

    // all calls made to a FallbackHandler should use ERC-2771 (caller is assumed to be an ERC-7579 account)
    function isTrustedForwarder(address) public view virtual override returns (bool) {
        return true;
    }

    function callPayable() public payable {
        emit ERC7579FallbackHandlerMockCalled(_msgSender(), msg.value, _msgData());
    }

    function callView() public view returns (address) {
        return _msgSender();
    }

    function callRevert() public pure {
        revert ERC7579FallbackHandlerMockRevert();
    }
}
