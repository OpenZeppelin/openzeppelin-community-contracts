// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {Dispatch} from "../utils/Dispatch.sol";

/// @custom:stateless
contract DiamondLoupeFacet is Context, IDiamondLoupe {
    using Dispatch for Dispatch.VMT;

    function facets() public view virtual override returns (Facet[] memory) {
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetFunctionSelectors(address /*_facet*/) public view virtual override returns (bytes4[] memory) {
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetAddresses() public view virtual override returns (address[] memory) {
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetAddress(bytes4 _functionSelector) public view virtual override returns (address) {
        return Dispatch.instance().getFunction(_functionSelector);
    }
}
