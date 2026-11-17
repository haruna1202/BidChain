# BidChain — PokéVault C2C Auction

Project đấu giá C2C thẻ Pokémon đã thẩm định, gồm smart contract Solidity trên Sepolia, frontend React/Vite + ethers.js/MetaMask, API Express và MySQL.

## Thành phần

- `blockchain/PokemonAuction.sol`: contract hiện tại. Không có quy trình giao hàng; bidder bị vượt có thể rút tiền hoàn, người bán rút tiền thắng sau khi phiên được kết thúc.
- `blockchain/PokemonAuctionABI.json`: ABI khớp với contract hiện tại.
- `frontend/`: giao diện, API, schema MySQL và hướng dẫn chạy.

## Quan trọng: cần deploy contract mới

Contract cũ tại `0x35D1515F5fb2Ecd9EB66398d9969e2930f942Edd` không thể sửa sau khi deploy. Nó vẫn giữ quy trình giao hàng/xác nhận. Contract trong gói này đã bỏ quy trình đó; deploy `blockchain/PokemonAuction.sol` lên Sepolia bằng ví kiểm định viên, rồi điền địa chỉ mới vào `frontend/.env.local` (`VITE_CONTRACT_ADDRESS`). Thẻ, phiên và tiền escrow ở contract cũ không tự chuyển sang contract mới.

## Bắt đầu

Làm theo [frontend/README.md](frontend/README.md) để tạo database, cấu hình môi trường, deploy/cấu hình contract và chạy API + Vite. Không commit `.env.local`, `.env.server`, `node_modules` hoặc file người dùng tải lên.
