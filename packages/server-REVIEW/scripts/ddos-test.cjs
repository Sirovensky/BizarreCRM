/**
 * Maximum throughput stress test — pushes as many requests as physically possible.
 * Uses HTTP keep-alive connection pooling to avoid TLS handshake per request.
 *
 * Usage: node scripts/ddos-test.cjs [duration_seconds] [connections] [target_host]
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

const DURATION_SEC = parseInt(process.argv[2]) || 60;
const CONNECTIONS = parseInt(process.argv[3]) || 500;
const TARGET_HOST = process.argv[4] || process.env.BASE_DOMAIN || readBaseDomainFromEnvFile() || 'localhost';

// Keep-alive agent — reuses TLS connections (massive throughput boost)
const agent = new https.Agent({
  keepAlive: true,
  keepAliveMsecs: 30000,
  maxSockets: CONNECTIONS,
  maxFreeSockets: CONNECTIONS,
  rejectUnauthorized: false,
});

const PATHS = [
  '/', '/api/v1/info', '/api/v1/health',
  '/api/v1/tickets', '/api/v1/customers', '/api/v1/inventory',
  '/api/v1/invoices', '/api/v1/search?q=test', '/api/v1/reports/dashboard',
  '/api/v1/settings/config', '/api/v1/employees', '/api/v1/pos/products',
  '/api/v1/signup/check-slug/test', '/api/v1/nonexistent',
  '/api/v1/tickets/kanban', '/api/v1/tickets/stalled',
];
const HOSTS = [
  TARGET_HOST,
  'fakeshop.' + TARGET_HOST,
  'test.' + TARGET_HOST,
  'admin.' + TARGET_HOST,
];

let total = 0, s2xx = 0, s4xx = 0, s429 = 0, s5xx = 0, errs = 0;
let minMs = Infinity, maxMs = 0, sumMs = 0;
const statusMap = new Map();

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

function fire() {
  const start = performance.now();
  const req = https.get({
    hostname: TARGET_HOST,
    port: 443,
    path: pick(PATHS),
    agent: agent,
    headers: { 'Host': pick(HOSTS) },
    timeout: 8000,
  }, (res) => {
    res.resume(); // drain body
    res.on('end', () => {
      const ms = performance.now() - start;
      total++;
      sumMs += ms;
      if (ms < minMs) minMs = ms;
      if (ms > maxMs) maxMs = ms;
      const c = res.statusCode;
      statusMap.set(c, (statusMap.get(c) || 0) + 1);
      if (c >= 200 && c < 300) s2xx++;
      else if (c === 429) s429++;
      else if (c >= 400 && c < 500) s4xx++;
      else if (c >= 500) s5xx++;
    });
  });
  req.on('error', () => { total++; errs++; });
  req.on('timeout', () => { req.destroy(); });
}

async function main() {
  console.log(`\n${'='.repeat(56)}`);
  console.log(`  MAX THROUGHPUT TEST — ${TARGET_HOST}`);
  console.log(`  ${CONNECTIONS} keep-alive connections × ${DURATION_SEC}s`);
  console.log(`  ${PATHS.length} paths × ${HOSTS.length} hosts`);
  console.log(`${'='.repeat(56)}\n`);

  const endTime = Date.now() + DURATION_SEC * 1000;
  const startTime = Date.now();

  // Fire requests as fast as possible from multiple "guns"
  const GUNS = Math.min(CONNECTIONS, 2000);
  const gunLoop = async (id) => {
    while (Date.now() < endTime) {
      fire();
      // Tiny yield every few requests to not starve the event loop
      if (total % 100 === 0) await new Promise(r => setImmediate(r));
    }
  };

  // Progress
  const ticker = setInterval(() => {
    const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
    const rps = (total / ((Date.now() - startTime) / 1000)).toFixed(0);
    const avgMs = total > 0 ? (sumMs / total).toFixed(0) : 0;
    process.stdout.write(`\r  [${elapsed}s] ${total} reqs | ${rps} req/s | 2xx:${s2xx} 429:${s429} 5xx:${s5xx} err:${errs} | avg:${avgMs}ms max:${maxMs.toFixed(0)}ms`);
  }, 500);

  // Launch all guns
  const guns = [];
  for (let i = 0; i < GUNS; i++) {
    guns.push(gunLoop(i));
  }
  await Promise.all(guns);

  // Wait for in-flight requests to finish
  await new Promise(r => setTimeout(r, 3000));
  clearInterval(ticker);

  const elapsed = (Date.now() - startTime) / 1000;
  const rps = (total / elapsed).toFixed(0);
  const avgMs = total > 0 ? (sumMs / total).toFixed(1) : 0;

  console.log(`\n\n${'='.repeat(56)}`);
  console.log(`  RESULTS`);
  console.log(`${'='.repeat(56)}`);
  console.log(`  Total requests:   ${total.toLocaleString()}`);
  console.log(`  Duration:         ${elapsed.toFixed(1)}s`);
  console.log(`  Throughput:       ${rps} req/s`);
  console.log(`  2xx:              ${s2xx.toLocaleString()}`);
  console.log(`  4xx (no auth):    ${(s4xx - s429).toLocaleString()}`);
  console.log(`  429 (rate limit): ${s429.toLocaleString()}`);
  console.log(`  5xx:              ${s5xx.toLocaleString()}`);
  console.log(`  Network errors:   ${errs.toLocaleString()}`);
  console.log(`  Avg latency:      ${avgMs}ms`);
  console.log(`  Min latency:      ${minMs.toFixed(1)}ms`);
  console.log(`  Max latency:      ${maxMs.toFixed(1)}ms`);

  console.log(`\n  Status codes:`);
  [...statusMap.entries()].sort((a, b) => b[1] - a[1]).forEach(([code, count]) => {
    console.log(`    ${code}: ${count.toLocaleString()} (${((count / total) * 100).toFixed(1)}%)`);
  });

  console.log(`\n  ${'─'.repeat(52)}`);
  if (s5xx === 0 && errs < total * 0.01) {
    console.log(`  ✅ SERVER SURVIVED — zero crashes`);
  } else if (s5xx > 0) {
    console.log(`  ⚠️  ${s5xx.toLocaleString()} origin errors (Cloudflare 530/521)`);
  }
  if (s429 > 0) {
    console.log(`  🛡️  Rate limiter blocked ${s429.toLocaleString()} requests`);
  }
  console.log(`\n${'='.repeat(56)}\n`);

  agent.destroy();
}

main().catch(console.error);
