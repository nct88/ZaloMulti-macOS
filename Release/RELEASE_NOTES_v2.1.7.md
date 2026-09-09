# ZaloMulti v2.1.7

## Sửa lỗi

- Bấm **Thêm tài khoản** không hiện form: overlay cũ dùng `if` + animation opacity trên ZStack nên bảng có thể mở ở opacity 0 (không thấy) và nuốt mọi click sau đó.
- Form thêm clone chuyển sang `.overlay` + state local, không animation ẩn. Cả thẻ dashed và nút **+ Thêm tài khoản** trên thanh công cụ đều mở form.
- Ô nhập vẫn là SwiftUI TextField (sửa regression Intel 2.1.5).

## Gói cài đặt

- `ZaloMulti-2.1.7-Universal.dmg`: khuyến nghị.
- `ZaloMulti-2.1.7-Intel.dmg`: Mac Intel.
- `ZaloMulti-2.1.7-AppleSilicon.dmg`: chip M.
