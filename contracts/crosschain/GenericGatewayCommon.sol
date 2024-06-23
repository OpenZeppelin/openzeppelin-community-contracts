// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGenericGateway} from "./IGenericGateway.sol";
import {Set} from "../utils/Set.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlotDerivation} from "@openzeppelin/contracts@master/utils/SlotDerivation.sol";
import {StorageSlot} from "@openzeppelin/contracts@master/utils/StorageSlot.sol";

abstract contract GenericGatewayCommon is IGenericGateway {
    using SlotDerivation for *;
    using StorageSlot for *;
    using Set for Set.Bytes32Set;

    event RequestCreated(bytes32 id, Request req);
    event RequestForwarded(bytes32 id);
    event RequestExecuted(bytes32 id);

    Set.Bytes32Set private _outBox;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.GenericGatewayCommon")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GENERIC_GATEWAY_COMMON_STORAGE =
        0x71ab59e9fe1edd5f3d56389a2c715a90ddbb606dacc41e1c5360c10e3fe15b00;

    function crossChainSender() public view returns (uint256 chainId, address sender) {
        return (
            GENERIC_GATEWAY_COMMON_STORAGE.offset(0).asUint256().tload(),
            GENERIC_GATEWAY_COMMON_STORAGE.offset(1).asAddress().tload()
        );
    }

    // This must be redeclared as public so that other function can call it
    function defaultCost(Message memory /*message*/) public pure virtual returns (address, uint256);

    function sendRequest(
        uint256 chain,
        address target,
        uint256 value,
        bytes memory data,
        bytes32 salt
    ) public payable virtual returns (bytes32) {
        (address feeAsset, uint256 feeValue) = defaultCost(
            Message({destination: Account({chain: chain, instance: target}), value: value, data: data})
        );
        return sendRequest(chain, target, value, data, salt, feeAsset, feeValue);
    }

    function sendRequest(
        uint256 chain,
        address target,
        uint256 value,
        bytes memory data,
        bytes32 salt,
        address feeAsset,
        uint256 feeValue
    ) public payable virtual returns (bytes32) {
        // build request, payload and hash
        Request memory req = _generateRequest(chain, target, msg.sender, value, data, salt);
        bytes32 id = keccak256(abi.encode(req));

        if (feeAsset == address(0)) {
            uint256 totalValue = value + feeValue;
            require(msg.value >= totalValue, "invalid value provided");
            if (msg.value > totalValue) Address.sendValue(payable(msg.sender), msg.value - totalValue);
        } else {
            require(msg.value >= value, "invalid value provided");
            if (feeValue > 0) SafeERC20.safeTransferFrom(IERC20(feeAsset), msg.sender, address(this), feeValue);
            if (msg.value > value) Address.sendValue(payable(msg.sender), msg.value - value);
        }

        _processRequest(id, req, feeAsset, feeValue);

        // TODO: event

        return id;
    }

    // ================================================= 2 step mode =================================================

    function createRequest(
        uint256 chain,
        address target,
        bytes memory data,
        bytes32 salt
    ) public payable virtual returns (bytes32) {
        // build request, payload and hash
        Request memory req = _generateRequest(chain, target, msg.sender, msg.value, data, salt);
        bytes32 id = keccak256(abi.encode(req));

        // register the request hash
        require(_outBox.insert(id), "Ticket already scheduled");

        // emit notice
        emit RequestCreated(id, req);

        return id;
    }

    function forwardRequest(Request memory req) public payable virtual {
        (address feeAsset, uint256 feeValue) = defaultCost(req.message);
        forwardRequest(req, feeAsset, feeValue);
    }

    function forwardRequest(Request memory req, address feeAsset, uint256 feeValue) public payable virtual {
        // compute the request hash
        bytes32 id = keccak256(abi.encode(req));

        if (feeAsset == address(0)) {
            require(msg.value >= feeValue, "invalid value provided");
            if (msg.value > feeValue) Address.sendValue(payable(msg.sender), msg.value - feeValue);
        } else {
            if (feeValue > 0) SafeERC20.safeTransferFrom(IERC20(feeAsset), msg.sender, address(this), feeValue);
            if (msg.value > 0) Address.sendValue(payable(msg.sender), msg.value);
        }

        // consume request hash
        require(_outBox.remove(id), "Ticket not scheduled");

        _processRequest(id, req, feeAsset, feeValue);

        // emit notice
        emit RequestForwarded(id);
    }

    // =============================================== specialisation ================================================

    function _processRequest(bytes32 id, Request memory req, address feeAsset, uint256 feeValue) internal virtual;

    // =================================================== helpers ===================================================
    function _generateRequest(
        uint256 chain,
        address target,
        address sender,
        uint256 value,
        bytes memory data,
        bytes32 salt
    ) internal view returns (Request memory) {
        return
            Request({
                source: Account({chain: block.chainid, instance: sender}),
                message: Message({destination: Account({chain: chain, instance: target}), value: value, data: data}),
                salt: salt
            });
    }

    function _executeRequest(Request memory req) internal {
        require(req.message.destination.chain == block.chainid);

        GENERIC_GATEWAY_COMMON_STORAGE.offset(0).asUint256().tstore(req.source.chain);
        GENERIC_GATEWAY_COMMON_STORAGE.offset(1).asAddress().tstore(req.source.instance);

        (bool success, bytes memory returndata) = req.message.destination.instance.call{value: req.message.value}(
            req.message.data
        );
        Address.verifyCallResult(success, returndata);

        GENERIC_GATEWAY_COMMON_STORAGE.offset(0).asUint256().tstore(0);
        GENERIC_GATEWAY_COMMON_STORAGE.offset(1).asAddress().tstore(address(0));
    }
}
