# PokéVault — React, Express, MySQL và Ethereum Sepolia

Website đấu giá C2C thẻ Pokémon. Người bán đăng hồ sơ thẻ đã thẩm định; ví owner duyệt; người bán tạo phiên; người mua đặt giá bằng Sepolia ETH. Contract giữ tiền, hoàn khoản đặt của người bị vượt giá và ghi khoản thắng cho người bán khi phiên kết thúc. Không có bước giao hàng.

## Chạy trên máy cá nhân với XAMPP

1. Cài Node.js và XAMPP. Trong XAMPP Control Panel, bật **MySQL**.
2. Mở `http://localhost/phpmyadmin`, tab **Import**, rồi nhập `database/schema.sql` để tạo database `pokevault` và bảng `cards`.
3. Tạo backend env: `Copy-Item .env.server.example .env.server`. Với XAMPP MySQL mặc định, dùng user `root`; để password trống nếu tài khoản root của bạn không có mật khẩu.
4. Deploy **contract mới** ở `../blockchain/PokemonAuction.sol` lên Sepolia: mở Remix, tạo file Solidity và dán nội dung contract; chọn compiler Solidity 0.8.17 trở lên; ở **Deploy & Run Transactions** chọn **Injected Provider - MetaMask**, xác nhận MetaMask đang ở Sepolia, nhấn **Deploy** và xác nhận giao dịch. Sau khi deploy xong, sao chép địa chỉ contract mới. Tạo `.env.local` từ `.env.example`, điền địa chỉ mới vào `VITE_CONTRACT_ADDRESS`.
5. Mở terminal thứ nhất tại `frontend`, chạy `npm.cmd install`, rồi `npm.cmd run api`.
6. Mở terminal thứ hai tại `frontend`, chạy `npm.cmd run dev`.
7. Mở `http://localhost:4000/api/health`; cần thấy `{"ok":true,"database":"pokevault"}`. Sau đó mở địa chỉ Vite hiện trong terminal.

Giữ hai terminal chạy. Khi sửa `.env.local` hoặc `.env.server`, khởi động lại tiến trình liên quan. API tự tạo `server/uploads` khi khởi động. Ảnh/chứng nhận được lưu ở đó; nếu chuyển sang máy khác thì phải dùng chung API và thư mục upload hoặc chuyển file sang nơi lưu trữ chung.

## MetaMask và vai trò

- Chọn mạng Sepolia trong MetaMask.
- **Người dùng C2C:** một ví có thể vừa bán vừa mua; gửi hồ sơ thẻ, tạo phiên và đặt giá.
- **Kiểm định viên:** là ví deploy contract mới (owner). Kết nối ví này để thấy hàng chờ, thông báo số hồ sơ mới và mở ảnh/chứng nhận.
- `.env.local` chứa địa chỉ contract công khai. Không đặt private key hay mật khẩu tại biến `VITE_*`.

## Tiền và kết thúc phiên

- Khi một người đặt giá cao hơn, khoản đặt trước của người bị vượt trở thành khoản có thể rút về chính ví đó.
- Sau khi hết giờ, bất kỳ ví nào có thể bấm **Kết thúc phiên**. Contract chuyển tiền thắng vào khoản có thể rút của người bán.
- Người bán kết nối đúng ví và bấm **Rút ETH khả dụng** để nhận tiền về MetaMask. Đây là giao dịch blockchain nên MetaMask cần xác nhận và tốn gas Sepolia.
- Nếu chưa có ai đặt giá, phiên kết thúc với trạng thái không có người đặt; không phát sinh tiền bán.

## MySQL và hồ sơ ảnh

- Blockchain lưu mã hồ sơ và hash; ảnh không nằm trong contract.
- Express nhận ba file (mặt trước, mặt sau, chứng nhận) và lưu file dưới `server/uploads`; MySQL lưu metadata và đường dẫn file.
- Nếu đồng bộ báo thiếu file cũ, vào **Tài khoản → Thẻ của tôi → Đồng bộ hồ sơ vào MySQL**. Thao tác cần còn bản gốc của file trong trình duyệt đã đăng ký; nếu không còn, đăng ký lại hoặc chọn lại ảnh/chứng nhận trong hồ sơ mới.
- Cả seller và reviewer phải truy cập cùng máy chủ API/MySQL để xem cùng bộ ảnh. Vite proxy chuyển `/api` và `/uploads` tới Express cổng 4000.

## Contract đã deploy trước đó

Địa chỉ cũ `0x35D1515F5fb2Ecd9EB66398d9969e2930f942Edd` không thể được thay đổi tại chỗ và contract cũ vẫn áp dụng quy trình giao hàng/xác nhận. Bản Solidity/ABI trong gói này bỏ bước giao hàng, nên cần deploy contract mới và thay `VITE_CONTRACT_ADDRESS` bằng địa chỉ mới. Thẻ, phiên và số dư escrow cũ không tự chuyển sang contract mới. Người bị vượt giá ở contract cũ cần rút khoản hoàn bằng giao diện/ABI cũ; người đang thắng ở contract cũ phải hoàn tất quy trình cũ để nhận tiền.

## Lưu ý demo

API demo chưa xác thực chữ ký ví cho endpoint metadata và lưu file cục bộ; chỉ dùng trong môi trường thử nghiệm. Sepolia ETH là token thử nghiệm, không có giá trị như ETH thật.
