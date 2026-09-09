# ZaloMulti v2.1.6

## Sửa lỗi

- **Intel:** bản 2.1.5 không tạo được clone vì ô Tên hiển thị / Số điện thoại dùng AppKit `NSTextField` bị co còn gần 0px — không gõ được, nút Tạo Clone luôn khóa. Khôi phục SwiftUI `TextField` như 2.1.4.
- Giữ các sửa cho chip M: binary Mach-O, Hardened Runtime, không thay Zalo bằng script bash.
- Overlay thêm clone không dùng `onTapGesture` (tránh mất focus trên Apple Silicon).

## Gói cài đặt

- `ZaloMulti-2.1.6-Universal.dmg`: khuyến nghị, Intel và chip M.
- `ZaloMulti-2.1.6-AppleSilicon.dmg`: chỉ chip M.
- `ZaloMulti-2.1.6-Intel.dmg`: chỉ Mac Intel.
