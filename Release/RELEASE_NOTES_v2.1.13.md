# ZaloMulti v2.1.13

## Sửa lỗi nghiêm trọng

- Xóa clone: bấm OK nhưng card vẫn hiện, phải tắt app mở lại mới mất. `NSAlert.runModal()` làm SwiftUI bỏ qua lần cập nhật list. Giờ xác nhận bằng sheet, xóa trên run loop tiếp theo, gán lại mảng `clones` để UI refresh ngay.

## Gói cài đặt

- `ZaloMulti-2.1.13-Intel.dmg`: Mac Intel
- `ZaloMulti-2.1.13-AppleSilicon.dmg`: chip M
- `ZaloMulti-2.1.13-Universal.dmg`: khuyến nghị
