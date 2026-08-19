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

    function fulfillDeposit(uint256 epochId, uint256 shares) external {
        _fulfillDeposit(epochId, shares);
    }
}

/// @dev Fuzz regression for the deposit-side rounding findings on the epoch strategy.
/// Locks in the properties audit H-02 (fulfilled epoch cannot regress to the Pending
/// sentinel) and audit C-02 (no cross-epoch borrowing) against the floor-aligned
/// per-epoch entitlement in `_consumeClaimableMint`.
contract ERC7540EpochDepositFuzzTest is Test {
    EpochVault internal vault;
    ERC20Mock internal token;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant WEEK = 7 days;

    function setUp() public {
        token = new ERC20Mock();
        vault = new EpochVault(token);
    }

    // Two epochs so `maxMint(alice)` sums floor entitlements across epochs — the shape
    // that used to let a ceil-rounded `requested` in `_consumeClaimableMint` drain the
    // older epoch's `totalShares` to 0 while `totalAssets` stayed positive, freezing Bob
    // behind a Pending-looking epoch.
    function testFuzz_MintClaimPreservesFulfilledSentinel(
        uint128 rA1,
        uint128 rB1,
        uint128 fulfillS1,
        uint128 rA2,
        uint128 fulfillS2
    ) public {
        rA1 = uint128(bound(rA1, 1, 1e30));
        rB1 = uint128(bound(rB1, 1, 1e30));
        rA2 = uint128(bound(rA2, 1, 1e30));
        fulfillS1 = uint128(bound(fulfillS1, 1, 1e30));
        fulfillS2 = uint128(bound(fulfillS2, 1, 1e30));

        token.mint(ALICE, uint256(rA1) + rA2);
        token.mint(BOB, rB1);
        vm.startPrank(ALICE);
        token.approve(address(vault), type(uint256).max);
        vault.requestDeposit(rA1, ALICE, ALICE);
        vm.stopPrank();
        vm.startPrank(BOB);
        token.approve(address(vault), type(uint256).max);
        vault.requestDeposit(rB1, BOB, BOB);
        vm.stopPrank();

        uint256 epoch1 = vault.currentDepositEpoch();
        vm.warp(block.timestamp + WEEK);

        vm.prank(ALICE);
        vault.requestDeposit(rA2, ALICE, ALICE);
        uint256 epoch2 = vault.currentDepositEpoch();
        assertGt(epoch2, epoch1);

        vm.warp(block.timestamp + WEEK);
        vault.fulfillDeposit(epoch1, fulfillS1);
        vault.fulfillDeposit(epoch2, fulfillS2);

        uint256 tA1Before = vault.totalDepositAssets(epoch1);

        uint256 aliceMax = vault.maxMint(ALICE);
        if (aliceMax > 0) {
            vm.prank(ALICE);
            vault.mint(aliceMax, ALICE, ALICE);
        }

        // Sentinel invariant on epoch1: a fulfilled epoch cannot regress to the Pending
        // sentinel state (totalShares == 0) while assets remain in the pool.
        uint256 tA1 = vault.totalDepositAssets(epoch1);
        uint256 tS1 = vault.totalDepositShares(epoch1);
        assertFalse(tS1 == 0 && tA1 > 0, "epoch1 sentinel dirtied");

        // C-02 invariant on epoch1: Alice never consumed more assets from epoch1 than her
        // request in that epoch.
        assertLe(tA1Before - tA1, rA1, "epoch1 asset over-consumption");

        // Bob's claim slot on epoch1 stays reachable (matches `claimableDepositRequest`).
        assertEq(vault.claimableDepositRequest(epoch1, BOB), tS1 > 0 ? rB1 : 0);
    }
}
