// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {Dispatch} from "../utils/Dispatch.sol";

/// @custom:stateless
contract DiamondLoupeFacet is Context, IDiamondLoupe {
    using Dispatch for Dispatch.VMT;

    function facets() public view override returns (Facet[] memory) {
        this;
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetFunctionSelectors(address _facet) public view override returns (bytes4[] memory) {
        this;
        _facet;
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetAddresses() public view override returns (address[] memory) {
        this;
        revert("This implementation doesnt keep an index, use an offchain index instead");
    }

    function facetAddress(bytes4 _functionSelector) public view override returns (address) {
        return Dispatch.instance().getFunction(_functionSelector);
    }
}
