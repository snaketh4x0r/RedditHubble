pragma solidity ^0.5.15;

import { AccountTree } from "../AccountTree.sol";

contract TestAccountTree is AccountTree {
    event Return(uint256);
    event Return2(uint256, bool);

    function updateSingle(bytes32 leaf) external returns (uint256) {
        uint256 operationGasCost = gasleft();
        _updateSingle(leaf);
        emit Return(operationGasCost - gasleft());
    }

    function updateBatch(bytes32[BATCH_SIZE] calldata leafs)
        external
        returns (uint256)
    {
        uint256 operationGasCost = gasleft();
        _updateBatch(leafs);
        emit Return(operationGasCost - gasleft());
    }

    function checkInclusion(
        bytes32 leaf,
        uint256 leafIndex,
        bytes32[WITNESS_LENGTH] calldata witness
    ) external returns (uint256, bool) {
        uint256 operationGasCost = gasleft();
        bool s = _checkInclusion(leaf, leafIndex, witness);
        emit Return2(operationGasCost - gasleft(), s);
    }
}
