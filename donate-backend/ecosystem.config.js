// PM2 config cho donate-api trên VPS. Đặt SEPAY_API_KEY thật trong file này trên VPS
// (KHÔNG commit khoá thật — repo để placeholder).
module.exports = { apps: [{
  name: 'donate-api',
  script: '/opt/zalomulti-donate/server.js',
  env: {
    PORT: '3015',
    DONATED_FILE: '/root/relay-server/donated_hwids.json',  // CHUNG file với relay-server
    PAID_FILE: '/opt/zalomulti-donate/data/paid.json',
    SEPAY_API_KEY: 'DAT_APIKEY_SEPAY_O_DAY',
    MIN_AMOUNT: '0'
  },
  autorestart: true
}]};
