/**
 * BizarreCRM High-Performance Stress Test
 * Uses Node.js native HTTPS with connection pooling for maximum throughput.
 *
 * Usage: node scripts/stress-test.js [total] [concurrency]
 * Example: node scripts/stress-test.js 5000 500
 */
const https = require('https');

const TOTAL = parseInt(process.argv[2]) || 5000;
const CONCURRENCY = parseInt(process.argv[3]) || 200;
const BASE = 'https://localhost';

// Reuse connections for speed
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
  { method: 'GET', path: '/api/v1/../../../etc/passwd' },
  { method: 'POST', path: '/api/v1/auth/login', body: '{"username":"admin","password":"wrong"}' },
  { method: 'POST', path: '/api/v1/auth/login', body: '{"username":"test","password":"test"}' },
  { method: 'POST', path: '/api/v1/tickets', body: '{}' },
  { method: 'DELETE', path: '/api/v1/tickets/999999' },
  { method: 'PUT', path: '/api/v1/customers/999999', body: '{"first_name":"hack"}' },
  { method: 'POST', path: '/super-admin/api/login', body: '{"username":"x","password":"x"}' },
  { method: 'GET', path: '/api/v1/management/stats' },
  { method: 'GET', path: '/' },
  { method: 'OPTIONS', path: '/api/v1/tickets' },
  { method: 'POST', path: '/api/v1/auth/login', body: '<script>alert(1)</script>' },
  { method: 'POST', path: '/api/v1/tickets', body: '{"sql":"DROP TABLE users;--"}' },
];

const stats = { sent: 0, done: 0, status: {}, errors: 0, startTime: 0 };

function sendRequest() {
  return new Promise((resolve) => {
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

    // Random fake auth header
    if (Math.random() > 0.5) {
      opts.headers['Authorization'] = 'Bearer fake-' + Math.random().toString(36);
    }

    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        stats.done++;
        stats.status[res.statusCode] = (stats.status[res.statusCode] || 0) + 1;
        resolve(res.statusCode);
      });
    });

    req.on('error', () => {
      stats.done++;
      stats.errors++;
      resolve(0);
    });

    req.on('timeout', () => {
      req.destroy();
      stats.done++;
      stats.errors++;
      resolve(0);
    });

    if (ep.body) req.write(ep.body);
    req.end();
    stats.sent++;
  });
}

async function run() {
  console.log('============================================');
  console.log(' BizarreCRM Stress Test (Node.js)');
  console.log(` Requests: ${TOTAL} | Concurrency: ${CONCURRENCY}`);
  console.log('============================================\n');

  stats.startTime = Date.now();

  // Progress ticker
  const ticker = setInterval(() => {
    const elapsed = (Date.now() - stats.startTime) / 1000;
    const rps = Math.round(stats.done / elapsed);
    process.stdout.write(`\r  Progress: ${stats.done}/${TOTAL} | ${rps} req/s | Errors: ${stats.errors}`);
  }, 200);

  // Send all requests with concurrency limit
  const active = new Set();
  for (let i = 0; i < TOTAL; i++) {
    const p = sendRequest().then(() => active.delete(p));
    active.add(p);
    if (active.size >= CONCURRENCY) {
      await Promise.race(active);
    }
  }
  await Promise.all(active);

  clearInterval(ticker);

  const elapsed = (Date.now() - stats.startTime) / 1000;
  const rps = Math.round(stats.done / elapsed);

  console.log(`\r  Progress: ${stats.done}/${TOTAL} | ${rps} req/s | Errors: ${stats.errors}`);
  console.log('\n');

  // Health check
  console.log('--- Post-stress health check ---');
  try {
    const code = await sendRequest();
    console.log(`  Server: ${code > 0 ? 'ALIVE' : 'DOWN'}`);
  } catch {
    console.log('  Server: DOWN');
  }

  console.log('\n--- Status Code Distribution ---');
  const sorted = Object.entries(stats.status).sort((a, b) => b[1] - a[1]);
  for (const [code, count] of sorted) {
    const pct = ((count / stats.done) * 100).toFixed(1);
    console.log(`  ${code}: ${count} (${pct}%)`);
  }

  console.log(`\n============================================`);
  console.log(` Duration: ${elapsed.toFixed(1)}s`);
  console.log(` Total: ${stats.done} requests`);
  console.log(` Rate: ${rps} req/s`);
  console.log(` Errors: ${stats.errors}`);
  console.log(`============================================`);
}

run();
