pragma solidity ^0.5.15;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract BurnAuction {
    using SafeMath for uint256;

    // number of blocks available in slot
    uint32 public blocksPerSlot;
    // Burn Address
    address payable burnAddress;
    // Default Coordinator
    Coordinator public coDefault;
    // number of blocks after contract deployment for genesisBlock number
    uint256 public delayGenesis;
    // First block where the first slot begins
    uint256 public genesisBlock;
    // Maximum rollup transactions: either off-chain or on-chain transactions
    uint256 public maxTx;
    // Min differance between currentslot and auction slots
    uint256 public minNextSlots;
    // Minimum bid to enter the auction
    uint256 public minBid;
    // Min next bid percentage
    uint256 public minNextbid;

    // Coordinator structure
    struct Coordinator {
        // Coordinator Address
        address payable coordinatorAddress;
    }

    // bid structure
    struct Bid {
        // bid amount(onchain) = sumtotalFees + targetProfit(offchain)
        uint256 amount;
        // used to indicate active auction for slot
        bool initialized;
    }

    // mapping to control winner of slot
    mapping(uint256 => Coordinator) public slotWinner;
    // mapping to control bid by slot
    mapping(uint256 => Bid) public slotBid;

    /**
     * @dev Event called when an Coordinator beat the current best bid of an ongoing auction
     */
    event currentBestBid(uint32 slot, uint256 amount, address Coordinator);

    /**
     * @dev BurnAuction Constructor
     * Set first block where the first slot begin
     * @param _maxTx maximum transactions
     * @param _burnAddress burner address
     * @param _blocksPerSlot number of blocks in slot
     * @param _delayGenesis delay genesisBlock by this
     * @param _minBid minimum bid for a auction slot
     * @param _minNextSlots differance between currentslot and auction slot
     */
    constructor(
        uint256 _maxTx,
        address payable _burnAddress,
        uint32 _blocksPerSlot,
        uint256 _delayGenesis,
        uint256 _minBid,
        uint256 _minNextSlots,
        uint256 _minNextbid,
        address payable defaultCoAddress
    ) public {
        genesisBlock = getBlockNumber() + _delayGenesis;
        maxTx = _maxTx;
        burnAddress = _burnAddress;
        blocksPerSlot = _blocksPerSlot;
        delayGenesis = _delayGenesis;
        minBid = _minBid;
        minNextSlots = _minNextSlots;
        minNextbid = _minNextbid;
        coDefault = Coordinator(defaultCoAddress);
    }

    /**
     * @dev Retrieve ether amount to be burned
     * @param slot slot number
     * @param co coordinator instance
     * @param _value amount of ether sent
     * @return  burn amount
     */
    function bid(
        uint32 slot,
        Coordinator memory co,
        uint256 _value
    ) internal returns (uint256) {
        uint256 burnBid = 0;
        uint256 value = _value;
        if (slotBid[slot].initialized) {
            uint256 previousBid = slotBid[slot].amount;
            uint256 nextBid = previousBid.add(
                (previousBid.mul(minNextbid)).div(100)
            );
            require(
                value >= nextBid,
                "bid not enough to outbid current bidder"
            );
            // refund previous bidder
            address payable previousBidder = slotWinner[slot]
                .coordinatorAddress;
            previousBidder.transfer(previousBid);
            // update burn amount
            burnBid = value.sub(previousBid);
        } else {
            // value should be greater than or equal to minBid
            require(value >= minBid, "bid not enough than minimum bid");
            slotBid[slot].initialized = true;
            burnBid = value;
        }
        // update slot winner
        slotWinner[slot] = co;
        // update slot price
        slotBid[slot].amount = value;
        // emit event
        emit currentBestBid(slot, slotBid[slot].amount, co.coordinatorAddress);
        return burnBid;
    }

    /**
     * @dev bid for self
     * @param _slot slot number
     */
    function bidBySelf(uint32 _slot) external payable returns (bool) {
        require(
            _slot >= currentSlot() + minNextSlots,
            "This auction is already closed"
        );
        Coordinator memory co = Coordinator(msg.sender);
        uint256 burnBid = bid(_slot, co, msg.value);
        burnAddress.transfer(burnBid);
        return true;
    }

    /**
     * @dev bid for others using different address arguments
     * @param _slot slot number
     * @param _coordinatorAddress coordinator address of others
     */
    function bidForOthers(uint32 _slot, address payable _coordinatorAddress)
        external
        payable
        returns (bool)
    {
        require(
            _slot >= currentSlot() + minNextSlots,
            "This auction is already closed"
        );
        Coordinator memory co = Coordinator(_coordinatorAddress);
        uint256 burnBid = bid(_slot, co, msg.value);
        burnAddress.transfer(burnBid);
        return true;
    }

    /**
     * @dev Retrieve slot winner
     * @return submitBatchAddress,returnAddress,Coordinator url,bidprice
     */
    function getCurrentWinner() public view returns (address) {
        uint32 querySlot = currentSlot();
        address batchSubmitter = slotWinner[querySlot].coordinatorAddress;
        if (batchSubmitter != address(0x00)) {
            return (batchSubmitter);
        } else {
            return (coDefault.coordinatorAddress);
        }
    }

    /**
     * @dev Calculate slot from block number
     * @param numBlock block number
     * @return slot number
     */
    function block2slot(uint256 numBlock) public view returns (uint32) {
        if (numBlock < genesisBlock) return 0;
        return uint32((numBlock - genesisBlock) / (blocksPerSlot));
    }

    /**
     * @dev Retrieve current slot
     * @return slot number
     */
    function currentSlot() public view returns (uint32) {
        return block2slot(getBlockNumber());
    }

    /**
     * @dev Retrieve block number
     * @return current block number
     */
    function getBlockNumber() public view returns (uint256) {
        return block.number;
    }

    /**
     * @dev check if given address winner of slot or not
     * @param _slot slot number
     * @param _winner winer address to be checked
     * @return bool
     */
    function checkWinner(uint256 _slot, address _winner)
        public
        view
        returns (bool)
    {
        if (
            slotBid[_slot].initialized != true &&
            coDefault.coordinatorAddress == _winner
        ) return true;
        address coordinator = slotWinner[_slot].coordinatorAddress;
        if (coordinator == _winner) {
            return true;
        } else {
            return false;
        }
    }
}
