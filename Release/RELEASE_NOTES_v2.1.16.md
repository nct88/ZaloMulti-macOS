# ZaloMulti v2.1.16

## Sửa lỗi

- **Bấm "Chạy" clone mở Zalo gốc rồi tắt**: clone dùng chung thư mục dữ liệu (và SingletonLock) với Zalo gốc vì Electron bỏ qua `HOME`. Nay clone có dữ liệu riêng qua `CFFIXED_USER_HOME`, chạy song song với Zalo gốc.
- **Mỗi lần mở clone phải đặt lại keychain**: clone giờ dùng keychain thật của máy. Clone tạo từ bản cũ được sửa tự động khi chạy, không cần tạo lại.
- **App tự mở trình duyệt mỗi lần khởi động trên macOS 15**: kiểm tra chống can thiệp bắt nhầm framework hệ thống `BiomeFlexibleStorage`. Đã bỏ qua thư viện hệ thống.
- **Nút "Thêm tài khoản" không phản hồi** (bản 2.1.15): build lại với Xcode 26.2.

## Gói cài đặt

- `ZaloMulti-2.1.16-Intel.dmg`
- `ZaloMulti-2.1.16-AppleSilicon.dmg`
- `ZaloMulti-2.1.16-Universal.dmg`
