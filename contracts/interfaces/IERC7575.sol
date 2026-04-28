// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @dev Multi-Asset ERC-4626 Vaults, as defined in https://eips.ethereum.org/EIPS/eip-7575
 */
interface IERC7575 is IERC165, IERC4626 {
    /// @dev The address of the underlying share received on deposit into the Vault.
    function share() external view returns (address shareTokenAddress);
}
