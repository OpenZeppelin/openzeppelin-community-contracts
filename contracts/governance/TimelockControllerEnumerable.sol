// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Extends the TimelockController to allow for enumerable operations
contract TimelockControllerEnumerable is TimelockController {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice The operation struct
    struct Operation {
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
    }

    /// @notice The operation batch struct
    struct OperationBatch {
        address[] targets;
        uint256[] values;
        bytes[] payloads;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
    }

    /// @notice The error when the operation index is not found
    error OperationIndexNotFound(uint256 index);
    /// @notice The error when the operation id is not found
    error OperationIdNotFound(bytes32 id);
    /// @notice The error when the operation batch index is not found
    error OperationBatchIndexNotFound(uint256 index);
    /// @notice The error when the operation batch id is not found
    error OperationBatchIdNotFound(bytes32 id);

    /// @notice The operations id set
    EnumerableSet.Bytes32Set private _operationsIdSet;
    /// @notice The operations map
    mapping(bytes32 id => Operation operation) private _operationsMap;

    /// @notice The operations batch id set
    EnumerableSet.Bytes32Set private _operationsBatchIdSet;
    /// @notice The operations batch map
    mapping(bytes32 id => OperationBatch operationBatch) private _operationsBatchMap;

    /// @notice Initializes the contract with the given timelock parameters
    /// @param minDelay initial minimum delay in seconds for operations
    /// @param proposers accounts to be granted proposer and canceller roles
    /// @param executors accounts to be granted executor role
    /// @param admin optional account to be granted admin role; disable with zero address
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}

    /// @inheritdoc TimelockController
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override {
        super.schedule(target, value, data, predecessor, salt, delay);
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _operationsIdSet.add(id);
        _operationsMap[id] = Operation({
            target: target,
            value: value,
            data: data,
            predecessor: predecessor,
            salt: salt,
            delay: delay
        });
    }

    /// @inheritdoc TimelockController
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override {
        super.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        _operationsBatchIdSet.add(id);
        _operationsBatchMap[id] = OperationBatch({
            targets: targets,
            values: values,
            payloads: payloads,
            predecessor: predecessor,
            salt: salt,
            delay: delay
        });
    }

    /// @inheritdoc TimelockController
    function cancel(bytes32 id) public virtual override {
        super.cancel(id);
        if (_operationsIdSet.contains(id)) {
            _operationsIdSet.remove(id);
            delete _operationsMap[id];
        }
        if (_operationsBatchIdSet.contains(id)) {
            _operationsBatchIdSet.remove(id);
            delete _operationsBatchMap[id];
        }
    }

    /// @notice Return all scheduled operations
    /// @return operations_ The operations array
    function operations() public view returns (Operation[] memory operations_) {
        uint256 operationsCount_ = _operationsIdSet.length();
        operations_ = new Operation[](operationsCount_);
        for (uint256 i = 0; i < operationsCount_; i++) {
            operations_[i] = _operationsMap[_operationsIdSet.at(i)];
        }
        return operations_;
    }

    /// @notice Return the number of operations from the set
    /// @return operationsCount_ The number of operations
    function operationsCount() public view returns (uint256 operationsCount_) {
        operationsCount_ = _operationsIdSet.length();
        return operationsCount_;
    }

    /// @notice Return the operation at the given index
    /// @param index The index of the operation
    /// @return operation_ The operation
    function operation(uint256 index) public view returns (Operation memory operation_) {
        if (index >= _operationsIdSet.length()) {
            revert OperationIndexNotFound(index);
        }
        operation_ = _operationsMap[_operationsIdSet.at(index)];
        return operation_;
    }

    /// @notice Return the operation with the given id
    /// @param id The id of the operation
    /// @return operation_ The operation
    function operation(bytes32 id) public view returns (Operation memory operation_) {
        if (!_operationsIdSet.contains(id)) {
            revert OperationIdNotFound(id);
        }
        operation_ = _operationsMap[id];
        return operation_;
    }

    /// @notice Return all scheduled operation batches
    /// @return operationsBatch_ The operationsBatch array
    function operationsBatch() public view returns (OperationBatch[] memory operationsBatch_) {
        uint256 operationsBatchCount_ = _operationsBatchIdSet.length();
        operationsBatch_ = new OperationBatch[](operationsBatchCount_);
        for (uint256 i = 0; i < operationsBatchCount_; i++) {
            operationsBatch_[i] = _operationsBatchMap[_operationsBatchIdSet.at(i)];
        }
        return operationsBatch_;
    }

    /// @notice Return the number of operationsBatch from the set
    /// @return operationsBatchCount_ The number of operationsBatch
    function operationsBatchCount() public view returns (uint256 operationsBatchCount_) {
        operationsBatchCount_ = _operationsBatchIdSet.length();
        return operationsBatchCount_;
    }

    /// @notice Return the operationsBatch at the given index
    /// @param index The index of the operationsBatch
    /// @return operationBatch_ The operationsBatch
    function operationBatch(uint256 index) public view returns (OperationBatch memory operationBatch_) {
        if (index >= _operationsBatchIdSet.length()) {
            revert OperationBatchIndexNotFound(index);
        }
        operationBatch_ = _operationsBatchMap[_operationsBatchIdSet.at(index)];
        return operationBatch_;
    }

    /// @notice Return the operationsBatch with the given id
    /// @param id The id of the operationsBatch
    /// @return operationBatch_ The operationsBatch
    function operationBatch(bytes32 id) public view returns (OperationBatch memory operationBatch_) {
        if (!_operationsBatchIdSet.contains(id)) {
            revert OperationBatchIdNotFound(id);
        }
        operationBatch_ = _operationsBatchMap[id];
        return operationBatch_;
    }
}
