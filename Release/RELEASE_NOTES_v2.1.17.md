# ZaloMulti v2.1.17

## Sửa lỗi quan trọng

- **Không gõ được tên / số điện thoại khi thêm tài khoản**: form chuyển sang dạng sheet chuẩn macOS (`TextField` + `@FocusState`), nhận bàn phím ổn định trên mọi máy (Intel & Apple Silicon).
- **Chạy clone làm Zalo gốc bị đăng xuất, đòi tạo lại khoá**: clone không còn dùng chung keychain với máy (nguyên nhân làm macOS reset login keychain). Clone chạy với keychain cách ly (`--use-mock-keychain`), không đụng Zalo gốc.
- **Zalo gốc báo lỗi / không mở được (ENOENT ZaloData)**: tự phát hiện và gỡ liên kết (symlink) hỏng do bản cũ để lại; khôi phục dữ liệu gốc nếu còn.
- **Clone thoát đột ngột khi có tin nhắn/hoạt động mới**: sửa lỗi theo dõi thông báo chạy sai luồng.
- **Giao diện không phản hồi / không cập nhật**: khắc phục triệt để ở gốc; bỏ các lớp vá tạm khiến app giật và rụng focus.

## Khác

- Siết bảo mật thông tin liên hệ & endpoint trong ứng dụng.
- Thêm liên hệ **Email** và **Hotline** ở thanh bên.
- Sửa kiểm tra cập nhật tự động trỏ đúng kho phát hành.

## Gói cài đặt

- `ZaloMulti-2.1.17-Intel.dmg`
- `ZaloMulti-2.1.17-AppleSilicon.dmg`
- `ZaloMulti-2.1.17-Universal.dmg`
