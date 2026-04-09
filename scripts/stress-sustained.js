/**
 * BizarreCRM Sustained Load Test
 * Runs continuously at target req/s until Ctrl+C.
 * Shows live stats every second.
 *
 * Usage: node scripts/stress-sustained.js [target_rps] [concurrency]
 * Example: node scripts/stress-sustained.js 1000 300
 */
const https = require('https');

const TARGET_RPS = parseInt(process.argv[2]) || 1000;
const CONCURRENCY = parseInt(process.argv[3]) || 300;

const agent = new https.Agent({
  rejectAuthorized: false,
  keepAlive: true,
  maxSockets: CONCURRENCY,
});

const ENDPOINTS = [
  { method: 'GET', path: '/api/v1/health' },
  { method: 'GET', path: '/api/v1/tickets?page=1&per_page=20' },
  { method: 'GET', path: '/api/v1/customers?page=1' },
  { method: 'GET', path: '/api/v1/inventory?page=1' },
  { method: 'GET', path: '/api/v1/invoices?page=1' },
  { method: 'GET', path: '/api/v1/search?q=test' },
  { method: 'GET', path: '/api/v1/leads' },
  { method: 'GET', path: '/api/v1/estimates' },
  { method: 'GET', path: '/api/v1/settings' },
  { method: 'GET', path: '/api/v1/reports/sales?from=2026-01-01&to=2026-12-31' },
  { method: 'GET', path: '/api/v1/notifications' },
  { method: 'GET', path: '/api/v1/employees' },
  { method: 'GET', path: '/api/v1/nonexistent' },
  { method: 'POST', path: '/api/v1/auth/login', body: '{"username":"admin","password":"wrong"}' },
  { method: 'POST', path: '/api/v1/tickets', body: '{}' },
  { method: 'DELETE', path: '/api/v1/tickets/999999' },
  { method: 'PUT', path: '/api/v1/customers/999999', body: '{"first_name":"hack"}' },
  { method: 'GET', path: '/' },
  { method: 'POST', path: '/api/v1/auth/login', body: '<script>alert(1)</script>' },
];

let totalSent = 0;
let totalDone = 0;
let totalErrors = 0;
let windowDone = 0;
let windowErrors = 0;
let window429 = 0;
let window500 = 0;
let active = 0;
let peakRps = 0;
let startTime = Date.now();

function sendRequest() {
  const ep = ENDPOINTS[Math.floor(Math.random() * ENDPOINTS.length)];
  const opts = {
    hostname: 'localhost',
    port: 443,
    path: ep.path,
    method: ep.method,
    rejectUnauthorized: false,
    agent,
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  };

  if (Math.random() > 0.5) {
    opts.headers['Authorization'] = 'Bearer fake-' + Math.random().toString(36);
  }

  active++;
  totalSent++;

  const req = https.request(opts, (res) => {
    let data = '';
    res.on('data', (c) => { data += c; });
    res.on('end', () => {
      active--;
      totalDone++;
      windowDone++;
      if (res.statusCode === 429) window429++;
      if (res.statusCode >= 500) window500++;
    });
  });

  req.on('error', () => { active--; totalDone++; totalErrors++; windowErrors++; });
  req.on('timeout', () => { req.destroy(); });

  if (ep.body) req.write(ep.body);
  req.end();
}

// Stats display every second
const statsInterval = setInterval(() => {
  const elapsed = Math.round((Date.now() - startTime) / 1000);
  const currentRps = windowDone;
  if (currentRps > peakRps) peakRps = currentRps;
  const avgRps = Math.round(totalDone / Math.max(elapsed, 1));

  const mem = process.memoryUsage();
  const clientMem = Math.round(mem.rss / 1024 / 1024);

  process.stdout.write(
    `\r  ${elapsed}s | RPS: ${currentRps} (avg ${avgRps}, peak ${peakRps}) | Active: ${active} | Total: ${totalDone} | 429: ${window429} | 5xx: ${window500} | Err: ${windowErrors} | Mem: ${clientMem}MB   `
  );

  // Reset window counters
  windowDone = 0;
  windowErrors = 0;
  window429 = 0;
  window500 = 0;
}, 1000);

// Request pump — sends TARGET_RPS requests per second
const pumpInterval = setInterval(() => {
  const batch = Math.min(TARGET_RPS, CONCURRENCY - active);
  for (let i = 0; i < batch; i++) {
    if (active < CONCURRENCY) {
      sendRequest();
    }
  }
}, 10); // Check every 10ms, send in small bursts

console.log('============================================');
console.log(` BizarreCRM Sustained Load Test`);
console.log(` Target: ${TARGET_RPS} req/s | Concurrency: ${CONCURRENCY}`);
console.log(` Press Ctrl+C to stop`);
console.log('============================================\n');

// Graceful shutdown
process.on('SIGINT', () => {
  clearInterval(pumpInterval);
  clearInterval(statsInterval);
  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  const avgRps = Math.round(totalDone / parseFloat(elapsed));
  console.log('\n\n============================================');
  console.log(' Test stopped');
  console.log(` Duration: ${elapsed}s`);
  console.log(` Total requests: ${totalDone}`);
  console.log(` Average: ${avgRps} req/s | Peak: ${peakRps} req/s`);
  console.log(` Errors: ${totalErrors}`);
  console.log('============================================');
  process.exit(0);
});
