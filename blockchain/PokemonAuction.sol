// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title PokemonAuction
/// @notice Sepolia demo auction for graded Pokemon cards.
/// @dev Auction proceeds and outbid refunds use pull payments through withdraw().
contract PokemonAuction {
    address public owner;
    uint public cardCount;
    uint public auctionCount;
    bool private locked;

    enum Status {
        Active,
        Completed,
        Cancelled,
        NoBids
    }

    struct Card {
        address seller;
        bytes32 certificateKey;
        uint profileId;
        bytes32 metadataHash;
        bool reviewed;
        bool approved;
        bool busy;
    }

    struct Auction {
        uint cardId;
        uint startPrice;
        uint bidStep;
        uint endTime;
        address highestBidder;
        uint highestBid;
        Status status;
    }

    mapping(uint => Card) public cards;
    mapping(uint => Auction) private auctions;
    mapping(bytes32 => bool) public certificateBusy;
    mapping(address => uint) public pendingReturns;

    event CardRegistered(uint indexed cardId, address indexed seller);
    event CardReviewed(uint indexed cardId, bool approved);
    event AuctionCreated(uint indexed auctionId, uint indexed cardId);
    event BidPlaced(uint indexed auctionId, address indexed bidder, uint amount);
    event StatusChanged(uint indexed auctionId, Status status);
    event FundsAllocated(uint indexed auctionId, address indexed recipient, uint amount);
    event Withdrawn(address indexed to, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier validAuction(uint auctionId) {
        require(auctionId > 0 && auctionId <= auctionCount, "Auction not found");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Seller submits a card profile hash; image files stay in the API/database.
    function registerCard(
        bytes32 certificateKey,
        uint profileId,
        bytes32 metadataHash
    ) external {
        require(certificateKey != bytes32(0), "Empty certificate");
        require(profileId > 0, "Invalid profile");
        require(metadataHash != bytes32(0), "Empty metadata");

        cardCount++;
        cards[cardCount] = Card({
            seller: msg.sender,
            certificateKey: certificateKey,
            profileId: profileId,
            metadataHash: metadataHash,
            reviewed: false,
            approved: false,
            busy: false
        });

        emit CardRegistered(cardCount, msg.sender);
    }

    /// @notice Only the contract owner/reviewer can approve or reject a card.
    function reviewCard(uint cardId, bool approved) external onlyOwner {
        require(cardId > 0 && cardId <= cardCount, "Card not found");
        require(!cards[cardId].busy, "Card busy");

        cards[cardId].reviewed = true;
        cards[cardId].approved = approved;
        emit CardReviewed(cardId, approved);
    }

    function createAuction(
        uint cardId,
        uint startPrice,
        uint bidStep,
        uint durationMinutes
    ) external {
        require(cardId > 0 && cardId <= cardCount, "Card not found");
        Card storage card = cards[cardId];
        require(msg.sender == card.seller, "Not seller");
        require(card.reviewed && card.approved, "Card not approved");
        require(!card.busy, "Card busy");
        require(!certificateBusy[card.certificateKey], "Certificate busy");
        require(startPrice > 0, "Invalid start price");
        require(bidStep > 0, "Invalid bid step");
        require(durationMinutes > 0 && durationMinutes <= 43200, "Duration: 1 to 43200 minutes");

        auctionCount++;
        auctions[auctionCount] = Auction({
            cardId: cardId,
            startPrice: startPrice,
            bidStep: bidStep,
            endTime: block.timestamp + durationMinutes * 1 minutes,
            highestBidder: address(0),
            highestBid: 0,
            status: Status.Active
        });

        card.busy = true;
        certificateBusy[card.certificateKey] = true;
        emit AuctionCreated(auctionCount, cardId);
    }

    /// @notice A seller may cancel only an active auction with no bids.
    function cancelAuction(uint auctionId) external validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == cards[auction.cardId].seller, "Not seller");
        require(auction.status == Status.Active, "Not active");
        require(block.timestamp < auction.endTime, "Time ended");
        require(auction.highestBidder == address(0), "Already has bids");

        auction.status = Status.Cancelled;
        _unlockCard(auction.cardId);
        emit StatusChanged(auctionId, auction.status);
    }

    /// @notice Each bid escrows the full amount; an outbid user gets a withdrawable refund.
    function bid(uint auctionId) external payable validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.status == Status.Active, "Not active");
        require(block.timestamp < auction.endTime, "Time ended");
        require(msg.sender != cards[auction.cardId].seller, "Seller cannot bid");

        uint minimumPrice = auction.highestBidder == address(0)
            ? auction.startPrice
            : auction.highestBid + auction.bidStep;
        require(msg.value >= minimumPrice, "Bid too low");

        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] += auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /// @notice Anyone can close an expired auction. The seller then withdraws the winning bid.
    function endAuction(uint auctionId) external validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.status == Status.Active, "Not active");
        require(block.timestamp >= auction.endTime, "Not ended");

        if (auction.highestBidder == address(0)) {
            auction.status = Status.NoBids;
        } else {
            address seller = cards[auction.cardId].seller;
            uint amount = auction.highestBid;
            auction.status = Status.Completed;
            pendingReturns[seller] += amount;
            emit FundsAllocated(auctionId, seller, amount);
        }

        _unlockCard(auction.cardId);
        emit StatusChanged(auctionId, auction.status);
    }

    /// @notice Withdraw a seller payout or an outbid refund to the connected wallet.
    function withdraw() external nonReentrant {
        uint amount = pendingReturns[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingReturns[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to send Ether");
        emit Withdrawn(msg.sender, amount);
    }

    function getBalance() external view returns (uint) {
        return address(this).balance;
    }

    function getAuction(uint auctionId)
        external
        view
        validAuction(auctionId)
        returns (Auction memory)
    {
        return auctions[auctionId];
    }

    function _unlockCard(uint cardId) private {
        Card storage card = cards[cardId];
        card.busy = false;
        certificateBusy[card.certificateKey] = false;
    }
}
