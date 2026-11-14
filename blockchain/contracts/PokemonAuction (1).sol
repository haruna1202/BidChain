// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract PokemonAuction {
    address public owner;

    uint public cardCount;
    uint public auctionCount;

    // Cấu hình cho phiên mới, đơn vị giây
    uint public shippingPeriod = 3 days;
    uint public responsePeriod = 7 days;
    uint public disputePeriod = 7 days;

    bool private locked;

    enum Status {
        Active,           // 0: Đang đấu giá
        AwaitingShipment, // 1: Chờ gửi hàng
        Shipped,          // 2: Đã gửi hàng
        Completed,        // 3: Đã thanh toán
        Cancelled,        // 4: Đã hủy
        NoBids,           // 5: Không có người đặt
        Disputed,         // 6: Đang tranh chấp
        Refunded          // 7: Đã ghi nhận hoàn tiền
    }

    struct Card {
        address seller;
        bytes32 certificateKey; // Hash đơn vị + mã chứng nhận
        uint profileId;         // Mã hồ sơ trong database
        bytes32 metadataHash;   // Hash thông tin và ảnh
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

        // Lưu cấu hình riêng, tránh đổi điều kiện phiên cũ
        uint shippingTime;
        uint responseTime;
        uint disputeTime;

        uint shippingDeadline;
        uint responseDeadline;
        uint disputeDeadline;

        Status status;
    }

    mapping(uint => Card) public cards;
    mapping(uint => Auction) private auctions;

    // Chặn một chứng nhận có nhiều phiên chưa xử lý xong
    mapping(bytes32 => bool) public certificateBusy;

    // Tiền từng ví được phép rút
    mapping(address => uint) public pendingReturns;

    event CardRegistered(
        uint indexed cardId,
        address indexed seller
    );

    event CardReviewed(uint indexed cardId, bool approved);

    event AuctionCreated(
        uint indexed auctionId,
        uint indexed cardId
    );

    event BidPlaced(
        uint indexed auctionId,
        address indexed bidder,
        uint amount
    );

    event StatusChanged(uint indexed auctionId, Status status);

    event ShipmentMarked(
        uint indexed auctionId,
        bytes32 shippingHash
    );

    event DisputeOpened(
        uint indexed auctionId,
        bytes32 evidenceHash
    );

    event FundsAllocated(
        uint indexed auctionId,
        address indexed recipient,
        uint amount
    );

    event Withdrawn(address indexed to, uint amount);

    event PeriodsUpdated(
        uint shippingTime,
        uint responseTime,
        uint disputeTime
    );

    // Chỉ ví triển khai contract được quản trị
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier validAuction(uint auctionId) {
        require(
            auctionId > 0 && auctionId <= auctionCount,
            "Auction not found"
        );
        _;
    }

    // Ngăn gọi lặp khi contract đang chuyển ETH
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
    }

    // =====================================
    // 1. CAU HINH THOI GIAN
    // =====================================

    // Chỉ áp dụng cho phiên tạo sau khi thay đổi
    function setPeriods(
        uint shippingTime,
        uint responseTime,
        uint disputeTime
    ) public onlyOwner {
        require(
            shippingTime > 0 && shippingTime <= 30 days,
            "Invalid shipping time"
        );
        require(
            responseTime > 0 && responseTime <= 30 days,
            "Invalid response time"
        );
        require(
            disputeTime > 0 && disputeTime <= 30 days,
            "Invalid dispute time"
        );

        shippingPeriod = shippingTime;
        responsePeriod = responseTime;
        disputePeriod = disputeTime;

        emit PeriodsUpdated(
            shippingTime,
            responseTime,
            disputeTime
        );
    }

    // =====================================
    // 2. DANG VA DUYET THE
    // =====================================

    // Ảnh và thông tin chi tiết lưu ngoài blockchain
    function registerCard(
        bytes32 certificateKey,
        uint profileId,
        bytes32 metadataHash
    ) public {
        require(certificateKey != bytes32(0), "Empty certificate");
        require(profileId > 0, "Invalid profile");
        require(metadataHash != bytes32(0), "Empty metadata");

        cardCount++;

        cards[cardCount] = Card({
            seller: msg.sender,
            certificateKey: certificateKey,
            profileId: profileId,
            metadataHash: metadataHash,
            approved: false,
            busy: false
        });

        emit CardRegistered(cardCount, msg.sender);
    }

    // true: duyệt; false: từ chối hoặc thu hồi duyệt
    function reviewCard(
        uint cardId,
        bool approved
    ) public onlyOwner {
        require(
            cardId > 0 && cardId <= cardCount,
            "Card not found"
        );
        require(!cards[cardId].busy, "Card busy");

        cards[cardId].approved = approved;

        emit CardReviewed(cardId, approved);
    }

    // =====================================
    // 3. TAO VA HUY PHIEN
    // =====================================

    function createAuction(
        uint cardId,
        uint startPrice,
        uint bidStep,
        uint durationMinutes
    ) public {
        require(
            cardId > 0 && cardId <= cardCount,
            "Card not found"
        );

        Card storage card = cards[cardId];

        require(msg.sender == card.seller, "Not seller");
        require(card.approved, "Card not approved");
        require(!card.busy, "Card busy");
        require(
            !certificateBusy[card.certificateKey],
            "Certificate busy"
        );
        require(startPrice > 0, "Invalid start price");
        require(bidStep > 0, "Invalid bid step");
        require(
            durationMinutes > 0 && durationMinutes <= 43200,
            "Duration: 1 to 43200 minutes"
        );

        auctionCount++;

        Auction storage auction = auctions[auctionCount];

        auction.cardId = cardId;
        auction.startPrice = startPrice;
        auction.bidStep = bidStep;
        auction.endTime =
            block.timestamp + durationMinutes * 1 minutes;

        auction.shippingTime = shippingPeriod;
        auction.responseTime = responsePeriod;
        auction.disputeTime = disputePeriod;
        auction.status = Status.Active;

        card.busy = true;
        certificateBusy[card.certificateKey] = true;

        emit AuctionCreated(auctionCount, cardId);
    }

    // Chỉ hủy được khi chưa có ai đặt giá
    function cancelAuction(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(
            msg.sender == cards[auction.cardId].seller,
            "Not seller"
        );
        require(auction.status == Status.Active, "Not active");
        require(block.timestamp < auction.endTime, "Time ended");
        require(
            auction.highestBidder == address(0),
            "Already has bids"
        );

        auction.status = Status.Cancelled;
        unlockCard(auction.cardId);

        emit StatusChanged(auctionId, Status.Cancelled);
    }

    // =====================================
    // 4. DAT GIA
    // =====================================

    // Mỗi lượt gửi toàn bộ ETH của giá mới
    function bid(uint auctionId)
        public payable validAuction(auctionId) nonReentrant
    {
        Auction storage auction = auctions[auctionId];

        require(auction.status == Status.Active, "Not active");
        require(block.timestamp < auction.endTime, "Time ended");
        require(
            msg.sender != cards[auction.cardId].seller,
            "Seller cannot bid"
        );

        uint minimumPrice = auction.startPrice;

        if (auction.highestBidder != address(0)) {
            minimumPrice = auction.highestBid + auction.bidStep;
        }

        require(msg.value >= minimumPrice, "Bid too low");

        // Khoản giá cũ được chuyển sang tiền chờ rút
        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] +=
                auction.highestBid;
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = msg.value;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    // =====================================
    // 5. KET THUC PHIEN
    // =====================================

    // Bất kỳ ai cũng gọi được sau khi hết giờ
    function endAuction(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(auction.status == Status.Active, "Not active");
        require(block.timestamp >= auction.endTime, "Not ended");

        if (auction.highestBidder == address(0)) {
            auction.status = Status.NoBids;
            unlockCard(auction.cardId);
        } else {
            auction.status = Status.AwaitingShipment;

            // Tính từ thời điểm hết phiên
            auction.shippingDeadline =
                auction.endTime + auction.shippingTime;
        }

        emit StatusChanged(auctionId, auction.status);
    }

    // =====================================
    // 6. GIAO HANG VA THANH TOAN
    // =====================================

    // Người bán ghi nhận đã gửi hàng
    function markShipped(
        uint auctionId,
        bytes32 shippingHash
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(
            msg.sender == cards[auction.cardId].seller,
            "Not seller"
        );
        require(
            auction.status == Status.AwaitingShipment,
            "Invalid status"
        );
        require(
            block.timestamp < auction.shippingDeadline,
            "Shipping deadline passed"
        );
        require(shippingHash != bytes32(0), "Empty shipping hash");

        auction.status = Status.Shipped;
        auction.responseDeadline =
            block.timestamp + auction.responseTime;

        emit ShipmentMarked(auctionId, shippingHash);
        emit StatusChanged(auctionId, Status.Shipped);
    }

    // Người thắng xác nhận nhận đúng thẻ
    function confirmReceived(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(msg.sender == auction.highestBidder, "Not winner");
        require(auction.status == Status.Shipped, "Not shipped");

        settle(auctionId, true);
    }

    // Người bán không gửi đúng hạn: hoàn người thắng
    function refundUnshipped(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(msg.sender == auction.highestBidder, "Not winner");
        require(
            auction.status == Status.AwaitingShipment,
            "Invalid status"
        );
        require(
            block.timestamp >= auction.shippingDeadline,
            "Not overdue"
        );

        settle(auctionId, false);
    }

    // Hết hạn phản hồi, không có tranh chấp: trả người bán
    function releaseAfterTimeout(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(auction.status == Status.Shipped, "Invalid status");
        require(
            block.timestamp >= auction.responseDeadline,
            "Not overdue"
        );

        settle(auctionId, true);
    }

    // =====================================
    // 7. TRANH CHAP
    // =====================================

    // Người mua mở tranh chấp trong hạn phản hồi
    function openDispute(
        uint auctionId,
        bytes32 evidenceHash
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(msg.sender == auction.highestBidder, "Not winner");
        require(auction.status == Status.Shipped, "Invalid status");
        require(
            block.timestamp < auction.responseDeadline,
            "Response deadline passed"
        );
        require(evidenceHash != bytes32(0), "Empty evidence");

        auction.status = Status.Disputed;
        auction.disputeDeadline =
            block.timestamp + auction.disputeTime;

        emit DisputeOpened(auctionId, evidenceHash);
        emit StatusChanged(auctionId, Status.Disputed);
    }

    // Admin xem bằng chứng bên ngoài rồi quyết định
    // true: trả người bán; false: hoàn người mua
    function resolveDispute(
        uint auctionId,
        bool paySeller
    ) public onlyOwner validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(auction.status == Status.Disputed, "Not disputed");
        require(
            block.timestamp < auction.disputeDeadline,
            "Dispute deadline passed"
        );

        settle(auctionId, paySeller);
    }

    // Chính sách demo: quá hạn admin xử lý thì hoàn người mua
    function refundDisputeTimeout(
        uint auctionId
    ) public validAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(auction.status == Status.Disputed, "Not disputed");
        require(
            block.timestamp >= auction.disputeDeadline,
            "Not overdue"
        );

        settle(auctionId, false);
    }

    // =====================================
    // 8. RUT TIEN VA XEM THONG TIN
    // =====================================

    // Người thua, người được hoàn, người bán đều rút ở đây
    function withdraw() public nonReentrant {
        uint amount = pendingReturns[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        // Xóa trước khi chuyển để tránh rút lặp
        pendingReturns[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit Withdrawn(msg.sender, amount);
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function getAuction(uint auctionId)
        public view validAuction(auctionId)
        returns (Auction memory)
    {
        return auctions[auctionId];
    }

    // =====================================
    // 9. HAM NOI BO
    // =====================================

    // Chốt tiền một lần, sau đó người nhận tự rút
    function settle(uint auctionId, bool paySeller) private {
        Auction storage auction = auctions[auctionId];

        require(
            auction.status == Status.AwaitingShipment ||
            auction.status == Status.Shipped ||
            auction.status == Status.Disputed,
            "Already settled"
        );

        uint amount = auction.highestBid;
        require(amount > 0, "No funds");

        address recipient;

        if (paySeller) {
            recipient = cards[auction.cardId].seller;
            auction.status = Status.Completed;
        } else {
            recipient = auction.highestBidder;
            auction.status = Status.Refunded;
        }

        pendingReturns[recipient] += amount;
        unlockCard(auction.cardId);

        emit FundsAllocated(auctionId, recipient, amount);
        emit StatusChanged(auctionId, auction.status);
    }

    // Đăng bán lại phải được admin kiểm tra lại
    function unlockCard(uint cardId) private {
        Card storage card = cards[cardId];

        card.busy = false;
        card.approved = false;
        certificateBusy[card.certificateKey] = false;
    }
}