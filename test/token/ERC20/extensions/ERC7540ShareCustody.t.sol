// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test, stdError} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ERC7540MutableCustodyMock, ERC7540StorageCustodyDelayMock} from "./ERC7540ShareCustodyMock.t.sol";

/// @dev The two share custody hooks are read at different stages. {ERC7540-_depositShareOrigin} is read at
/// fulfillment and again at claim. {ERC7540-_redeemShareDestination} is read at request and again at
/// fulfillment, never at claim, but the claim lowers {ERC7540-totalPendingRedeemShares} unconditionally and so
/// depends on those two reads having agreed. Either way the pair has to agree, and these tests show what a
/// vault whose custody value moves in between does to its own accounting.
contract ERC7540ShareCustodyTest is Test {
    ERC20Mock private _asset;

    address private _escrow = makeAddr("escrow");
    address private _alice = makeAddr("alice");
    address private _bob = makeAddr("bob");

    uint256 private constant AMOUNT = 1000;

    function setUp() public {
        _asset = new ERC20Mock();
    }

    function _fund(address vault, address account) private {
        _asset.mint(account, AMOUNT);
        vm.prank(account);
        _asset.approve(vault, type(uint256).max);
    }

    /// @dev Custody is dropped between fulfillment and claim. The claim takes the mint-on-claim branch even
    /// though fulfillment already took the pre-mint branch, so the shares are minted twice and the pending
    /// asset counter is decremented twice, the second time against another controller's request.
    function test_dropCustodyBetweenFulfillAndClaim() public {
        ERC7540MutableCustodyMock vault = new ERC7540MutableCustodyMock(IERC20(address(_asset)), _escrow, _escrow);
        _fund(address(vault), _alice);
        _fund(address(vault), _bob);

        vm.prank(_alice);
        vault.requestDeposit(AMOUNT, _alice, _alice);
        vm.prank(_bob);
        vault.requestDeposit(AMOUNT, _bob, _bob);
        assertEq(vault.totalPendingDepositAssets(), 2 * AMOUNT);

        // Alice is fulfilled under the pre-mint custody model.
        vault.fulfillDeposit(AMOUNT, AMOUNT, _alice);
        assertEq(vault.totalPendingDepositAssets(), AMOUNT, "fulfillment consumed Alice's pending assets");
        assertEq(vault.balanceOf(_escrow), AMOUNT, "shares pre-minted to the escrow");

        vault.setDepositShareOrigin(address(0));

        uint256 supplyBefore = vault.totalSupply();
        uint256 claimable = vault.maxDeposit(_alice);
        vm.prank(_alice);
        vault.deposit(claimable, _alice, _alice);

        // The shares Alice claims are minted a second time; the pre-minted ones stay at the escrow.
        assertEq(vault.balanceOf(_alice), AMOUNT, "Alice received freshly minted shares");
        assertEq(vault.balanceOf(_escrow), AMOUNT, "pre-minted shares stranded at the escrow");
        assertEq(vault.totalSupply(), supplyBefore + AMOUNT, "supply doubled for a single deposit");

        // The second decrement came out of Bob's request, which is still on the books.
        assertEq(vault.totalPendingDepositAssets(), 0, "Bob's pending assets were consumed by Alice's claim");
        assertEq(vault.pendingDepositRequest(0, _bob), AMOUNT, "Bob's request still recorded");

        // Bob can no longer be paid: his claim underflows the global counter.
        vault.fulfillDeposit(AMOUNT, AMOUNT, _bob);
        uint256 bobClaimable = vault.maxDeposit(_bob);
        vm.prank(_bob);
        vm.expectRevert(stdError.arithmeticError);
        vault.deposit(bobClaimable, _bob, _bob);
    }

    /// @dev The mirror case. Custody is adopted between fulfillment and claim, so the claim tries to transfer
    /// shares out of an escrow that fulfillment never pre-minted to.
    function test_adoptCustodyBetweenFulfillAndClaim() public {
        ERC7540MutableCustodyMock vault = new ERC7540MutableCustodyMock(
            IERC20(address(_asset)),
            address(0),
            address(0)
        );
        _fund(address(vault), _alice);

        vm.prank(_alice);
        vault.requestDeposit(AMOUNT, _alice, _alice);
        vault.fulfillDeposit(AMOUNT, AMOUNT, _alice);
        assertEq(vault.balanceOf(_escrow), 0, "mint-on-claim fulfillment pre-mints nothing");
        assertEq(vault.totalPendingDepositAssets(), AMOUNT);

        vault.setDepositShareOrigin(_escrow);

        uint256 claimable = vault.maxDeposit(_alice);
        vm.prank(_alice);
        vm.expectRevert(); // transfer from an escrow that holds no shares
        vault.deposit(claimable, _alice, _alice);
    }

    /// @dev Redeem side. The hook is read at request and again at fulfillment, and the two reads have to
    /// agree: exactly one of them raises `_totalPendingRedeemShares`. The claim never reads the hook, it
    /// lowers that counter unconditionally, so a request whose two reads disagree is never counted and the
    /// claim takes the shortfall out of whatever another controller put there.
    function test_dropRedeemCustodyBetweenRequestAndFulfill() public {
        ERC7540MutableCustodyMock vault = new ERC7540MutableCustodyMock(IERC20(address(_asset)), address(0), _escrow);
        _fund(address(vault), _alice);
        _fund(address(vault), _bob);

        // Both hold shares, minted one for one.
        address[2] memory holders = [_alice, _bob];
        for (uint256 i = 0; i < holders.length; ++i) {
            vm.prank(holders[i]);
            vault.requestDeposit(AMOUNT, holders[i], holders[i]);
            vault.fulfillDeposit(AMOUNT, AMOUNT, holders[i]);
            uint256 claimable = vault.maxDeposit(holders[i]);
            vm.prank(holders[i]);
            vault.deposit(claimable, holders[i], holders[i]);
            assertEq(vault.balanceOf(holders[i]), AMOUNT);
        }

        // Alice requests under the escrow model: shares move, the counter is not raised.
        vm.prank(_alice);
        vault.requestRedeem(AMOUNT, _alice, _alice);
        assertEq(vault.balanceOf(_escrow), AMOUNT, "Alice's shares escrowed");
        assertEq(vault.totalPendingRedeemShares(), 0, "escrow branch raises nothing at request");

        vault.setRedeemShareDestination(address(0));

        // Bob requests under the burn-at-request model: his shares are burned and counted.
        vm.prank(_bob);
        vault.requestRedeem(AMOUNT, _bob, _bob);
        assertEq(vault.totalPendingRedeemShares(), AMOUNT, "only Bob's request is counted");

        // Neither fulfillment raises the counter now, because the hook reads zero for both.
        vault.fulfillRedeem(AMOUNT, AMOUNT, _alice);
        vault.fulfillRedeem(AMOUNT, AMOUNT, _bob);
        assertEq(vault.totalPendingRedeemShares(), AMOUNT, "Alice's request was never counted");
        assertEq(vault.balanceOf(_escrow), AMOUNT, "Alice's escrowed shares were never burned");

        // Alice claims and is paid, out of the counter Bob's request populated.
        uint256 aliceBefore = _asset.balanceOf(_alice);
        vm.prank(_alice);
        vault.redeem(AMOUNT, _alice, _alice);
        assertEq(_asset.balanceOf(_alice) - aliceBefore, AMOUNT, "Alice was paid");
        assertEq(vault.totalPendingRedeemShares(), 0, "Alice consumed Bob's accounting");

        // Bob cannot claim any more.
        vm.prank(_bob);
        vm.expectRevert(stdError.arithmeticError);
        vault.redeem(AMOUNT, _bob, _bob);

        // And the escrowed shares are still outstanding, so supply stays overstated.
        assertEq(vault.balanceOf(_escrow), AMOUNT, "escrowed shares never burned");
    }

    /// @dev The ERC7540Delay modules check the custody hooks once, in their constructor. A storage-backed
    /// override written by the child constructor body passes that check and then takes the very branch the
    /// module documents as unsupported, which strands the shares and bricks every redeem claim.
    function test_delayConstructorCheckMissesStorageBackedOverride() public {
        ERC7540StorageCustodyDelayMock vault = new ERC7540StorageCustodyDelayMock(
            IERC20(address(_asset)),
            address(0),
            _escrow
        );
        assertEq(vault.redeemShareDestination(), _escrow, "constructor check passed on an unsupported vault");

        _fund(address(vault), _alice);
        vm.prank(_alice);
        vault.requestDeposit(AMOUNT, _alice, _alice);
        vm.warp(block.timestamp + 2 hours);
        uint256 claimable = vault.maxDeposit(_alice);
        vm.prank(_alice);
        vault.deposit(claimable, _alice, _alice);

        uint256 shares = vault.balanceOf(_alice);
        assertGt(shares, 0);

        vm.prank(_alice);
        vault.requestRedeem(shares, _alice, _alice);

        // The escrow branch ran: shares were moved instead of burned, so the pending counter was never raised.
        assertEq(vault.balanceOf(_escrow), shares, "shares escrowed rather than burned");
        assertEq(vault.totalPendingRedeemShares(), 0, "pending redeem shares never recorded");

        vm.warp(block.timestamp + 2 hours);
        uint256 redeemable = vault.maxRedeem(_alice);
        assertEq(redeemable, shares, "the request is still claimable on paper");

        vm.prank(_alice);
        vm.expectRevert(stdError.arithmeticError);
        vault.redeem(redeemable, _alice, _alice);

        assertEq(vault.balanceOf(_alice), 0, "Alice cannot recover her shares");
        assertEq(vault.balanceOf(_escrow), shares, "the shares remain stuck at the escrow");
    }

    /// @dev Deposit-side mirror of the previous test. The escaped check leaves the claim reaching for
    /// pre-minted shares that a delay-based vault never mints, so the assets stay locked and
    /// {totalPendingDepositAssets} stays permanently inflated.
    function test_delayConstructorCheckMissesStorageBackedOriginOverride() public {
        ERC7540StorageCustodyDelayMock vault = new ERC7540StorageCustodyDelayMock(
            IERC20(address(_asset)),
            _escrow,
            address(0)
        );
        assertEq(vault.depositShareOrigin(), _escrow, "constructor check passed on an unsupported vault");

        _fund(address(vault), _alice);
        vm.prank(_alice);
        vault.requestDeposit(AMOUNT, _alice, _alice);
        assertEq(vault.totalPendingDepositAssets(), AMOUNT);

        vm.warp(block.timestamp + 2 hours);
        uint256 claimable = vault.maxDeposit(_alice);
        assertEq(claimable, AMOUNT, "the request is claimable on paper");

        vm.prank(_alice);
        vm.expectRevert(); // transfer from an escrow a delay vault never pre-mints to
        vault.deposit(claimable, _alice, _alice);

        assertEq(vault.totalPendingDepositAssets(), AMOUNT, "pending assets stay inflated forever");
        assertEq(vault.totalAssets(), 0, "the deposited assets are permanently excluded from totalAssets");
        assertEq(_asset.balanceOf(address(vault)), AMOUNT, "the assets are stuck in the vault");
    }
}
