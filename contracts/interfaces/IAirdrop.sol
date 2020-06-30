pragma solidity ^0.5.15;
pragma experimental ABIEncoderV2;

import {Types} from "../libs/Types.sol";

interface IAirdrop {
    function processDrop(
        Types.Transaction calldata drop,
        Types.AccountMerkleProof calldata _to_merkle_proof
    )
        external
        view
        returns (
            bytes32,
            uint256,
            bool
        );
}