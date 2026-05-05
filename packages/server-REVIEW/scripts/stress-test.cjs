/**
 * Stress test — blast the configured server with thousands of requests per second.
 * Tests rate limiting, error handling, and server resilience under heavy load.
 *
 * Usage: node scripts/stress-test.cjs [duration_seconds] [concurrency] [target_host]
 *
 * Examples:
 *   node scripts/stress-test.cjs 30 200                    # 200 workers, 30s, default host
 *   node scripts/stress-test.cjs 60 500 example.com        # 500 workers, 60s, custom host
 */
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
const fs = require('fs');
const https = require('https');
const path = require('path');

function readBaseDomainFromEnvFile() {
  const envFile = path.resolve(__dirname, '..', '..', '..', '.env');
  try {
    const line = fs.readFileSync(envFile, 'utf8')
      .split(/\r?\n/)
      .find((entry) => /^BASE_DOMAIN=/.test(entry.trim()));
    if (!line) return '';
    return line.split('=').slice(1).join('=').trim().replace(/^['"]|['"]$/g, '');
  } catch {
    return '';
  }
}

// --- Config ---
const DURATION_SEC = parseInt(process.argv[2]) || 30;
const CONCURRENCY = parseInt(process.argv[3]) || 200;
const TARGET_HOST = process.argv[4] || process.env.BASE_DOMAIN || readBaseDomainFromEnvFile() || 'localhost';
const TARGET_PORT = 443;

// --- Endpoints to attack (mix of public + authenticated + invalid) ---
const ENDPOINTS = [
  // Landing page (static assets)
  { weight: 10, method: 'GET', path: '/' },
  { weight: 5,  method: 'GET', path: '/assets/index.css' },
  { weight: 5,  method: 'GET', path: '/assets/index.js' },

  // Public API endpoints
  { weight: 8,  method: 'GET', path: '/api/v1/info' },
  { weight: 8,  method: 'GET', path: '/api/v1/health' },

  // Signup slug checks (rate limited: 30/min per IP)
  { weight: 6,  method: 'GET', path: '/api/v1/signup/check-slug/testshop' },
  { weight: 3,  method: 'GET', path: '/api/v1/signup/check-slug/randomshop' + Math.random().toString(36).slice(2, 8) },

  // Auth endpoints (rate limited, should reject)
  { weight: 8,  method: 'POST', path: '/api/v1/auth/login', body: '{"username":"fake","password":"fake"}' },
  { weight: 4,  method: 'POST', path: '/api/v1/auth/login', body: '{"username":"admin","password":"wrongpassword"}' },

  // Authenticated endpoints without token (should get 401)
  { weight: 10, method: 'GET', path: '/api/v1/tickets' },
  { weight: 8,  method: 'GET', path: '/api/v1/customers' },
  { weight: 6,  method: 'GET', path: '/api/v1/inventory' },
  { weight: 5,  method: 'GET', path: '/api/v1/invoices' },
  { weight: 5,  method: 'GET', path: '/api/v1/reports/dashboard' },
  { weight: 4,  method: 'GET', path: '/api/v1/search?q=test' },
  { weight: 3,  method: 'GET', path: '/api/v1/settings/config' },
  { weight: 3,  method: 'GET', path: '/api/v1/employees' },

  // Non-existent endpoints (should get clean 404)
  { weight: 4,  method: 'GET', path: '/api/v1/nonexistent' },
  { weight: 2,  method: 'POST', path: '/api/v1/fake/endpoint' },

  // Malicious payloads (should be rejected)
  { weight: 3,  method: 'POST', path: '/api/v1/auth/login', body: '{"username":"<script>alert(1)</script>","password":"x"}' },
  { weight: 2,  method: 'GET', path: '/api/v1/tickets?page=1&pagesize=999999' },
  { weight: 2,  method: 'GET', path: '/../../../etc/passwd' },
  { weight: 2,  method: 'GET', path: '/api/v1/tickets/../../etc/passwd' },

  // Signup spam (rate limited: 5/hour per IP)
  { weight: 2,  method: 'POST', path: '/api/v1/signup/', body: '{"slug":"attacker","shop_name":"Hack Shop","admin_email":"a@b.com","admin_password":"password123"}' },

  // Large payload (should be rejected by body parser limit)
  { weight: 1,  method: 'POST', path: '/api/v1/auth/login', body: '{"username":"' + 'A'.repeat(10000) + '","password":"x"}' },

  // Portal/tracking (public, unauthenticated)
  { weight: 4,  method: 'GET', path: '/api/v1/track/portal/FAKE-ORDER' },

  // Tenant subdomains (should get tenant not found)
  { weight: 3,  method: 'GET', path: '/', host: 'fakeshop.' + TARGET_HOST },
  { weight: 3,  method: 'GET', path: '/', host: 'admin.' + TARGET_HOST },
  { weight: 2,  method: 'GET', path: '/', host: 'www.' + TARGET_HOST },
];

// Build weighted pool
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
const POOL = [];
for (const ep of ENDPOINTS) {
  for (let i = 0; i < ep.weight; i++) POOL.push(ep);
}

// --- Stats ---
let totalRequests = 0;
let status2xx = 0;
let status3xx = 0;
let status4xx = 0;
let status429 = 0;
let status5xx = 0;
let networkErrors = 0;
const latencies = [];
const statusCounts = new Map();

// --- Request runner ---
function makeRequest() {
  return new Promise((resolve) => {
    const ep = pick(POOL);
    const host = ep.host || TARGET_HOST;
    const start = performance.now();

    const options = {
      hostname: TARGET_HOST,
      port: TARGET_PORT,
      path: ep.path,
      method: ep.method,
      headers: {
        'Host': host,
        'Content-Type': 'application/json',
        'User-Agent': 'BizarreCRM-StressTest/1.0',
      },
      rejectUnauthorized: false,
      timeout: 10000,
    };

    if (ep.body) {
      options.headers['Content-Length'] = Buffer.byteLength(ep.body);
    }

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        const latency = performance.now() - start;
        latencies.push(latency);
        totalRequests++;

        const code = res.statusCode;
        statusCounts.set(code, (statusCounts.get(code) || 0) + 1);

        if (code >= 200 && code < 300) status2xx++;
        else if (code >= 300 && code < 400) status3xx++;
        else if (code === 429) status429++;
        else if (code >= 400 && code < 500) status4xx++;
        else if (code >= 500) status5xx++;

        resolve();
      });
    });

    req.on('error', () => {
      const latency = performance.now() - start;
      latencies.push(latency);
      totalRequests++;
      networkErrors++;
      resolve();
    });

    req.on('timeout', () => { req.destroy(); });

    if (ep.body) req.write(ep.body);
    req.end();
  });
}

// --- Worker loop ---
async function worker(endTime) {
  while (Date.now() < endTime) {
    await makeRequest();
  }
}

// --- Percentile ---
function percentile(sorted, p) {
  const idx = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

// --- Main ---
async function main() {
  console.log(`\n${'='.repeat(52)}`);
  console.log(`  STRESS TEST — ${TARGET_HOST}`);
  console.log(`  ${CONCURRENCY} concurrent workers × ${DURATION_SEC}s`);
  console.log(`  ${ENDPOINTS.length} endpoint patterns`);
  console.log(`${'='.repeat(52)}\n`);

  const endTime = Date.now() + DURATION_SEC * 1000;
  const startTime = Date.now();

  // Progress ticker
  const ticker = setInterval(() => {
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
    const rps = (totalRequests / (Date.now() - startTime) * 1000).toFixed(0);
    process.stdout.write(`\r  [${elapsed}s] ${totalRequests} reqs | ${rps} req/s | 2xx:${status2xx} 4xx:${status4xx} 429:${status429} 5xx:${status5xx} err:${networkErrors}`);
  }, 500);

  // Launch workers
  const workers = [];
  for (let i = 0; i < CONCURRENCY; i++) {
    workers.push(worker(endTime));
  }
  await Promise.all(workers);
  clearInterval(ticker);

  // --- Results ---
  const elapsed = (Date.now() - startTime) / 1000;
  const sorted = [...latencies].sort((a, b) => a - b);

  console.log(`\n\n${'='.repeat(52)}`);
  console.log(`  RESULTS`);
  console.log(`${'='.repeat(52)}`);
  console.log(`  Total requests:   ${totalRequests}`);
  console.log(`  Duration:         ${elapsed.toFixed(1)}s`);
  console.log(`  Throughput:       ${(totalRequests / elapsed).toFixed(0)} req/s`);
  console.log(`  2xx (success):    ${status2xx}`);
  console.log(`  3xx (redirect):   ${status3xx}`);
  console.log(`  401/403 (auth):   ${status4xx - status429}`);
  console.log(`  429 (rate limit): ${status429}`);
  console.log(`  5xx (server err): ${status5xx}`);
  console.log(`  Network errors:   ${networkErrors}`);
  console.log(`\n  Latency:`);
  console.log(`    Min:  ${sorted[0]?.toFixed(1)}ms`);
  console.log(`    p50:  ${percentile(sorted, 50)?.toFixed(1)}ms`);
  console.log(`    p90:  ${percentile(sorted, 90)?.toFixed(1)}ms`);
  console.log(`    p95:  ${percentile(sorted, 95)?.toFixed(1)}ms`);
  console.log(`    p99:  ${percentile(sorted, 99)?.toFixed(1)}ms`);
  console.log(`    Max:  ${sorted[sorted.length - 1]?.toFixed(1)}ms`);

  console.log(`\n  Status code breakdown:`);
  const sortedCodes = [...statusCounts.entries()].sort((a, b) => b[1] - a[1]);
  for (const [code, count] of sortedCodes) {
    const pct = ((count / totalRequests) * 100).toFixed(1);
    console.log(`    ${code}: ${count} (${pct}%)`);
  }

  // Verdict
  console.log(`\n  ${'─'.repeat(48)}`);
  if (status5xx === 0 && networkErrors < totalRequests * 0.01) {
    console.log(`  ✅ SERVER SURVIVED — 0 crashes, rate limiter held`);
  } else if (status5xx > 0) {
    console.log(`  ⚠️  ${status5xx} SERVER ERRORS — check server logs`);
  }
  if (status429 > 0) {
    console.log(`  🛡️  Rate limiter triggered ${status429} times — working as expected`);
  }
  console.log(`\n${'='.repeat(52)}\n`);
}

main().catch(console.error);
