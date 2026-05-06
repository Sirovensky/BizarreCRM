import fs from 'fs';
import os from 'os';
import path from 'path';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const LOG_ENV_KEYS = [
  'LOG_FILE_ENABLED',
  'LOG_FILE_PATH',
  'LOG_FILE_MAX_SIZE',
  'LOG_FILE_MAX_BYTES',
  'LOG_FILE_MAX_FILES',
  'LOG_FORMAT',
  'LOG_LEVEL',
  'NODE_ENV',
] as const;

const originalEnv = new Map<string, string | undefined>();
let tempDir: string;

async function importLogger() {
  vi.resetModules();
  return import('../logger.js');
}

beforeEach(() => {
  for (const key of LOG_ENV_KEYS) {
    originalEnv.set(key, process.env[key]);
    delete process.env[key];
  }
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bizarre-logger-'));
});

afterEach(() => {
  vi.restoreAllMocks();
  for (const key of LOG_ENV_KEYS) {
    const original = originalEnv.get(key);
    if (original === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = original;
    }
  }
  originalEnv.clear();
  fs.rmSync(tempDir, { recursive: true, force: true });
});

describe('logger rotating file sink', () => {
  it('writes the same PII-redacted line to stdout and the configured file', async () => {
    const filePath = path.join(tempDir, 'server.log');
    process.env.NODE_ENV = 'production';
    process.env.LOG_LEVEL = 'info';
    process.env.LOG_FORMAT = 'json';
    process.env.LOG_FILE_PATH = filePath;
    process.env.LOG_FILE_MAX_SIZE = '1M';
    process.env.LOG_FILE_MAX_FILES = '3';

    const infoSpy = vi.spyOn(console, 'info').mockImplementation(() => {});
    const { createLogger } = await importLogger();

    createLogger('logger-test').info('customer contact', {
      email: 'alice@example.com',
      phone: '+15551234567',
      address: '123 Main Street',
      nested: { to: '+15559876543' },
    });

    const fileLine = fs.readFileSync(filePath, 'utf8').trim();
    expect(infoSpy).toHaveBeenCalledWith(fileLine);

    const entry = JSON.parse(fileLine);
    expect(entry).toMatchObject({
      level: 'info',
      module: 'logger-test',
      message: 'customer contact',
      email: '***@example.com',
      phone: '***-***-4567',
      address: '[REDACTED:address len=15]',
      nested: { to: '***-***-6543' },
    });
  });

  it('rotates before exceeding max size and respects the max-files cap', async () => {
    const filePath = path.join(tempDir, 'server.log');
    process.env.LOG_LEVEL = 'info';
    process.env.LOG_FORMAT = 'json';
    process.env.LOG_FILE_PATH = filePath;
    process.env.LOG_FILE_MAX_SIZE = '220';
    process.env.LOG_FILE_MAX_FILES = '3';

    vi.spyOn(console, 'info').mockImplementation(() => {});
    const { createLogger } = await importLogger();
    const log = createLogger('rotate-test');

    for (let i = 0; i < 6; i += 1) {
      log.info(`rotation-${i}`, { payload: 'x'.repeat(120) });
    }

    expect(fs.existsSync(filePath)).toBe(true);
    expect(fs.existsSync(`${filePath}.1`)).toBe(true);
    expect(fs.existsSync(`${filePath}.2`)).toBe(true);
    expect(fs.existsSync(`${filePath}.3`)).toBe(false);
    expect(fs.readFileSync(filePath, 'utf8')).toContain('rotation-5');
    expect(fs.readFileSync(`${filePath}.1`, 'utf8')).toContain('rotation-4');
    expect(fs.readFileSync(`${filePath}.2`, 'utf8')).toContain('rotation-3');
  });

  it('does not throw when the file sink fails', async () => {
    process.env.LOG_LEVEL = 'info';
    process.env.LOG_FILE_PATH = tempDir;

    vi.spyOn(console, 'info').mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { createLogger } = await importLogger();
    const log = createLogger('failure-test');

    expect(() => log.info('first write')).not.toThrow();
    expect(() => log.info('second write')).not.toThrow();
    expect(errorSpy).toHaveBeenCalledTimes(1);
    expect(errorSpy.mock.calls[0][0]).toContain('rotating file sink disabled');
  });
});
