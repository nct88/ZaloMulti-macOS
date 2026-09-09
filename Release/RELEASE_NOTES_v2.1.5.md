# ZaloMulti v2.1.5

## Sửa lỗi Apple Silicon (chip M)

- Không còn thay binary Mach-O của Zalo bằng script bash khi tạo clone. Script này khiến macOS trên chip M từ chối ký mã / kill tiến trình Electron.
- Ký clone bằng Hardened Runtime (`--options runtime`) kèm entitlement JIT, giống Zalo gốc. Thiếu bước này thì clone bị AMFI kill trên chip M dù tạo “thành công”.
- Ký từng helper/framework từ trong ra ngoài, bỏ `--deep` (deprecated, làm sai identifier helper trên ARM).
- Ô nhập Tên hiển thị / Số điện thoại dùng AppKit `NSTextField` để tránh lỗi mất focus của SwiftUI trên chip M và khi chạy Rosetta.
- Cảnh báo ngay trên dashboard nếu đang chạy bản Intel qua Rosetta.

## Gói cài đặt cho máy test chip M

Dùng **một** trong hai file (không dùng bản Intel):

- `ZaloMulti-2.1.5-Universal.dmg` — khuyến nghị, chạy được Intel và chip M
- `ZaloMulti-2.1.5-AppleSilicon.dmg` — chỉ chip M

Không gửi `ZaloMulti-*-Intel.dmg` cho máy M. Bản Intel chạy qua Rosetta và dễ lỗi form thêm tài khoản.

## Checklist cho người test trên Mac chip M

1. Cài Zalo Desktop chính thức vào `/Applications/Zalo.app` và mở 1 lần.
2. Tải đúng file Universal hoặc AppleSilicon, kéo vào Applications.
3. Lần đầu mở: chuột phải → Mở → chọn Mở (Gatekeeper).
4. Trong Zalỏ: Thêm tài khoản → nhập tên → Tạo Clone. Form phải gõ được, không bị reset.
5. Nếu lỗi: Cài đặt → tab Log → Copy đường dẫn, gửi file `~/Library/Logs/ZaloMulti/zcm.log`.
6. Dòng log cần có: `Host: arm64 (Apple Silicon native)`. Nếu thấy `via Rosetta` là đang dùng nhầm bản Intel.
