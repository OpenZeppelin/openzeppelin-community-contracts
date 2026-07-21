F-1. Paginated operations(start, end) writes out-of-bounds
(Panic 0x32)   

contracts/governance/TimelockControllerEnumerable.sol Lines: 122-131
and 170-182  
The paginated read functions operations(uint256 start, uint256 end) and
operationsBatch(uint256 start, uint256 end) allocate a return array of length end -
start but then write into it using the loop variable i as the index, which ranges from start to end -
1 rather than from 0 to end - start - 1. Whenever start > 0, the first write lands at index
start, which is outside the allocated array bounds, and Solidity 0.8.x raises Panic(0x32) (array
out-of-bounds). The no-argument overloads work only because they pass start = 0. The single-index
and id-based accessors operation(uint256), operation(bytes32),
operationBatch(uint256), operationBatch(bytes32) are unaffected.
Evidence (verbatim from source)
function operations(uint256 start, uint256 end) public view returns
(Operation[] memory operations_) {
if (start > end || start >= _operationsIdSet.length()) {
revert InvalidIndexRange(start, end);
}
operations_ = new Operation[](end - start);
for (uint256 i = start; i < end; i++) {
operations_[i] = _operationsMap[_operationsIdSet.at(i)]; // BUG: writes at
i, not i-start
}
return operations_;
}
// operationsBatch(start, end) at lines 170-182 has the identical bug:
function operationsBatch(uint256 start, uint256 end) public view returns
(OperationBatch[] memory operationsBatch_) {
if (start > end || start >= _operationsBatchIdSet.length()) {
revert InvalidIndexRange(start, end);
}
operationsBatch_ = new OperationBatch[](end - start);
for (uint256 i = start; i < end; i++) {
operationsBatch_[i] = _operationsBatchMap[_operationsBatchIdSet.at(i)]; //
BUG
}
return operationsBatch_;
}
Impact
The paginated read path is unusable: any caller requesting a range with start > 0 will receive a
revert. Off-chain dashboards, subgraph mirrors, and governance UIs that paginate the operation list
will fail to load pages beyond the first. Because the functions are view, there is no on-chain fund-loss
path; however, the timelock's scheduling, execution, and cancellation paths inherit unchanged from OZ
TimelockController and remain safe. The severity is therefore Medium (functional defect in a
public read API) rather than High.


Recommendation
Replace the loop body to write at the offset index i - start. Concretely: operations_[i -
start] = _operationsMap[_operationsIdSet.at(i)]; and the analogous change in
operationsBatch. Add a unit test that calls operations(1, 3) on a set with at least 3 entries and
asserts it returns 2 elements with the correct ids.
