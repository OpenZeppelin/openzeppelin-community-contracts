// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "./vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "./vendor/axelar/interfaces/IAxelarGasService.sol";
import {CAIP2} from "../utils/CAIP-2.sol";

/// @dev Equivalence interface between CAIP-2 chain identifiers and Gateway-specific chain identifiers.
///
/// See https://chainagnostic.org/CAIPs/caip-2[CAIP2].
interface ICAIP2Equivalence {
    /// @dev Sets a CAIP-2 chain identifier as equivalent to a Gateway-specific chain identifier.
    function setCAIP2Equivalence(CAIP2.ChainId memory chain, bytes memory custom) external;

    /// @dev Checks if a CAIP-2 chain identifier is registered as equivalent to a Gateway-specific chain identifier.
    function exists(CAIP2.ChainId memory chain) external view returns (bool);

    /// @dev Retrieves the Gateway-specific chain identifier equivalent to a CAIP-2 chain identifier.
    function fromCAIP2(CAIP2.ChainId memory chain) external pure returns (bytes memory);
}
