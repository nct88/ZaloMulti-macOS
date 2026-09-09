# ZaloMulti v2.1.15

## Thiết kế lại UI / khởi động

- Form thêm clone trở lại **trong cùng cửa sổ** (bỏ NSWindow riêng). Tạo/xóa cập nhật list ngay, không cần tắt app.
- Xóa dùng SwiftUI confirmationDialog.
- Dashboard lắng nghe `NotificationCenter` + `listRevision` để vẽ lại list.
- Khởi động không chặn: pgrep/migrate chạy sau frame đầu. Donate mở sau 6 giây, không chờ form thêm clone.

## Gói cài đặt

- `ZaloMulti-2.1.15-Intel.dmg`
- `ZaloMulti-2.1.15-AppleSilicon.dmg`
- `ZaloMulti-2.1.15-Universal.dmg`
