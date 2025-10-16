// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TimelockControllerEnumerableMock} from "./TimelockControllerEnumerableMock.t.sol";
import {
    TimelockControllerEnumerable
} from "@openzeppelin/community-contracts/governance/TimelockControllerEnumerable.sol";

contract TimelockControllerEnumerableTest is Test {
    TimelockControllerEnumerableMock public timelockControllerEnumerable;

    event Call();

    function setUp() public {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(this);
        executors[0] = address(this);
        uint256 minDelay = 1 days;
        timelockControllerEnumerable = new TimelockControllerEnumerableMock(minDelay, proposers, executors, address(0));
    }

    function call() external {
        emit Call();
    }

    function test_schedule() public {
        timelockControllerEnumerable.schedule(
            address(this),
            0,
            abi.encodeCall(this.call, ()),
            bytes32(0),
            bytes32(0),
            1 days
        );
        assertEq(timelockControllerEnumerable.operationsCount(), 1);
        TimelockControllerEnumerable.Operation memory operation = timelockControllerEnumerable.operation(uint256(0));
        assertEq(operation.target, address(this));
        assertEq(operation.value, 0);
        assertEq(operation.data, abi.encodeCall(this.call, ()));
        assertEq(operation.predecessor, bytes32(0));
        assertEq(operation.salt, bytes32(0));
        assertEq(operation.delay, 1 days);
        bytes32 id = timelockControllerEnumerable.hashOperation(
            address(this),
            0,
            abi.encodeCall(this.call, ()),
            bytes32(0),
            bytes32(0)
        );
        operation = timelockControllerEnumerable.operation(id);
        assertEq(operation.target, address(this));
        assertEq(operation.value, 0);
        assertEq(operation.data, abi.encodeCall(this.call, ()));
        assertEq(operation.predecessor, bytes32(0));
        assertEq(operation.salt, bytes32(0));
        assertEq(operation.delay, 1 days);
    }

    function test_operations() public {
        test_schedule();
        TimelockControllerEnumerable.Operation[] memory operations = timelockControllerEnumerable.operations(0, 1);
        assertEq(operations.length, 1);
        assertEq(operations[0].target, address(this));
        assertEq(operations[0].value, 0);
        assertEq(operations[0].data, abi.encodeCall(this.call, ()));
        assertEq(operations[0].predecessor, bytes32(0));
        assertEq(operations[0].salt, bytes32(0));
        assertEq(operations[0].delay, 1 days);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.InvalidIndexRange.selector, 2, 1));
        timelockControllerEnumerable.operations(2, 1);

        operations = timelockControllerEnumerable.operations();
        assertEq(operations.length, 1);
        assertEq(operations[0].target, address(this));
        assertEq(operations[0].value, 0);
        assertEq(operations[0].data, abi.encodeCall(this.call, ()));
        assertEq(operations[0].predecessor, bytes32(0));
        assertEq(operations[0].salt, bytes32(0));
        assertEq(operations[0].delay, 1 days);
    }

    function test_schedule_execute() public {
        test_schedule();
        TimelockControllerEnumerable.Operation memory operation = timelockControllerEnumerable.operation(uint256(0));
        bytes32 id = timelockControllerEnumerable.hashOperation(
            operation.target,
            operation.value,
            operation.data,
            operation.predecessor,
            operation.salt
        );
        assertEq(timelockControllerEnumerable.isOperationPending(id), true);
        vm.warp(block.timestamp + operation.delay);
        timelockControllerEnumerable.execute(
            operation.target,
            operation.value,
            operation.data,
            operation.predecessor,
            operation.salt
        );
        assertEq(timelockControllerEnumerable.isOperationPending(id), false);
    }

    function test_scheduleBatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = address(this);
        values[0] = 0;
        payloads[0] = abi.encodeCall(this.call, ());
        timelockControllerEnumerable.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 1 days);
        assertEq(timelockControllerEnumerable.operationsBatchCount(), 1);
        TimelockControllerEnumerable.OperationBatch memory operationBatch = timelockControllerEnumerable.operationBatch(
            uint256(0)
        );
        assertEq(operationBatch.targets[0], address(this));
        assertEq(operationBatch.values[0], 0);
        assertEq(operationBatch.payloads[0], abi.encodeCall(this.call, ()));
        assertEq(operationBatch.predecessor, bytes32(0));
        assertEq(operationBatch.salt, bytes32(0));
        assertEq(operationBatch.delay, 1 days);
        bytes32 id = timelockControllerEnumerable.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));
        operationBatch = timelockControllerEnumerable.operationBatch(id);
        assertEq(operationBatch.targets[0], address(this));
        assertEq(operationBatch.values[0], 0);
        assertEq(operationBatch.payloads[0], abi.encodeCall(this.call, ()));
        assertEq(operationBatch.predecessor, bytes32(0));
        assertEq(operationBatch.salt, bytes32(0));
        assertEq(operationBatch.delay, 1 days);
    }

    function test_operationsBatch() public {
        test_scheduleBatch();
        TimelockControllerEnumerable.OperationBatch[] memory operationBatches = timelockControllerEnumerable
            .operationsBatch(0, 1);
        assertEq(operationBatches.length, 1);
        assertEq(operationBatches[0].targets[0], address(this));
        assertEq(operationBatches[0].values[0], 0);
        assertEq(operationBatches[0].payloads[0], abi.encodeCall(this.call, ()));
        assertEq(operationBatches[0].predecessor, bytes32(0));
        assertEq(operationBatches[0].salt, bytes32(0));
        assertEq(operationBatches[0].delay, 1 days);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.InvalidIndexRange.selector, 2, 1));
        timelockControllerEnumerable.operationsBatch(2, 1);

        operationBatches = timelockControllerEnumerable.operationsBatch();
        assertEq(operationBatches.length, 1);
        assertEq(operationBatches[0].targets[0], address(this));
        assertEq(operationBatches[0].values[0], 0);
        assertEq(operationBatches[0].payloads[0], abi.encodeCall(this.call, ()));
        assertEq(operationBatches[0].predecessor, bytes32(0));
        assertEq(operationBatches[0].salt, bytes32(0));
        assertEq(operationBatches[0].delay, 1 days);
    }

    function test_scheduleBatch_execute() public {
        test_scheduleBatch();
        TimelockControllerEnumerable.OperationBatch memory operationBatch = timelockControllerEnumerable.operationBatch(
            uint256(0)
        );
        bytes32 id = timelockControllerEnumerable.hashOperationBatch(
            operationBatch.targets,
            operationBatch.values,
            operationBatch.payloads,
            operationBatch.predecessor,
            operationBatch.salt
        );
        assertEq(timelockControllerEnumerable.isOperationPending(id), true);
        vm.warp(block.timestamp + operationBatch.delay);
        timelockControllerEnumerable.executeBatch(
            operationBatch.targets,
            operationBatch.values,
            operationBatch.payloads,
            operationBatch.predecessor,
            operationBatch.salt
        );
        assertEq(timelockControllerEnumerable.isOperationPending(id), false);
    }

    function test_cancel_schedule() public {
        timelockControllerEnumerable.schedule(
            address(this),
            0,
            abi.encodeCall(this.call, ()),
            bytes32(0),
            bytes32(0),
            1 days
        );
        assertEq(timelockControllerEnumerable.operationsCount(), 1);
        bytes32 id = timelockControllerEnumerable.hashOperation(
            address(this),
            0,
            abi.encodeCall(this.call, ()),
            bytes32(0),
            bytes32(0)
        );
        timelockControllerEnumerable.cancel(id);
        assertEq(timelockControllerEnumerable.operationsCount(), 0);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.OperationIdNotFound.selector, id));
        timelockControllerEnumerable.operation(id);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.OperationIndexNotFound.selector, 0));
        timelockControllerEnumerable.operation(uint256(0));
    }

    function test_cancel_scheduleBatch() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory payloads = new bytes[](1);
        targets[0] = address(this);
        values[0] = 0;
        payloads[0] = abi.encodeCall(this.call, ());
        timelockControllerEnumerable.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), 1 days);
        assertEq(timelockControllerEnumerable.operationsBatchCount(), 1);
        bytes32 id = timelockControllerEnumerable.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));
        timelockControllerEnumerable.cancel(id);
        assertEq(timelockControllerEnumerable.operationsBatchCount(), 0);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.OperationBatchIdNotFound.selector, id));
        timelockControllerEnumerable.operationBatch(id);
        vm.expectRevert(abi.encodeWithSelector(TimelockControllerEnumerable.OperationBatchIndexNotFound.selector, 0));
        timelockControllerEnumerable.operationBatch(uint256(0));
    }
}
