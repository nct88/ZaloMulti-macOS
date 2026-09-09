# ZaloMulti v2.1.12

## Sửa lỗi bản đóng gói (Release)

- App bị đơ khi tạo clone vì copy/vá asar/codesign chạy trên main thread — spinner không quay, dễ bấm Tạo 2 lần ra hai tài khoản cùng tên. Đưa toàn bộ I/O ra background.
- Không xoá được clone: process Zalo còn sống làm `removeItem` fail; xóa không còn hiện trên list dù file còn. Giờ kill process, `chmod` rồi xóa; chỉ gỡ khỏi list khi file đã xóa.
- Hộp xác nhận xóa dùng `NSAlert` (không dùng SwiftUI dialog).
- Bỏ quét toàn bộ file `._*` khi gỡ quarantine (rất chậm trên Electron).

## Gói cài đặt

- `ZaloMulti-2.1.12-Intel.dmg`: Mac Intel
- `ZaloMulti-2.1.12-AppleSilicon.dmg`: chip M
- `ZaloMulti-2.1.12-Universal.dmg`: khuyến nghị
