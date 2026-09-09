# ZaloMulti v2.1.11

## Sửa lỗi

- Nút **Tạo Clone** đã chạy nhưng form không hiện tiến trình/lỗi (SwiftUI trong NSPanel không vẽ lại) nên nhìn như không phản hồi. Form chuyển sang cửa sổ AppKit thuần: spinner, dòng trạng thái, lỗi màu đỏ.
- Chặn bấm tạo chồng nhiều lần (làm hỏng bản copy Zalo, lỗi Info.plist / Mach-O / rsync).
- Sao chép Zalo bằng `ditto`, xóa clone cũ hỏng trước khi copy.

## Gói cài đặt

- `ZaloMulti-2.1.11-Intel.dmg`: Mac Intel
- `ZaloMulti-2.1.11-AppleSilicon.dmg`: chip M
- `ZaloMulti-2.1.11-Universal.dmg`: khuyến nghị
