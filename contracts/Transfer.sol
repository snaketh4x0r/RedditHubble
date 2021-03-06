pragma solidity ^0.5.15;
pragma experimental ABIEncoderV2;
import { FraudProofHelpers } from "./FraudProof.sol";
import { Types } from "./libs/Types.sol";
import { RollupUtils } from "./libs/RollupUtils.sol";
import { MerkleTreeUtilsLib } from "./MerkleTreeUtils.sol";

import { BLS } from "./libs/BLS.sol";
import { Tx } from "./libs/Tx.sol";
import { MerkleTreeUtilsLib } from "./MerkleTreeUtils.sol";

contract Transfer is FraudProofHelpers {
    using Tx for bytes;

    uint256 constant MASK_4BYTES = 0xffffffff;
    uint256 constant MASK_1BYTES = 0xff;
    uint256 constant OFF_TX_TYPE = 32;
    uint256 constant OFF_NONCE = 33;
    uint256 constant OFF_TX_DATA = 37;
    // [TX_TYPE<1>|nonce<4>|tx<16>]
    uint256 constant MSG_LEN_0 = 21;
    uint256 constant TX_LEN_0 = 16;

    function checkSignature(
        uint256[2] memory signature,
        Types.SignatureProof memory proof,
        bytes32 stateRoot,
        bytes32 accountRoot,
        bytes32 domain,
        bytes memory txs
    ) public view returns (Types.ErrorCode) {
        uint256 batchSize = txs.transfer_size();
        uint256[2][] memory messages = new uint256[2][](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 signerStateID;
            // solium-disable-next-line security/no-inline-assembly
            assembly {
                signerStateID := and(
                    mload(add(add(txs, mul(i, TX_LEN_0)), 4)),
                    MASK_4BYTES
                )
            }

            // check state inclustion
            require(
                MerkleTreeUtilsLib.verifyLeaf(
                    stateRoot,
                    RollupUtils.HashFromAccount(proof.stateAccounts[i]),
                    signerStateID,
                    proof.stateWitnesses[i]
                ),
                "Rollup: state inclusion signer"
            );

            // check pubkey inclusion
            uint256 signerAccountID = proof.stateAccounts[i].ID;
            require(
                MerkleTreeUtilsLib.verifyLeaf(
                    accountRoot,
                    keccak256(abi.encodePacked(proof.pubkeys[i])),
                    signerAccountID,
                    proof.pubkeyWitnesses[i]
                ),
                "Rollup: account does not exists"
            );

            // construct the message
            signerAccountID = signerAccountID <<= 224;
            require(proof.stateAccounts[i].nonce > 0, "Rollup: zero nonce");
            uint256 nonce = proof.stateAccounts[i].nonce <<= 224;
            bytes memory txMsg = new bytes(MSG_LEN_0);

            // solium-disable-next-line security/no-inline-assembly
            assembly {
                mstore8(add(txMsg, OFF_TX_TYPE), 1)
                mstore(add(txMsg, OFF_NONCE), sub(nonce, 1))
                mstore(
                    add(txMsg, OFF_TX_DATA),
                    mload(add(add(txs, 32), mul(TX_LEN_0, i)))
                )
            }
            // make the message
            messages[i] = BLS.hashToPoint(domain, txMsg);
        }
        if (!BLS.verifyMultiple(signature, proof.pubkeys, messages)) {
            return Types.ErrorCode.BadSignature;
        }
        return Types.ErrorCode.NoError;
    }

    /**
     * @notice processBatch processes a whole batch
     * @return returns updatedRoot, txRoot and if the batch is valid or not
     * */
    function processTransferBatch(
        bytes32 stateRoot,
        bytes memory txs,
        Types.AccountMerkleProof[] memory accountProofs
    ) public pure returns (bytes32, bool) {
        uint256 length = txs.transfer_size();

        bool isTxValid;

        for (uint256 i = 0; i < length; i++) {
            // call process tx update for every transaction to check if any
            // tx evaluates correctly
            (stateRoot, , , , isTxValid) = processTx(
                stateRoot,
                txs.transfer_decode(i),
                accountProofs[i * 2],
                accountProofs[i * 2 + 1]
            );

            if (!isTxValid) {
                break;
            }
        }

        return (stateRoot, !isTxValid);
    }

    /**
     * @notice processTx processes a transactions and returns the updated balance tree
     *  and the updated leaves
     * conditions in require mean that the dispute be declared invalid
     * if conditons evaluate if the coordinator was at fault
     * @return Total number of batches submitted onchain
     */
    function processTx(
        bytes32 stateRoot,
        Tx.Transfer memory _tx,
        Types.AccountMerkleProof memory fromAccountProof,
        Types.AccountMerkleProof memory toAccountProof
    )
        public
        pure
        returns (
            bytes32,
            bytes memory,
            bytes memory,
            Types.ErrorCode,
            bool
        )
    {
        require(
            MerkleTreeUtilsLib.verifyLeaf(
                stateRoot,
                RollupUtils.HashFromAccount(fromAccountProof.account),
                _tx.fromIndex,
                fromAccountProof.siblings
            ),
            "Transfer: sender does not exist"
        );

        Types.ErrorCode err_code = validateTxBasic(
            _tx.amount,
            fromAccountProof.account
        );
        if (err_code != Types.ErrorCode.NoError)
            return (ZERO_BYTES32, "", "", err_code, false);

        if (
            fromAccountProof.account.tokenType !=
            toAccountProof.account.tokenType
        )
            return (
                ZERO_BYTES32,
                "",
                "",
                Types.ErrorCode.BadFromTokenType,
                false
            );

        bytes32 newRoot;
        bytes memory new_from_account;
        bytes memory new_to_account;

        (new_from_account, newRoot) = ApplyTransferTxSender(
            fromAccountProof,
            _tx
        );

        require(
            MerkleTreeUtilsLib.verifyLeaf(
                newRoot,
                RollupUtils.HashFromAccount(toAccountProof.account),
                _tx.toIndex,
                toAccountProof.siblings
            ),
            "Transfer: receiver does not exist"
        );

        (new_to_account, newRoot) = ApplyTransferTxReceiver(
            toAccountProof,
            _tx
        );

        return (
            newRoot,
            new_from_account,
            new_to_account,
            Types.ErrorCode.NoError,
            true
        );
    }

    function ApplyTransferTxSender(
        Types.AccountMerkleProof memory _merkle_proof,
        Tx.Transfer memory _tx
    ) public pure returns (bytes memory updatedAccount, bytes32 newRoot) {
        Types.UserAccount memory account = _merkle_proof.account;
        account = RemoveTokensFromAccount(account, _tx.amount);
        account.nonce++;
        bytes memory accountInBytes = RollupUtils.BytesFromAccount(account);
        newRoot = MerkleTreeUtilsLib.rootFromWitnesses(
            keccak256(accountInBytes),
            _tx.fromIndex,
            _merkle_proof.siblings
        );
        return (accountInBytes, newRoot);
    }

    function ApplyTransferTxReceiver(
        Types.AccountMerkleProof memory _merkle_proof,
        Tx.Transfer memory _tx
    ) public pure returns (bytes memory updatedAccount, bytes32 newRoot) {
        Types.UserAccount memory account = _merkle_proof.account;
        account = AddTokensToAccount(account, _tx.amount);
        bytes memory accountInBytes = RollupUtils.BytesFromAccount(account);
        newRoot = MerkleTreeUtilsLib.rootFromWitnesses(
            keccak256(accountInBytes),
            _tx.toIndex,
            _merkle_proof.siblings
        );
        return (accountInBytes, newRoot);
    }
}
