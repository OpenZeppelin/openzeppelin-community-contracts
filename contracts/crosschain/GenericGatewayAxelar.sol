// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGenericGateway} from "./IGenericGateway.sol";
import {Set} from "../utils/Set.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts@master/utils/math/Math.sol";

import {IAxelarGateway} from "./vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "./vendor/axelar/interfaces/IAxelarGasService.sol";

contract GenericGatewayAxelar is IGenericGateway, Ownable {
    using Set for Set.Bytes32Set;

    event RequestCreated(bytes32 id, Request req);
    event RequestForwarded(bytes32 id);
    event RequestExecuted(bytes32 id);

    IAxelarGateway public immutable gateway;
    IAxelarGasService public immutable gasService;
    Set.Bytes32Set private _outBox;

    struct ChainDetails { string name; string remote; }
    mapping(uint256 chainId => ChainDetails chainName) public chainDetails;

    constructor(IAxelarGateway _gateway, address _initialOwner) Ownable(_initialOwner) {
        gateway = _gateway;
    }

    function registerForeignChainDetails(uint256 chainId, ChainDetails memory details) public onlyOwner() {
        require(chainId != block.chainid);
        require(bytes(chainDetails[chainId].name).length == 0);
        chainDetails[chainId] = details;
    }

    // =============================================== cost estimation ===============================================

    function defaultCost(Message memory /*message*/) public pure returns (address, uint256) {
        return (address(0), 0);
    }

    function estimateCost(Message memory /*message*/, address asset) public pure returns (uint256) {
        return Math.ternary(asset == address(0), 0, type(uint256).max);
    }

    // ================================================= 1 step mode =================================================

    function sendRequest(uint256 chain, address target, bytes memory data, bytes32 salt) public payable returns (bytes32) {
        Request memory req = _generateRequest(chain, target, msg.sender, 0, data, salt);
        (address feeAsset, uint256 feeValue) = defaultCost(req.message);
        return _sendRequest(req, feeAsset, feeValue);
    }

    function sendRequest(uint256 chain, address target, bytes memory data, bytes32 salt, address feeAsset, uint256 feeValue) public payable returns (bytes32) {
        Request memory req = _generateRequest(chain, target, msg.sender, 0, data, salt);
        return _sendRequest(req, feeAsset, feeValue);
    }

    function _sendRequest(Request memory req, address feeAsset, uint256 feeValue) internal returns (bytes32) {
        // retrieve chain details for the destination chain
        ChainDetails storage details = chainDetails[req.message.destination.chain];
        require(bytes(details.name).length > 0, "Remote chain not registered");

        // rebuild request hash
        bytes memory payload = abi.encode(req);
        bytes32 id = keccak256(payload);

        // If value is provided, forward it to the gasService
        require(feeAsset == address(0) && feeValue == msg.value); // Axelar only support ether
        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{ value: msg.value }(address(this), details.name, details.remote, payload, msg.sender);
        }

        // send cross-chain signal
        gateway.callContract(details.name, details.remote, payload);

        // TODO: event

        return id;
    }

    // ================================================= 2 step mode =================================================

    function createRequest(uint256 chain, address target, bytes memory data, bytes32 salt) public payable returns (bytes32) {
        require(msg.value == 0); // Axelar doesn't support value

        Request memory req = _generateRequest(chain, target, msg.sender, 0, data, salt);
        return _createRequest(req);
    }

    function _createRequest(Request memory req) internal returns (bytes32) {
        // retrieve chain details for the destination chain
        ChainDetails storage details = chainDetails[req.message.destination.chain];
        require(bytes(details.name).length > 0, "Remote chain not registered");

        // compute the request hash
        bytes memory payload = abi.encode(req);
        bytes32 id = keccak256(payload);

        // register the request hash
        require(_outBox.insert(id), "Ticket already scheduled");

        // emit notice
        emit RequestCreated(id, req);

        return id;

    }

    function forwardRequest(Request memory req) public payable {
        (address feeAsset, uint256 feeValue) = defaultCost(req.message);
        _forwardRequest(req, feeAsset, feeValue);
    }

    function forwardRequest(Request memory req, address feeAsset, uint256 feeValue) public payable {
        _forwardRequest(req, feeAsset, feeValue);
    }

    function _forwardRequest(Request memory req, address feeAsset, uint256 feeValue) internal {
        ChainDetails storage details = chainDetails[req.message.destination.chain];
        // Not needed, was verified during request creation
        // require(bytes(details.name).length > 0, "Remote chain not registered");

        // compute the request hash
        bytes memory payload = abi.encode(req);
        bytes32 id = keccak256(payload);

        // consume request hash
        require(_outBox.remove(id), "Ticket not scheduled");

        // If value is provided, forward it to the gasService
        require(feeAsset == address(0) && feeValue == msg.value);
        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{ value: msg.value }(address(this), details.name, details.remote, payload, msg.sender);
        }

        // send cross-chain signal
        gateway.callContract(details.name, details.remote, payload);

        // emit notice
        emit RequestForwarded(id);
    }

    // =========================================== receive end (specific) ============================================
    function executeRequest(Request memory req, bytes32 commandId) public payable {
        // compute the request hash
        bytes memory payload = abi.encode(req);
        bytes32 id = keccak256(payload);

        // retrieve chain details for the source chain
        ChainDetails storage details = chainDetails[req.source.chain];
        require(bytes(details.name).length > 0, "Remote chain not registered");

        // validate operation (includes replay protection)
        require(gateway.validateContractCall(commandId, details.name, details.remote, id));

        // perform call
        _executeRequest(req.message);

        // emit notice
        emit RequestExecuted(id);
    }

    // =================================================== helpers ===================================================
    function _generateRequest(
        uint256 chain,
        address target,
        address sender,
        uint256 value,
        bytes memory data,
        bytes32 salt
    ) internal view returns (Request memory) {
        return Request({
            source: Account({
                chain: block.chainid,
                instance: sender
            }),
            message: Message({
                destination: Account({
                    chain: chain,
                    instance: target
                }),
                value: value,
                data: data
            }),
            salt: salt
        });
    }

    function _executeRequest(Message memory message) internal {
        require(message.destination.chain == block.chainid);
        (bool success, bytes memory returndata) = message.destination.instance.call{value: message.value}(message.data);
        Address.verifyCallResult(success, returndata);
    }
}
