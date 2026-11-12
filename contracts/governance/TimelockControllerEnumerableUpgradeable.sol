// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @dev Extends the TimelockController to allow for enumerable operations
abstract contract TimelockControllerEnumerableUpgradeable is Initializable, TimelockControllerUpgradeable {
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

    /// @dev The error when the operation index is not found
    error OperationIndexNotFound(uint256 index);
    /// @dev The error when the operation id is not found
    error OperationIdNotFound(bytes32 id);
    /// @dev The error when the operation batch index is not found
    error OperationBatchIndexNotFound(uint256 index);
    /// @dev The error when the operation batch id is not found
    error OperationBatchIdNotFound(bytes32 id);
    /// @dev The error when the index range is invalid
    error InvalidIndexRange(uint256 start, uint256 end);

    /// @custom:storage-location erc7201:openzeppelin.storage.TimelockControllerEnumerable
    struct TimelockControllerEnumerableStorage {
        /// @notice The operations id set
        EnumerableSet.Bytes32Set _operationsIdSet;
        /// @notice The operations map
        mapping(bytes32 id => Operation operation) _operationsMap;

        /// @notice The operations batch id set
        EnumerableSet.Bytes32Set _operationsBatchIdSet;
        /// @notice The operations batch map
        mapping(bytes32 id => OperationBatch operationBatch) _operationsBatchMap;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.TimelockControllerEnumerable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TimelockControllerEnumerableStorageLocation = 0x3595215c8b401bfe88deacb896d8111ca009fa3a601b0894c7bd7bd16456fe00;

    function _getTimelockControllerEnumerableStorage() private pure returns (TimelockControllerEnumerableStorage storage $) {
        assembly {
            $.slot := TimelockControllerEnumerableStorageLocation
        }
    }

    function __TimelockControllerEnumerable_init() internal onlyInitializing {
    }

    function __TimelockControllerEnumerable_init_unchained() internal onlyInitializing {
    }
    /// @inheritdoc TimelockControllerUpgradeable
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        super.schedule(target, value, data, predecessor, salt, delay);
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        $._operationsIdSet.add(id);
        $._operationsMap[id] = Operation({
            target: target,
            value: value,
            data: data,
            predecessor: predecessor,
            salt: salt,
            delay: delay
        });
    }

    /// @inheritdoc TimelockControllerUpgradeable
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        super.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        $._operationsBatchIdSet.add(id);
        $._operationsBatchMap[id] = OperationBatch({
            targets: targets,
            values: values,
            payloads: payloads,
            predecessor: predecessor,
            salt: salt,
            delay: delay
        });
    }

    /// @inheritdoc TimelockControllerUpgradeable
    function cancel(bytes32 id) public virtual override {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        super.cancel(id);
        if ($._operationsIdSet.contains(id)) {
            $._operationsIdSet.remove(id);
            delete $._operationsMap[id];
        }
        if ($._operationsBatchIdSet.contains(id)) {
            $._operationsBatchIdSet.remove(id);
            delete $._operationsBatchMap[id];
        }
    }

    /// @dev Return all scheduled operations
    /// WARNING: This is designed for view accessors queried without gas fees. Using it in state-changing
    /// functions may become uncallable if the list grows too large.
    function operations() public view returns (Operation[] memory operations_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        return operations(0, $._operationsIdSet.length());
    }

    /// @dev Return the operations in the given index range
    /// @param start The start index
    /// @param end The end index
    /// @return operations_ The operations
    /// WARNING: This is designed for view accessors queried without gas fees. Using it in state-changing
    /// functions may become uncallable if the list grows too large.
    function operations(uint256 start, uint256 end) public view returns (Operation[] memory operations_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (start > end || start >= $._operationsIdSet.length()) {
            revert InvalidIndexRange(start, end);
        }
        operations_ = new Operation[](end - start);
        for (uint256 i = start; i < end; i++) {
            operations_[i] = $._operationsMap[$._operationsIdSet.at(i)];
        }
        return operations_;
    }

    /// @dev Return the number of operations from the set
    function operationsCount() public view returns (uint256 operationsCount_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        operationsCount_ = $._operationsIdSet.length();
        return operationsCount_;
    }

    /// @dev Return the operation at the given index
    function operation(uint256 index) public view returns (Operation memory operation_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (index >= $._operationsIdSet.length()) {
            revert OperationIndexNotFound(index);
        }
        operation_ = $._operationsMap[$._operationsIdSet.at(index)];
        return operation_;
    }

    /// @dev Return the operation with the given id
    function operation(bytes32 id) public view returns (Operation memory operation_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (!$._operationsIdSet.contains(id)) {
            revert OperationIdNotFound(id);
        }
        operation_ = $._operationsMap[id];
        return operation_;
    }

    /// @dev Return all scheduled operation batches
    /// WARNING: This is designed for view accessors queried without gas fees. Using it in state-changing
    /// functions may become uncallable if the list grows too large.
    function operationsBatch() public view returns (OperationBatch[] memory operationsBatch_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        return operationsBatch(0, $._operationsBatchIdSet.length());
    }

    /// @dev Return the operationsBatch in the given index range
    /// @param start The start index
    /// @param end The end index
    /// @return operationsBatch_ The operationsBatch
    /// WARNING: This is designed for view accessors queried without gas fees. Using it in state-changing
    /// functions may become uncallable if the list grows too large.
    function operationsBatch(
        uint256 start,
        uint256 end
    ) public view returns (OperationBatch[] memory operationsBatch_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (start > end || start >= $._operationsBatchIdSet.length()) {
            revert InvalidIndexRange(start, end);
        }
        operationsBatch_ = new OperationBatch[](end - start);
        for (uint256 i = start; i < end; i++) {
            operationsBatch_[i] = $._operationsBatchMap[$._operationsBatchIdSet.at(i)];
        }
        return operationsBatch_;
    }

    /// @dev Return the number of operationsBatch from the set
    function operationsBatchCount() public view returns (uint256 operationsBatchCount_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        operationsBatchCount_ = $._operationsBatchIdSet.length();
        return operationsBatchCount_;
    }

    /// @dev Return the operationsBatch at the given index
    function operationBatch(uint256 index) public view returns (OperationBatch memory operationBatch_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (index >= $._operationsBatchIdSet.length()) {
            revert OperationBatchIndexNotFound(index);
        }
        operationBatch_ = $._operationsBatchMap[$._operationsBatchIdSet.at(index)];
        return operationBatch_;
    }

    /// @dev Return the operationsBatch with the given id
    function operationBatch(bytes32 id) public view returns (OperationBatch memory operationBatch_) {
        TimelockControllerEnumerableStorage storage $ = _getTimelockControllerEnumerableStorage();
        if (!$._operationsBatchIdSet.contains(id)) {
            revert OperationBatchIdNotFound(id);
        }
        operationBatch_ = $._operationsBatchMap[id];
        return operationBatch_;
    }
}
