// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579ModuleMockUpgradeable} from "./ERC7579ModuleMockUpgradeable.sol";
import {MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC7579FallbackHandlerMockUpgradeable is Initializable, ERC7579ModuleMockUpgradeable {
    event ERC7579FallbackHandlerMockCalled(address account, address sender, uint256 value, bytes data);

    error ERC7579FallbackHandlerMockRevert();

    function __ERC7579FallbackHandlerMock_init() internal onlyInitializing {
        __ERC7579ModuleMock_init_unchained(MODULE_TYPE_FALLBACK);
    }

    function __ERC7579FallbackHandlerMock_init_unchained() internal onlyInitializing {
    }
    function _msgAccount() internal view returns (address) {
        return msg.sender;
    }

    function _msgSender() internal pure returns (address) {
        return address(bytes20(msg.data[msg.data.length - 20:]));
    }

    function _msgData() internal pure returns (bytes calldata) {
        return msg.data[:msg.data.length - 20];
    }

    function callPayable() public payable {
        emit ERC7579FallbackHandlerMockCalled(_msgAccount(), _msgSender(), msg.value, _msgData());
    }

    function callView() public view returns (address, address) {
        return (_msgAccount(), _msgSender());
    }

    function callRevert() public pure {
        revert ERC7579FallbackHandlerMockRevert();
    }
}
