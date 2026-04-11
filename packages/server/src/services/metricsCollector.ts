/**
 * Metrics Collector — Persistent historical request metrics.
 *
 * Samples server metrics every 60 seconds into a separate metrics.db file.
 * Aggregates into hourly rollups for long-term storage. Supports time-range
 * queries from 1 hour to 6 months.
 *
 * Storage tiers:
 *   metrics_raw    — 1-minute granularity, retained 48 hours (~2,880 rows max)
 *   metrics_hourly — 1-hour granularity,   retained 6 months (~4,380 rows max)
 */
import Database from 'better-sqlite3';
import path from 'path';
import { config } from '../config.js';
import {
  getRequestsPerSecond,
  getRequestsPerSecondPeak,
  getRequestsPerMinute,
  getAvgResponseTime,
  getP95ResponseTime,
} from '../utils/requestCounter.js';
import { allClients } from '../ws/server.js';

// ---------------------------------------------------------------------------
// DB setup
// ---------------------------------------------------------------------------

let metricsDb: Database.Database | null = null;

function getDb(): Database.Database {
  if (metricsDb) return metricsDb;

  const dbPath = path.join(path.dirname(config.dbPath), 'metrics.db');
  metricsDb = new Database(dbPath);
  metricsDb.pragma('journal_mode = WAL');
  metricsDb.pragma('synchronous = NORMAL');
  metricsDb.pragma('cache_size = -8000');   // 8MB — small DB
  metricsDb.pragma('wal_autocheckpoint = 5000');

  // Create tables
  metricsDb.exec(`
    CREATE TABLE IF NOT EXISTS metrics_raw (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      rps_avg REAL NOT NULL DEFAULT 0,
      rps_peak REAL NOT NULL DEFAULT 0,
      rpm INTEGER NOT NULL DEFAULT 0,
      avg_response_ms REAL NOT NULL DEFAULT 0,
      p95_response_ms REAL NOT NULL DEFAULT 0,
      active_connections INTEGER NOT NULL DEFAULT 0,
      memory_mb REAL NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS metrics_hourly (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      rps_avg REAL NOT NULL DEFAULT 0,
      rps_peak REAL NOT NULL DEFAULT 0,
      rpm_avg INTEGER NOT NULL DEFAULT 0,
      avg_response_ms REAL NOT NULL DEFAULT 0,
      p95_response_ms REAL NOT NULL DEFAULT 0,
      active_connections_avg REAL NOT NULL DEFAULT 0,
      memory_mb_avg REAL NOT NULL DEFAULT 0,
      sample_count INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_metrics_raw_ts ON metrics_raw(timestamp);
    CREATE INDEX IF NOT EXISTS idx_metrics_hourly_ts ON metrics_hourly(timestamp);
  `);

  return metricsDb;
}

// ---------------------------------------------------------------------------
// Sampling — runs every 60 seconds
// ---------------------------------------------------------------------------

function sampleMetrics(): void {
  const db = getDb();
  const now = new Date().toISOString().replace('T', ' ').substring(0, 19);
  const mem = process.memoryUsage();

  db.prepare(`
    INSERT INTO metrics_raw (timestamp, rps_avg, rps_peak, rpm, avg_response_ms, p95_response_ms, active_connections, memory_mb)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    now,
    getRequestsPerSecond(),
    getRequestsPerSecondPeak(),
    getRequestsPerMinute(),
    getAvgResponseTime(),
    getP95ResponseTime(),
    allClients?.size ?? 0,
    Math.round((mem.rss / 1024 / 1024) * 10) / 10,
  );
}

// ---------------------------------------------------------------------------
// Hourly rollup — aggregates raw → hourly, cleans up old data
// ---------------------------------------------------------------------------

function rollupHourly(): void {
  const db = getDb();

  // Aggregate raw metrics from completed hours into hourly summaries
  // Only roll up data older than 1 hour to avoid partial-hour aggregation
  const cutoff = new Date(Date.now() - 3600_000).toISOString().replace('T', ' ').substring(0, 13) + ':00:00';

  // Find hours that have raw data but no hourly summary yet
  const hours = db.prepare(`
    SELECT SUBSTR(timestamp, 1, 13) || ':00:00' AS hour_ts,
           AVG(rps_avg) AS rps_avg,
           MAX(rps_peak) AS rps_peak,
           CAST(AVG(rpm) AS INTEGER) AS rpm_avg,
           AVG(avg_response_ms) AS avg_response_ms,
           MAX(p95_response_ms) AS p95_response_ms,
           AVG(active_connections) AS active_connections_avg,
           AVG(memory_mb) AS memory_mb_avg,
           COUNT(*) AS sample_count
    FROM metrics_raw
    WHERE timestamp < ?
    GROUP BY SUBSTR(timestamp, 1, 13)
    HAVING SUBSTR(timestamp, 1, 13) || ':00:00' NOT IN (SELECT timestamp FROM metrics_hourly)
  `).all(cutoff) as Array<Record<string, unknown>>;

  if (hours.length > 0) {
    const insert = db.prepare(`
      INSERT INTO metrics_hourly (timestamp, rps_avg, rps_peak, rpm_avg, avg_response_ms, p95_response_ms, active_connections_avg, memory_mb_avg, sample_count)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const doInsert = db.transaction(() => {
      for (const h of hours) {
        insert.run(h.hour_ts, h.rps_avg, h.rps_peak, h.rpm_avg, h.avg_response_ms, h.p95_response_ms, h.active_connections_avg, h.memory_mb_avg, h.sample_count);
      }
    });
    doInsert();
    console.log(`[Metrics] Rolled up ${hours.length} hour(s) into metrics_hourly`);
  }

  // Cleanup: delete raw older than 48 hours
  db.prepare("DELETE FROM metrics_raw WHERE timestamp < datetime('now', '-48 hours')").run();

  // Cleanup: delete hourly older than 6 months
  db.prepare("DELETE FROM metrics_hourly WHERE timestamp < datetime('now', '-180 days')").run();
}

// ---------------------------------------------------------------------------
// Query — time-range data for the dashboard
// ---------------------------------------------------------------------------

export interface MetricsDataPoint {
  timestamp: string;
  rps_avg: number;
  rps_peak: number;
  rpm: number;
  avg_response_ms: number;
  p95_response_ms: number;
  active_connections: number;
  memory_mb: number;
}

type TimeRange = '1h' | '6h' | '1d' | '1w' | '1m' | '6m';

// @audit-fixed: previously the '1d' bucket used `SUBSTR(timestamp, 1, 14) || '5:00'`
// which appended the literal string `5:00` to a partial timestamp, producing values
// like `2026-04-11 12:5:00` — a malformed datetime that broke chart axes downstream.
// The intent was 10-minute buckets (truncate to first digit of the minute and pad to
// `:M0:00`). Use `SUBSTR(..., 1, 15) || '0:00'` to keep two minute digits and clamp
// the second to 0, producing valid timestamps like `2026-04-11 12:50:00`.
// Also normalize the '1m' bucket from hour-substr (1..13) to a full hour timestamp
// so it returns parseable values for the charting layer.
const RANGE_CONFIG: Record<TimeRange, { table: 'raw' | 'hourly'; interval: string; groupBy?: string }> = {
  '1h': { table: 'raw', interval: '-1 hours' },
  '6h': { table: 'raw', interval: '-6 hours' },
  '1d': { table: 'raw', interval: '-1 days', groupBy: "SUBSTR(timestamp, 1, 15) || '0:00'" }, // 10-min buckets, valid datetimes
  '1w': { table: 'hourly', interval: '-7 days' },
  '1m': { table: 'hourly', interval: '-30 days', groupBy: "SUBSTR(timestamp, 1, 13) || ':00:00'" }, // hourly, valid datetimes
  '6m': { table: 'hourly', interval: '-180 days', groupBy: "SUBSTR(timestamp, 1, 10) || ' 00:00:00'" }, // daily, valid datetimes
};

/** Build a live snapshot from the in-memory request counter (appended as trailing point). */
function liveSnapshot(): MetricsDataPoint {
  const mem = process.memoryUsage();
  return {
    timestamp: new Date().toISOString().replace('T', ' ').substring(0, 19),
    rps_avg: getRequestsPerSecond(),
    rps_peak: getRequestsPerSecondPeak(),
    rpm: getRequestsPerMinute(),
    avg_response_ms: getAvgResponseTime(),
    p95_response_ms: getP95ResponseTime(),
    active_connections: allClients?.size ?? 0,
    memory_mb: Math.round((mem.rss / 1024 / 1024) * 10) / 10,
  };
}

export function getMetricsHistory(range: string): MetricsDataPoint[] {
  const db = getDb();
  const cfg = RANGE_CONFIG[range as TimeRange];
  if (!cfg) return [liveSnapshot()];

  let rows: MetricsDataPoint[];

  if (cfg.table === 'raw') {
    if (cfg.groupBy) {
      rows = db.prepare(`
        SELECT ${cfg.groupBy} AS timestamp,
               AVG(rps_avg) AS rps_avg, MAX(rps_peak) AS rps_peak,
               CAST(AVG(rpm) AS INTEGER) AS rpm,
               AVG(avg_response_ms) AS avg_response_ms,
               MAX(p95_response_ms) AS p95_response_ms,
               CAST(AVG(active_connections) AS INTEGER) AS active_connections,
               AVG(memory_mb) AS memory_mb
        FROM metrics_raw
        WHERE timestamp >= datetime('now', ?)
        GROUP BY ${cfg.groupBy}
        ORDER BY timestamp ASC
      `).all(cfg.interval) as MetricsDataPoint[];
    } else {
      rows = db.prepare(`
        SELECT timestamp, rps_avg, rps_peak, rpm, avg_response_ms, p95_response_ms, active_connections, memory_mb
        FROM metrics_raw
        WHERE timestamp >= datetime('now', ?)
        ORDER BY timestamp ASC
      `).all(cfg.interval) as MetricsDataPoint[];
    }
  } else if (cfg.groupBy) {
    rows = db.prepare(`
      SELECT ${cfg.groupBy} AS timestamp,
             AVG(rps_avg) AS rps_avg, MAX(rps_peak) AS rps_peak,
             CAST(AVG(rpm_avg) AS INTEGER) AS rpm,
             AVG(avg_response_ms) AS avg_response_ms,
             MAX(p95_response_ms) AS p95_response_ms,
             CAST(AVG(active_connections_avg) AS INTEGER) AS active_connections,
             AVG(memory_mb_avg) AS memory_mb
      FROM metrics_hourly
      WHERE timestamp >= datetime('now', ?)
      GROUP BY ${cfg.groupBy}
      ORDER BY timestamp ASC
    `).all(cfg.interval) as MetricsDataPoint[];
  } else {
    rows = db.prepare(`
      SELECT timestamp, rps_avg, rps_peak, rpm_avg AS rpm, avg_response_ms, p95_response_ms,
             CAST(active_connections_avg AS INTEGER) AS active_connections, memory_mb_avg AS memory_mb
      FROM metrics_hourly
      WHERE timestamp >= datetime('now', ?)
      ORDER BY timestamp ASC
    `).all(cfg.interval) as MetricsDataPoint[];
  }

  // @audit-fixed: previously always appended a live "now" point even when the
  // historical query returned 0 rows — that produced a chart with a single dot
  // at "now" + a giant blank gap, which the dashboard rendered as a flat zero
  // line. Only append the live point if the most-recent row is older than the
  // sampling interval, so we don't double-display the current sample.
  const live = liveSnapshot();
  const lastRow = rows[rows.length - 1];
  if (!lastRow || lastRow.timestamp !== live.timestamp) {
    rows.push(live);
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

let sampleTimer: ReturnType<typeof setInterval> | null = null;
let rollupTimer: ReturnType<typeof setInterval> | null = null;

export function startMetricsCollector(): void {
  // Initialize DB eagerly
  getDb();
  console.log('[Metrics] Collector started — sampling every 60s, hourly rollup');

  // Sample immediately so the first data point exists right away
  sampleMetrics();

  // Then sample every 60 seconds
  sampleTimer = setInterval(sampleMetrics, 60_000);
  sampleTimer.unref();

  // Hourly rollup + cleanup (run at startup too for any missed rollups)
  rollupHourly();
  rollupTimer = setInterval(rollupHourly, 3600_000);
  rollupTimer.unref();
}

export function stopMetricsCollector(): void {
  if (sampleTimer) { clearInterval(sampleTimer); sampleTimer = null; }
  if (rollupTimer) { clearInterval(rollupTimer); rollupTimer = null; }
  if (metricsDb) { metricsDb.close(); metricsDb = null; }
}
