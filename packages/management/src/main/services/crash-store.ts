import { app } from 'electron';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { logger } from './main-logger.js';

type DashboardCrashType = 'uncaughtException' | 'unhandledRejection';

export interface DashboardCrashContext {
  os: {
    type: string;
    platform: NodeJS.Platform;
    release: string;
    arch: string;
  };
  versions: {
    node: string;
    electron?: string;
    chrome?: string;
    v8?: string;
  };
  app: {
    name: string;
    version: string;
    isPackaged: boolean;
  };
}

export interface DashboardCrashEntry {
  id: string;
  timestamp: string;
  route: string;
  errorMessage: string;
  errorStack: string;
  type: DashboardCrashType;
  recovered: boolean;
  source: 'dashboard';
  context: DashboardCrashContext;
}

interface DashboardCrashData {
  crashes: DashboardCrashEntry[];
}

const DASHBOARD_CRASH_LOG_FILE = 'dashboard-crash-log.json';
const MAX_DASHBOARD_CRASH_ENTRIES = 500;
const MAX_ERROR_MESSAGE_CHARS = 1000;
const MAX_ERROR_STACK_CHARS = 4000;

let loaded = false;
let crashData: DashboardCrashData = { crashes: [] };

function truncate(value: string, maxChars: number): string {
  return value.length > maxChars ? `${value.slice(0, maxChars - 3)}...` : value;
}

function getCrashLogPath(): string {
  return path.join(app.getPath('userData'), DASHBOARD_CRASH_LOG_FILE);
}

function loadCrashData(): DashboardCrashData {
  try {
    const crashLogPath = getCrashLogPath();
    if (!fs.existsSync(crashLogPath)) return { crashes: [] };
    const parsed = JSON.parse(fs.readFileSync(crashLogPath, 'utf-8')) as { crashes?: unknown };
    return {
      crashes: Array.isArray(parsed.crashes)
        ? (parsed.crashes as DashboardCrashEntry[])
        : [],
    };
  } catch (err) {
    logger.warn('[Dashboard] Failed to load dashboard crash log; starting fresh', { error: err });
    return { crashes: [] };
  }
}

function ensureLoaded(): void {
  if (loaded) return;
  crashData = loadCrashData();
  loaded = true;
}

function saveCrashData(data: DashboardCrashData): void {
  try {
    const crashLogPath = getCrashLogPath();
    const dir = path.dirname(crashLogPath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const tmpPath = `${crashLogPath}.tmp.${process.pid}.${Date.now()}`;
    fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2), { encoding: 'utf-8', mode: 0o600 });
    fs.renameSync(tmpPath, crashLogPath);
  } catch (err) {
    logger.error('[Dashboard] Failed to save dashboard crash log', { error: err });
  }
}

function captureCrashContext(): DashboardCrashContext {
  return {
    os: {
      type: os.type(),
      platform: process.platform,
      release: os.release(),
      arch: process.arch,
    },
    versions: {
      node: process.versions.node,
      electron: process.versions.electron,
      chrome: process.versions.chrome,
      v8: process.versions.v8,
    },
    app: {
      name: app.getName(),
      version: app.getVersion(),
      isPackaged: app.isPackaged,
    },
  };
}

function normalizeCrashReason(reason: unknown): { message: string; stack: string } {
  if (reason instanceof Error) {
    return {
      message: truncate(reason.message || reason.name || 'Unknown error', MAX_ERROR_MESSAGE_CHARS),
      stack: truncate(reason.stack || reason.message || '', MAX_ERROR_STACK_CHARS),
    };
  }

  const message = typeof reason === 'string' ? reason : String(reason);
  return {
    message: truncate(message || 'Unknown rejection', MAX_ERROR_MESSAGE_CHARS),
    stack: '',
  };
}

export function recordDashboardCrash(
  type: DashboardCrashType,
  reason: unknown,
): DashboardCrashEntry | null {
  try {
    ensureLoaded();
    const normalized = normalizeCrashReason(reason);
    const entry: DashboardCrashEntry = {
      id: `dashboard-${crypto.randomUUID()}`,
      timestamp: new Date().toISOString(),
      route: 'dashboard:main',
      errorMessage: normalized.message,
      errorStack: normalized.stack,
      type,
      recovered: true,
      source: 'dashboard',
      context: captureCrashContext(),
    };

    const nextCrashes = [...crashData.crashes, entry];
    crashData = {
      crashes: nextCrashes.length > MAX_DASHBOARD_CRASH_ENTRIES
        ? nextCrashes.slice(nextCrashes.length - MAX_DASHBOARD_CRASH_ENTRIES)
        : nextCrashes,
    };
    saveCrashData(crashData);
    return entry;
  } catch (err) {
    logger.error('[Dashboard] Failed to record dashboard crash', { error: err });
    return null;
  }
}

export function getDashboardCrashLog(): readonly DashboardCrashEntry[] {
  ensureLoaded();
  return crashData.crashes;
}

export function clearDashboardCrashLog(): void {
  ensureLoaded();
  crashData = { crashes: [] };
  saveCrashData(crashData);
}
