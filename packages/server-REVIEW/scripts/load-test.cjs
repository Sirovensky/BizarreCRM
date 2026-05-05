/**
 * Comprehensive load test — hits every major API endpoint with concurrent requests.
 * Uses native fetch (Node 22+) to blast the server.
 *
 * Usage: node scripts/load-test.cjs [duration_seconds] [concurrency]
 */
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const https = require('https');
const jwt = require('jsonwebtoken');
const Database = require('better-sqlite3');
const path = require('path');
const crypto = require('crypto');

// --- Config ---
const DURATION_SEC = parseInt(process.argv[2]) || 30;
const CONCURRENCY = parseInt(process.argv[3]) || 50;
const TENANT = 'bizarreelectronics';
const HOST = `${TENANT}.localhost`;
const BASE = 'https://127.0.0.1:443';

// Disable TLS verification for self-signed cert
const { Agent: UndiciAgent } = require('undici');
const undiciAgent = new UndiciAgent({ connect: { rejectUnauthorized: false } });

// --- Generate auth token ---
const db = new Database(path.join(__dirname, '..', 'data', 'tenants', `${TENANT}.db`));
const user = db.prepare('SELECT id, role FROM users WHERE username = ? AND is_active = 1').get('admin');
const sessionId = crypto.randomUUID();
const expires = new Date(Date.now() + 3600000).toISOString().replace('T', ' ').substring(0, 19);
db.prepare('INSERT INTO sessions (id, user_id, expires_at) VALUES (?, ?, ?)').run(sessionId, user.id, expires);

// Get some real IDs for detail endpoints
const ticketIds = db.prepare('SELECT id FROM tickets ORDER BY RANDOM() LIMIT 20').all().map(r => r.id);
const customerIds = db.prepare('SELECT id FROM customers ORDER BY RANDOM() LIMIT 20').all().map(r => r.id);
const invoiceIds = db.prepare('SELECT id FROM invoices ORDER BY RANDOM() LIMIT 10').all().map(r => r.id);
const inventoryIds = db.prepare('SELECT id FROM inventory_items ORDER BY RANDOM() LIMIT 10').all().map(r => r.id);
db.close();

const TOKEN = jwt.sign(
  { userId: user.id, sessionId, role: user.role, tenantSlug: TENANT },
  'dev-secret-change-me-in-production',
  { expiresIn: '1h' }
);

// --- Endpoint definitions (weighted by real-world frequency) ---
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

const ENDPOINTS = [
  // Ticket list (heaviest, most frequent)
  { weight: 15, method: 'GET', path: '/api/v1/tickets?pagesize=20&page=1' },
  { weight: 8,  method: 'GET', path: '/api/v1/tickets?pagesize=20&status_id=active' },
  { weight: 5,  method: 'GET', path: '/api/v1/tickets?keyword=iphone&pagesize=10' },
  // Ticket detail
  { weight: 12, method: 'GET', path: () => `/api/v1/tickets/${pick(ticketIds)}` },
  // Ticket kanban
  { weight: 4,  method: 'GET', path: '/api/v1/tickets/kanban' },
  // Ticket my-queue
  { weight: 6,  method: 'GET', path: '/api/v1/tickets/my-queue' },
  // Search (latency-critical)
  { weight: 10, method: 'GET', path: '/api/v1/search?q=john' },
  { weight: 5,  method: 'GET', path: '/api/v1/search?q=iphone' },
  { weight: 3,  method: 'GET', path: '/api/v1/search?q=screen' },
  // Customer list
  { weight: 8,  method: 'GET', path: '/api/v1/customers?pagesize=20&page=1' },
  // Customer detail
  { weight: 6,  method: 'GET', path: () => `/api/v1/customers/${pick(customerIds)}` },
  // Reports dashboard
  { weight: 5,  method: 'GET', path: '/api/v1/reports/dashboard' },
  // Reports
  { weight: 3,  method: 'GET', path: '/api/v1/reports/insights?from=2025-01-01&to=2026-04-09' },
  { weight: 2,  method: 'GET', path: '/api/v1/reports/sales?from=2025-10-01&to=2026-04-09' },
  // Settings
  { weight: 4,  method: 'GET', path: '/api/v1/settings/config' },
  { weight: 3,  method: 'GET', path: '/api/v1/settings/statuses' },
  // Inventory
  { weight: 5,  method: 'GET', path: '/api/v1/inventory?pagesize=20' },
  { weight: 3,  method: 'GET', path: () => `/api/v1/inventory/${pick(inventoryIds)}` },
  // Invoices
  { weight: 4,  method: 'GET', path: '/api/v1/invoices?pagesize=20' },
  { weight: 2,  method: 'GET', path: () => `/api/v1/invoices/${pick(invoiceIds)}` },
  // POS
  { weight: 3,  method: 'GET', path: '/api/v1/pos/products' },
  // Employees
  { weight: 2,  method: 'GET', path: '/api/v1/employees' },
  // Stalled / missing parts
  { weight: 2,  method: 'GET', path: '/api/v1/tickets/stalled' },
  { weight: 2,  method: 'GET', path: '/api/v1/tickets/missing-parts' },
];

// Build weighted pool
const POOL = [];
for (const ep of ENDPOINTS) {
  for (let i = 0; i < ep.weight; i++) POOL.push(ep);
}

// --- Stats ---
let totalRequests = 0;
let successCount = 0;
let errorCount = 0;
let status4xx = 0;
let status5xx = 0;
const latencies = [];
const endpointStats = new Map();

function recordStat(ep, latencyMs, statusCode) {
  const key = typeof ep.path === 'function' ? ep.path.toString().replace(/.*\/api/, '/api').replace(/\$.*/, '/:id') : ep.path;
  if (!endpointStats.has(key)) endpointStats.set(key, { count: 0, totalMs: 0, errors: 0, min: Infinity, max: 0 });
  const s = endpointStats.get(key);
  s.count++;
  s.totalMs += latencyMs;
  if (latencyMs < s.min) s.min = latencyMs;
  if (latencyMs > s.max) s.max = latencyMs;
  if (statusCode >= 400) s.errors++;
}

// --- Request runner (using https.request for custom Host header) ---
function makeHttpsRequest(method, urlPath) {
  return new Promise((resolve) => {
    const start = performance.now();
    const req = https.request({
      hostname: '127.0.0.1',
      port: 443,
      path: urlPath,
      method,
      headers: {
        'Host': HOST,
        'Authorization': `Bearer ${TOKEN}`,
        'Content-Type': 'application/json',
      },
      rejectUnauthorized: false,
      timeout: 10000,
    }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        const latency = performance.now() - start;
        resolve({ latency, statusCode: res.statusCode, bodyLen: body.length });
      });
    });
    req.on('error', () => {
      const latency = performance.now() - start;
      resolve({ latency, statusCode: 0, bodyLen: 0 });
    });
    req.on('timeout', () => { req.destroy(); });
    req.end();
  });
}

async function makeRequest() {
  const ep = pick(POOL);
  const urlPath = typeof ep.path === 'function' ? ep.path() : ep.path;

  const { latency, statusCode } = await makeHttpsRequest(ep.method, urlPath);
  latencies.push(latency);
  totalRequests++;

  if (statusCode >= 200 && statusCode < 300) {
    successCount++;
  } else if (statusCode >= 500) {
    status5xx++;
    errorCount++;
  } else if (statusCode >= 400) {
    status4xx++;
  } else if (statusCode === 0) {
    errorCount++;
  }

  recordStat(ep, latency, statusCode);
}

// --- Worker loop ---
async function worker(id, endTime) {
  while (Date.now() < endTime) {
    await makeRequest();
  }
}

// --- Percentile helper ---
function percentile(sorted, p) {
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

// --- Main ---
async function main() {
  console.log(`\n========================================`);
  console.log(`  LOAD TEST — ${CONCURRENCY} concurrent workers`);
  console.log(`  Duration: ${DURATION_SEC}s`);
  console.log(`  Target: ${BASE} (tenant: ${TENANT})`);
  console.log(`  Endpoints: ${ENDPOINTS.length} unique paths`);
  console.log(`========================================\n`);

  const endTime = Date.now() + DURATION_SEC * 1000;

  // Progress ticker
  const startTime = Date.now();
  const ticker = setInterval(() => {
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
    const rps = (totalRequests / (Date.now() - startTime) * 1000).toFixed(0);
    process.stdout.write(`\r  [${elapsed}s] ${totalRequests} requests | ${rps} req/s | ${errorCount} errors`);
  }, 500);

  // Launch workers
  const workers = [];
  for (let i = 0; i < CONCURRENCY; i++) {
    workers.push(worker(i, endTime));
  }
  await Promise.all(workers);
  clearInterval(ticker);

  // --- Results ---
  const elapsed = (Date.now() - startTime) / 1000;
  const sorted = [...latencies].sort((a, b) => a - b);

  console.log(`\n\n========================================`);
  console.log(`  RESULTS`);
  console.log(`========================================`);
  console.log(`  Total requests:   ${totalRequests}`);
  console.log(`  Duration:         ${elapsed.toFixed(1)}s`);
  console.log(`  Throughput:       ${(totalRequests / elapsed).toFixed(0)} req/s`);
  console.log(`  Success (2xx):    ${successCount}`);
  console.log(`  Client err (4xx): ${status4xx}`);
  console.log(`  Server err (5xx): ${status5xx}`);
  console.log(`  Network errors:   ${errorCount - status5xx}`);
  console.log(`  Error rate:       ${((errorCount / totalRequests) * 100).toFixed(1)}%`);
  console.log(`\n  Latency:`);
  console.log(`    Min:    ${sorted[0]?.toFixed(1)}ms`);
  console.log(`    p50:    ${percentile(sorted, 50)?.toFixed(1)}ms`);
  console.log(`    p90:    ${percentile(sorted, 90)?.toFixed(1)}ms`);
  console.log(`    p95:    ${percentile(sorted, 95)?.toFixed(1)}ms`);
  console.log(`    p99:    ${percentile(sorted, 99)?.toFixed(1)}ms`);
  console.log(`    Max:    ${sorted[sorted.length - 1]?.toFixed(1)}ms`);

  console.log(`\n  Per-endpoint breakdown:`);
  console.log(`  ${'Endpoint'.padEnd(55)} ${'Reqs'.padStart(6)} ${'Avg'.padStart(8)} ${'Min'.padStart(8)} ${'Max'.padStart(8)} ${'Errs'.padStart(6)}`);
  console.log(`  ${'─'.repeat(55)} ${'─'.repeat(6)} ${'─'.repeat(8)} ${'─'.repeat(8)} ${'─'.repeat(8)} ${'─'.repeat(6)}`);

  const entries = [...endpointStats.entries()].sort((a, b) => b[1].count - a[1].count);
  for (const [key, s] of entries) {
    const shortKey = key.length > 54 ? '...' + key.slice(-51) : key;
    console.log(`  ${shortKey.padEnd(55)} ${String(s.count).padStart(6)} ${(s.totalMs / s.count).toFixed(1).padStart(7)}ms ${s.min.toFixed(1).padStart(7)}ms ${s.max.toFixed(1).padStart(7)}ms ${String(s.errors).padStart(6)}`);
  }

  console.log(`\n========================================\n`);
}

main().catch(console.error);
