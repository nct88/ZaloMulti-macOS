// ZaloMulti / truong.me — Donate backend (VPS, thay cho Cloudflare Worker /donate-api)
//
// Đặt sau nginx: truong.me/donate-api/*  →  127.0.0.1:PORT (nginx strip tiền tố /donate-api).
// Mục tiêu: nhận webhook SePay → ghi "đã trả tiền" theo mã CK; trang donate poll /check
// thấy paid → gọi /hwid/register|/donate_add để ghi HWID vào donated_hwids.json;
// app ZaloMulti đọc donate_check (do relay-server phục vụ, CHUNG file) → hết popup.
//
// Dùng file JSON (giống hệ thống sẵn có), không cần module native.

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');

// ───────── Config (qua biến môi trường / PM2 ecosystem) ─────────
const PORT = parseInt(process.env.PORT || '3005', 10);
// CHUNG file với relay-server để app donate_check thấy ngay:
const DONATED_FILE = process.env.DONATED_FILE || '/root/relay-server/donated_hwids.json';
// Kho giao dịch đã nhận từ webhook SePay:
const PAID_FILE = process.env.PAID_FILE || path.join(__dirname, 'data', 'paid.json');
// Ánh xạ mã đơn → HWID (trang donate đăng ký khi tạo đơn) để webhook tự ghi nhận
// kể cả khi người dùng đóng trang trước khi tiền vào:
const MAP_FILE = process.env.MAP_FILE || path.join(__dirname, 'data', 'codemap.json');
// Khoá webhook SePay: header "Authorization: Apikey <KEY>"
const SEPAY_API_KEY = process.env.SEPAY_API_KEY || '';
const MIN_AMOUNT = parseInt(process.env.MIN_AMOUNT || '0', 10);

fs.mkdirSync(path.dirname(PAID_FILE), { recursive: true });

// ───────── JSON helpers (atomic write) ─────────
function readJSON(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { return fallback; }
}
function writeJSONAtomic(file, data) {
  const tmp = file + '.tmp-' + process.pid;
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, file);
}

function getDonatedList() {
  const l = readJSON(DONATED_FILE, []);
  return Array.isArray(l) ? l : [];
}
function addDonatedHwid(hwid) {
  const list = getDonatedList();
  if (!list.includes(hwid)) { list.push(hwid); writeJSONAtomic(DONATED_FILE, list); return true; }
  return false;
}
function isDonated(hwid) { return getDonatedList().includes(hwid); }

// codemap: { [CODE]: hwid } — mã đơn (nội dung CK) → HWID
function getCodeMap() { return readJSON(MAP_FILE, {}); }
function setCodeMap(code, hwid) {
  const m = getCodeMap();
  m[String(code).toUpperCase()] = hwid;
  writeJSONAtomic(MAP_FILE, m);
}
// Tìm HWID theo nội dung CK: duyệt các mã đã đăng ký, mã nào xuất hiện trong content → trả HWID
function hwidsFromContent(content) {
  const up = String(content || '').toUpperCase();
  const m = getCodeMap();
  const found = [];
  for (const code of Object.keys(m)) {
    if (code && up.includes(code)) found.push({ code, hwid: m[code] });
  }
  return found;
}

// paid: { [ref]: {content, amount, at} }  — chống trùng theo referenceCode
function getPaid() { return readJSON(PAID_FILE, {}); }
function recordPaid(ref, rec) {
  const p = getPaid();
  if (p[ref]) return false;
  p[ref] = rec; writeJSONAtomic(PAID_FILE, p); return true;
}
// Tìm giao dịch khớp mã CK (content chứa code), đủ số tiền
function findPaidByCode(code, minAmount) {
  const up = String(code).toUpperCase();
  const p = getPaid();
  for (const ref of Object.keys(p)) {
    const rec = p[ref];
    if (String(rec.content || '').toUpperCase().includes(up)) {
      if (!minAmount || (rec.amount || 0) >= minAmount) return rec;
    }
  }
  return null;
}

// ───────── App ─────────
const app = express();
app.set('trust proxy', true);
app.use(express.json({ limit: '256kb' }));
app.use(express.urlencoded({ extended: false, limit: '256kb' }));

// CORS mở (giống hệ thống cũ, app Electron + web gọi)
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.get('/healthz', (_req, res) => res.json({ ok: true, donated: getDonatedList().length }));

// 1) Webhook SePay — nguồn sự thật "đã trả tiền"
app.post('/webhook/sepay', (req, res) => {
  if (SEPAY_API_KEY) {
    const auth = req.get('authorization') || '';
    const expected = 'Apikey ' + SEPAY_API_KEY;
    const a = Buffer.from(auth), b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(401).json({ success: false, error: 'unauthorized' });
    }
  }
  const p = req.body || {};
  const transferType = String(p.transferType || '').toLowerCase();
  if (transferType && transferType !== 'in') return res.json({ success: true, ignored: 'not incoming' });

  const ref = String(p.referenceCode || p.id || Date.now());
  const amount = parseInt(p.transferAmount || p.amount || 0, 10) || 0;
  const content = [p.code, p.content, p.description].filter(Boolean).join(' ');

  const isNew = recordPaid(ref, { content, amount, at: new Date().toISOString() });

  // Tự ghi HWID đã donate dựa trên ánh xạ mã→HWID (không cần trang donate mở)
  let marked = [];
  if (isNew) {
    for (const { code, hwid } of hwidsFromContent(content)) {
      if (MIN_AMOUNT > 0 && amount < MIN_AMOUNT) continue;
      if (hwid && addDonatedHwid(hwid)) marked.push({ code, hwid });
    }
  }
  res.json({ success: true, duplicate: !isNew, marked });
});

// Trang donate đăng ký ánh xạ mã→HWID khi tạo đơn (trước khi trả tiền)
app.all('/order', (req, res) => {
  const code = String(req.query.code || (req.body && req.body.code) || '');
  const hwid = String(req.query.hwid || (req.body && req.body.hwid) || '');
  if (!code || !hwid) return res.json({ success: false, error: 'thiếu code/hwid' });
  setCodeMap(code, hwid);
  res.json({ success: true });
});

// 2) Trang donate poll: đã trả tiền cho mã này chưa?
app.get('/check', (req, res) => {
  const code = String(req.query.code || '');
  const amount = parseInt(req.query.amount || '0', 10) || 0;
  if (!code) return res.json({ status: 'pending', error: 'missing code' });
  const hit = findPaidByCode(code, MIN_AMOUNT || (amount ? Math.floor(amount * 0.9) : 0));
  res.set('Cache-Control', 'no-store');
  res.json({ status: hit ? 'paid' : 'pending' });
});

// 3) Ghi HWID đã donate — trang donate gọi sau khi thấy paid
function handleAdd(hwid, res) {
  if (!hwid) return res.json({ success: false, error: 'Thiếu mã HWID' });
  addDonatedHwid(hwid);
  res.json({ success: true, hwid, message: 'Đã thêm HWID thành công!' });
}
app.all('/donate_add', (req, res) => handleAdd(String(req.query.hwid || (req.body && req.body.hwid) || ''), res));
app.post('/hwid/register', (req, res) => handleAdd(String((req.body && req.body.hwid) || req.query.hwid || ''), res));

// 4) Tra cứu trạng thái (tương thích cả 2 tên tham số)
app.get('/hwid/check', (req, res) => {
  const hwid = String(req.query.id || req.query.hwid || '');
  res.json({ hwid, donated: hwid ? isDonated(hwid) : false });
});
app.get('/donate_check', (req, res) => {
  const hwid = String(req.query.hwid || '');
  if (!hwid) return res.json({ error: 'Thiếu mã HWID', donated: false });
  res.set('Cache-Control', 'no-store');
  res.json({ hwid, donated: isDonated(hwid) });
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`[donate-api] listening 127.0.0.1:${PORT} donatedFile=${DONATED_FILE}`);
});
