// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC7943Fungible} from "@openzeppelin/community-contracts/interfaces/IERC7943.sol";
import {ERC20uRWAMock} from "./ERC20uRWAMock.t.sol";

contract ERC20uRWATest is Test {
    ERC20uRWAMock public token;

    address public holder = makeAddr("holder");
    address public recipient = makeAddr("recipient");
    address public freezer = makeAddr("freezer");
    address public enforcer = makeAddr("enforcer");

    uint256 public constant INITIAL_SUPPLY = 100;

    function setUp() public {
        token = new ERC20uRWAMock("My uRWA Token", "uRWA", freezer, enforcer);
        token.mint(holder, INITIAL_SUPPLY);
    }

    // --- canTransfer: balance check removed ---

    function test_canTransfer_trueWhenAmountExceedsAvailableBalance() public view {
        uint256 amount = INITIAL_SUPPLY + 1000;
        assertTrue(token.canTransfer(holder, recipient, amount));
    }

    function test_canTransfer_falseWhenAmountExceedsUnfrozenButWithinBalance() public {
        vm.prank(freezer);
        token.setFrozenTokens(holder, 80);

        // Available = 100 - 80 = 20; 30 is within the balance but exceeds the unfrozen amount.
        assertFalse(token.canTransfer(holder, recipient, 30));
    }

    function test_canTransfer_trueForZeroBalanceSender() public {
        address emptyAccount = makeAddr("emptyAccount");
        assertTrue(token.canTransfer(emptyAccount, recipient, 1));
    }

    // --- canTransfer: canSend / canReceive gating ---

    function test_canTransfer_falseWhenCanSendFalse() public {
        token.setCanSend(holder, false);
        assertFalse(token.canTransfer(holder, recipient, 10));
    }

    function test_canTransfer_falseWhenCanReceiveFalse() public {
        token.setCanReceive(recipient, false);
        assertFalse(token.canTransfer(holder, recipient, 10));
    }

    function test_canTransfer_trueWhenCanSendAndCanReceiveTrue() public {
        token.setCanSend(holder, true);
        token.setCanReceive(recipient, true);
        assertTrue(token.canTransfer(holder, recipient, 10));
    }

    function test_canTransfer_defaultsToCanTransactWhenNotOverridden() public {
        // No overrides set: canSend/canReceive fall back to canTransact, which defaults to true.
        assertTrue(token.canTransfer(holder, recipient, 10));

        token.blockUser(holder);
        assertFalse(token.canTransfer(holder, recipient, 10));
    }

    // --- forcedTransfer: canReceive(to) enforcement ---

    function test_forcedTransfer_revertsWhenCanReceiveFalse() public {
        token.setCanReceive(recipient, false);

        vm.prank(enforcer);
        vm.expectRevert(abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotReceive.selector, recipient));
        token.forcedTransfer(holder, recipient, 10);
    }

    function test_forcedTransfer_succeedsWhenReceiveAllowedByDefault() public {
        vm.prank(enforcer);
        bool result = token.forcedTransfer(holder, recipient, 10);
        assertTrue(result);
        assertEq(token.balanceOf(holder), INITIAL_SUPPLY - 10);
        assertEq(token.balanceOf(recipient), 10);
    }

    // --- asymmetric send/receive permissions ---

    function test_accountCanReceiveButNotSend() public {
        // holder can send (default), recipient explicitly cannot send but can receive.
        token.setCanSend(recipient, false);
        token.setCanReceive(recipient, true);

        // holder -> recipient: holder can send, recipient can receive => true
        assertTrue(token.canTransfer(holder, recipient, 10));

        // recipient -> holder: recipient cannot send => false
        assertFalse(token.canTransfer(recipient, holder, 10));
    }

    function test_accountCanSendButNotReceive() public {
        // holder explicitly can send but cannot receive.
        token.setCanSend(holder, true);
        token.setCanReceive(holder, false);

        // recipient -> holder: holder cannot receive => false
        assertFalse(token.canTransfer(recipient, holder, 10));

        // holder -> recipient: holder can send, recipient can receive (default) => true
        assertTrue(token.canTransfer(holder, recipient, 10));
    }
}
