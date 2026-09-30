// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC7540} from "../../../../contracts/token/ERC20/extensions/ERC7540.sol";
import {ERC7540EpochMock} from "../../../../contracts/mocks/token/ERC7540EpochMock.sol";

contract EpochVault is ERC7540EpochMock {
    constructor(IERC20 asset_) ERC20("Vault", "VLT") ERC7540(asset_) ERC7540EpochMock(address(0)) {}

    function fulfillRedeem(uint256 epochId, uint256 assets) external {
        _fulfillRedeem(epochId, assets);
    }

    function mintShares(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Fuzz regression for the redeem-side rounding findings on the epoch strategy.
/// Locks in the properties audit H-02 (fulfilled epoch cannot regress to the Pending
/// sentinel) and audit C-02 (no cross-epoch borrowing) against the floor-aligned
/// per-epoch entitlement in `_consumeClaimableWithdraw`.
contract ERC7540EpochRedeemFuzzTest is Test {
    EpochVault internal vault;
    ERC20Mock internal token;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant WEEK = 7 days;

    function setUp() public {
        token = new ERC20Mock();
        vault = new EpochVault(token);
    }

    // Two epochs so `maxWithdraw(alice)` sums floor entitlements across epochs — the
    // shape that used to let a ceil-rounded `requested` in `_consumeClaimableWithdraw`
    // drain the older epoch's `totalAssets` to 0 while `totalShares` stayed positive,
    // freezing Bob behind a Pending-looking epoch.
    function testFuzz_WithdrawClaimPreservesFulfilledSentinel(
        uint128 rA1,
        uint128 rB1,
        uint128 fulfillA1,
        uint128 rA2,
        uint128 fulfillA2
    ) public {
        rA1 = uint128(bound(rA1, 1, 1e30));
        rB1 = uint128(bound(rB1, 1, 1e30));
        rA2 = uint128(bound(rA2, 1, 1e30));
        fulfillA1 = uint128(bound(fulfillA1, 1, 1e30));
        fulfillA2 = uint128(bound(fulfillA2, 1, 1e30));

        // Seed share balances and a vault asset reserve for redemptions to pay out.
        vault.mintShares(ALICE, uint256(rA1) + rA2);
        vault.mintShares(BOB, rB1);
        token.mint(address(vault), uint256(fulfillA1) + fulfillA2);

        vm.prank(ALICE);
        vault.requestRedeem(rA1, ALICE, ALICE);
        vm.prank(BOB);
        vault.requestRedeem(rB1, BOB, BOB);

        uint256 epoch1 = vault.currentRedeemEpoch();
        vm.warp(block.timestamp + WEEK);

        vm.prank(ALICE);
        vault.requestRedeem(rA2, ALICE, ALICE);
        uint256 epoch2 = vault.currentRedeemEpoch();
        assertGt(epoch2, epoch1);

        vm.warp(block.timestamp + WEEK);
        vault.fulfillRedeem(epoch1, fulfillA1);
        vault.fulfillRedeem(epoch2, fulfillA2);

        uint256 tS1Before = vault.totalRedeemShares(epoch1);

        uint256 aliceMax = vault.maxWithdraw(ALICE);
        if (aliceMax > 0) {
            vm.prank(ALICE);
            vault.withdraw(aliceMax, ALICE, ALICE);
        }

        // Sentinel invariant on epoch1: fulfilled epoch cannot regress to Pending
        // (totalAssets == 0) while shares remain.
        uint256 tS1 = vault.totalRedeemShares(epoch1);
        uint256 tA1 = vault.totalRedeemAssets(epoch1);
        assertFalse(tA1 == 0 && tS1 > 0, "epoch1 sentinel dirtied");

        // Alice never burned more shares from epoch1 than her request there.
        assertLe(tS1Before - tS1, rA1, "epoch1 share over-consumption");

        // Bob's claim slot on epoch1 stays reachable.
        assertEq(vault.claimableRedeemRequest(epoch1, BOB), tA1 > 0 ? rB1 : 0);
    }
}
