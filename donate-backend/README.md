# donate-api — backend donate trên VPS (thay Cloudflare Worker)

Service Node.js phục vụ `truong.me/donate-api/*`, nhận **webhook SePay** và ghi HWID đã
ủng hộ vào **chung file** `/root/relay-server/donated_hwids.json` mà app ZaloMulti đọc
qua `api.truong.me/donate_check`. Khi đã donate → app ngừng mở trang donate.

## Đã triển khai trên VPS (144.91.77.44)
- Thư mục: `/opt/zalomulti-donate/` (server.js, package.json, ecosystem.config.js, data/)
- PM2: process `donate-api`, cổng **127.0.0.1:3015**, `pm2 save` đã lưu.
- nginx: `truong.me` có thêm `location /donate-api/ → http://127.0.0.1:3015/` (đã `nginx -t` + reload).
- Ghi chung `donated_hwids.json` với relay-server → `donate_check` của app thấy ngay.

## Các route (sau khi nginx strip tiền tố /donate-api)
| Public | Việc |
|---|---|
| `POST /donate-api/webhook/sepay` | SePay gọi khi có tiền vào (verify `Authorization: Apikey`); tự tra mã→HWID và ghi donate |
| `POST /donate-api/order` | Trang donate đăng ký ánh xạ `{code, hwid}` khi tạo đơn (để webhook tự ghi dù đóng trang) |
| `GET /donate-api/check?code=&amount=` | Trang donate poll: đã trả tiền cho mã này chưa |
| `GET /donate-api/donate_add?hwid=` | Ghi HWID đã donate |
| `POST /donate-api/hwid/register` | Như trên (body JSON {hwid}) |
| `GET /donate-api/donate_check?hwid=` / `/hwid/check?id=` | Tra trạng thái |

## CÒN LẠI — 2 việc bạn tự làm

**1. Gỡ route Cloudflare Worker cho `/donate-api`**
Hiện Worker chặn `truong.me/donate-api/*` ở edge nên request chưa xuống VPS.
Vào Cloudflare dashboard → Workers & Pages → Worker đang gắn → **Triggers / Routes** →
xoá route `truong.me/donate-api/*`. Sau đó public URL sẽ chạy vào VPS.

**2. Cấu hình webhook SePay**
SePay → Cấu hình → Webhooks → thêm:
- URL: `https://truong.me/donate-api/webhook/sepay`
- Kiểu: JSON, sự kiện: tiền vào (incoming)
- Authorization: `Apikey <KEY>` — dùng đúng `SEPAY_API_KEY` trong
  `/opt/zalomulti-donate/ecosystem.config.js` trên VPS.

## Kiểm tra (sau khi gỡ Worker)
```bash
curl 'https://truong.me/donate-api/healthz'
curl 'https://truong.me/donate-api/donate_check?hwid=test_123'   # donated:true
# giả lập webhook:
curl -X POST https://truong.me/donate-api/webhook/sepay \
  -H 'Authorization: Apikey <KEY>' -H 'Content-Type: application/json' \
  -d '{"transferType":"in","transferAmount":50000,"referenceCode":"T1","content":"MA_DON ung ho"}'
```

## Vận hành
```bash
pm2 restart donate-api      # sau khi sửa code/env
pm2 logs donate-api         # xem log
# dữ liệu: donated_hwids.json (relay-server) + /opt/zalomulti-donate/data/paid.json
```

## Lưu ý
- `donate_add`/`hwid/register` hiện **không auth** (giữ như hệ thống cũ). Nếu muốn chặt
  hơn: chỉ ghi HWID khi `/check` của mã tương ứng đã `paid`. Nói nếu bạn muốn siết.
- Service này độc lập, **không đụng** relay-server (Facebook Messenger) — relay không bị restart.
