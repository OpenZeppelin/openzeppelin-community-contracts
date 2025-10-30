// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {Dispatch} from "../utils/Dispatch.sol";

/// @custom:stateless
contract DiamondCutFacet is Context, IDiamondCut {
    using Dispatch for Dispatch.VMT;

    error DiamondCutFacetAlreadyExist(bytes4 selector);
    error DiamondCutFacetAlreadySet(bytes4 selector);
    error DiamondCutFacetDoesNotExist(bytes4 selector);

    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) public override {
        Dispatch.VMT storage store = Dispatch.instance();

        store.enforceOwner(_msgSender());
        for (uint256 i = 0; i < _diamondCut.length; ++i) {
            FacetCut memory facetcut = _diamondCut[i];
            for (uint256 j = 0; j < facetcut.functionSelectors.length; ++j) {
                bytes4 selector = facetcut.functionSelectors[j];
                address currentFacet = store.getFunction(selector);
                if (facetcut.action == FacetCutAction.Add && currentFacet != address(0)) {
                    revert DiamondCutFacetAlreadyExist(selector);
                } else if (facetcut.action == FacetCutAction.Replace && currentFacet != facetcut.facetAddress) {
                    revert DiamondCutFacetAlreadySet(selector);
                } else if (facetcut.action == FacetCutAction.Remove && currentFacet == address(0)) {
                    revert DiamondCutFacetDoesNotExist(selector);
                }
                store.setFunction(selector, facetcut.facetAddress);
            }
        }

        emit DiamondCut(_diamondCut, _init, _calldata);

        if (_calldata.length > 0) {
            Address.functionDelegateCall(_init, _calldata);
	    }
    }
}
