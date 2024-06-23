// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "./vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "./vendor/axelar/interfaces/IAxelarGasService.sol";

import {GenericGatewayCommon} from "./GenericGatewayCommon.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts@master/utils/math/Math.sol";

contract GenericGatewayAxelar is GenericGatewayCommon, Ownable {
    IAxelarGateway public immutable gateway;
    IAxelarGasService public immutable gasService;

    struct ChainDetails {
        string name;
        string remote;
    }

    mapping(uint256 chainId => ChainDetails chainName) public chainDetails;

    constructor(IAxelarGateway _gateway, address _initialOwner) Ownable(_initialOwner) {
        gateway = _gateway;
    }

    function registerForeignChainDetails(uint256 chainId, ChainDetails memory details) public onlyOwner {
        require(chainId != block.chainid);
        require(bytes(chainDetails[chainId].name).length == 0);
        chainDetails[chainId] = details;
    }

    function defaultCost(Message memory /*message*/) public pure virtual override returns (address, uint256) {
        return (address(0), 0);
    }

    function estimateCost(Message memory /*message*/, address asset) public pure virtual returns (uint256) {
        return Math.ternary(asset == address(0), 0, type(uint256).max);
    }

    /// @dev Override that the target blockchain is registered and that 0 value is passed when creating a request.
    function createRequest(
        uint256 chain,
        address target,
        bytes memory data,
        bytes32 salt
    ) public payable virtual override returns (bytes32) {
        require(msg.value == 0, "Axelar does not support native currency bridging");

        // retrieve chain details for the destination chain
        ChainDetails storage details = chainDetails[chain];
        require(bytes(details.name).length > 0, "Remote chain not registered");

        return super.createRequest(chain, target, data, salt);
    }

    function _processRequest(
        bytes32 /*id*/,
        Request memory req,
        address feeAsset,
        uint256 feeValue
    ) internal virtual override {
        require(feeAsset == address(0), "Axelar only supports fees in native currency");
        require(req.message.value == 0, "Axelar does not support native currency bridging");

        ChainDetails storage details = chainDetails[req.message.destination.chain];
        require(bytes(details.name).length > 0, "Remote chain not registered");

        bytes memory payload = abi.encode(req);

        // If value is provided, forward it to the gasService
        if (feeValue > 0) {
            gasService.payNativeGasForContractCall{value: feeValue}(
                address(this),
                details.name,
                details.remote,
                payload,
                msg.sender
            );
        }

        // send cross-chain signal
        gateway.callContract(details.name, details.remote, payload);
    }
}
