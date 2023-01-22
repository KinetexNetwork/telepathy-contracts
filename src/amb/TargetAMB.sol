pragma solidity 0.8.14;
pragma experimental ABIEncoderV2;

import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "./libraries/MerklePatriciaTrie.sol";
import "src/lightclient/libraries/SimpleSerialize.sol";
import "src/amb/interfaces/IAMB.sol";
import "forge-std/console.sol";

/// @title Target Arbitrary Message Bridge
/// @author Succinct Labs
/// @notice Executes the messages sent from the source chain on the target chain.
contract TargetAMB is IReciever, ReentrancyGuard {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /// @notice The reference light client contract.
    ILightClient public lightClient;

    /// @notice Mapping between a message root and its status.
    mapping(bytes32 => MessageStatus) public messageStatus;

    /// @notice Address of the SourceAMB on the source chain.
    address public sourceAMB;

    uint256 internal constant HISTORICAL_ROOTS_LIMIT = 16777216;
    uint256 internal constant SLOTS_PER_HISTORICAL_ROOT = 8192;

    constructor(address _lightClient, address _sourceAMB) {
        lightClient = ILightClient(_lightClient);
        sourceAMB = _sourceAMB;
    }

    /// @notice Executes a message given a storage proof.
    /// @param slot Specifies which execution state root should be read from the light client.
    /// @param messageBytes The message we want to execute provided as bytes.
    /// @param accountProof Used to prove the SourceAMB's state root.
    /// @param storageProof Used to prove the existence of the message root inside the SourceAMB.
    function executeMessage(
        uint64 slot,
        bytes calldata messageBytes,
        bytes[] calldata accountProof,
        bytes[] calldata storageProof
    ) external nonReentrant {
        Message memory message;
        (
            message.nonce,
            message.sender,
            message.receiver,
            message.chainId,
            message.gasLimit,
            message.data
        ) = abi.decode(messageBytes, (uint256, address, address, uint16, uint256, bytes));
        bytes32 messageRoot = keccak256(messageBytes);

        if (messageStatus[messageRoot] != MessageStatus.NOT_EXECUTED) {
            revert("Message already executed.");
        } else if (message.chainId != block.chainid) {
            revert("Wrong chain.");
        }

        {
            bytes32 executionStateRoot = lightClient.executionStateRoots(slot);
            bytes32 storageRoot = MPT.verifyAccount(accountProof, sourceAMB, executionStateRoot);
            bytes32 slotKey = keccak256(abi.encode(keccak256(abi.encode(message.nonce, 0))));
            uint256 slotValue = MPT.verifyStorage(slotKey, storageRoot, storageProof);

            if (bytes32(slotValue) != messageRoot) {
                revert("Invalid message hash.");
            }
        }

        bool status;
        if ((gasleft() * 63) / 64 <= message.gasLimit + 40000) {
            revert("Insufficient gas");
        } else {
            bytes memory receiveCall = abi.encodeWithSignature(
                "receiveSuccinct(address,bytes)", message.sender, message.data
            );
            (status,) = message.receiver.call{gas: message.gasLimit}(receiveCall);
        }

        if (status) {
            messageStatus[messageRoot] = MessageStatus.EXECUTION_SUCCEEDED;
        } else {
            messageStatus[messageRoot] = MessageStatus.EXECUTION_FAILED;
        }

        emit ExecutedMessage(message.nonce, messageRoot, messageBytes, status);
    }

    /// @notice Executes a message given an event proof.
    /// @param srcSlotTxSlotPack The slot where we want to read the header from and the slot where
    ///                          the tx executed, packed as two uint64s.
    /// @param messageBytes The message we want to execute provided as bytes.
    /// @param receiptsRootProof A merkle proof proving the receiptsRoot in the block header.
    /// @param receiptsRoot The receipts root which contains our "SentMessage" event.
    /// @param txIndexRLPEncoded The index of our transaction inside the block RLP encoded.
    /// @param logIndex The index of the event in our transaction.
    function executeMessageFromLog(
        bytes calldata srcSlotTxSlotPack,
        bytes calldata messageBytes,
        bytes32[] calldata receiptsRootProof,
        bytes32 receiptsRoot,
        bytes[] calldata receiptProof,
        bytes memory txIndexRLPEncoded,
        uint256 logIndex
    ) external nonReentrant {
        // verify receiptsRoot against the light client header root
        {
            (uint64 srcSlot, uint64 txSlot) = abi.decode(srcSlotTxSlotPack, (uint64, uint64));
            bytes32 headerRoot = lightClient.headers(srcSlot);
            require(headerRoot != bytes32(0), "TrustlessAMB: headerRoot is missing");

            uint256 index;
            if (txSlot == srcSlot) {
                index = 8 + 3;
                index = index * 2 ** 9 + 387;
            } else if (txSlot + SLOTS_PER_HISTORICAL_ROOT <= srcSlot) {
                index = 8 + 3;
                index = index * 2 ** 5 + 7;
                index = index * 2 + 0;
                index = index * HISTORICAL_ROOTS_LIMIT + txSlot / SLOTS_PER_HISTORICAL_ROOT;
                index = index * 2 + 1;
                index = index * SLOTS_PER_HISTORICAL_ROOT + txSlot % SLOTS_PER_HISTORICAL_ROOT;
                index = index * 2 ** 9 + 387;
            } else if (txSlot < srcSlot) {
                index = 8 + 3;
                index = index * 2 ** 5 + 6;
                index = index * SLOTS_PER_HISTORICAL_ROOT + txSlot % SLOTS_PER_HISTORICAL_ROOT;
                index = index * 2 ** 9 + 387;
            } else {
                revert("TrustlessAMB: invalid target slot");
            }
            // TODO we could reduce gas costs by calling `restoreMerkleRoot` here
            // and not passing in the receiptsRoot
            bool isValid =
                SSZ.isValidMerkleBranch(receiptsRoot, index, receiptsRootProof, headerRoot);
            require(isValid, "TrustlessAMB: invalid receipts root proof");
        }

        Message memory message;
        (
            message.nonce,
            message.sender,
            message.receiver,
            message.chainId,
            message.gasLimit,
            message.data
        ) = abi.decode(messageBytes, (uint256, address, address, uint16, uint256, bytes));
        bytes32 messageRoot = keccak256(messageBytes);

        if (messageStatus[messageRoot] != MessageStatus.NOT_EXECUTED) {
            revert("Message already executed.");
        } else if (message.chainId != block.chainid) {
            revert("Wrong chain.");
        }

        {
            // bytes memory key = rlpIndex(txIndex); // TODO maybe we can save calldata by
            // passing in the txIndex and rlp encode it here
            bytes32 receiptMessageRoot = MPT.verifyAMBReceipt(
                receiptProof, receiptsRoot, txIndexRLPEncoded, logIndex, sourceAMB
            );
            require(receiptMessageRoot == messageRoot, "Invalid message hash.");
        }

        bool status;
        if ((gasleft() * 63) / 64 <= message.gasLimit + 40000) {
            revert("Insufficient gas");
        } else {
            bytes memory recieveCall = abi.encodeWithSignature(
                "receiveSuccinct(address,bytes)", message.sender, message.data
            );
            (status,) = message.receiver.call{gas: message.gasLimit}(recieveCall);
        }

        if (status) {
            messageStatus[messageRoot] = MessageStatus.EXECUTION_SUCCEEDED;
        } else {
            messageStatus[messageRoot] = MessageStatus.EXECUTION_FAILED;
        }

        emit ExecutedMessage(message.nonce, messageRoot, messageBytes, status);
    }
}
