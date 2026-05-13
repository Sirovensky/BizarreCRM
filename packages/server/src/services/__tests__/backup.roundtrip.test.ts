import { afterEach, describe, expect, it } from 'vitest';
import { promises as fsp } from 'fs';
import path from 'path';
import os from 'os';
import crypto from 'crypto';
import { encryptFile, decryptFile } from '../backup.js';

const tmpFiles: string[] = [];

async function makeTmp(bytes: Buffer): Promise<string> {
  const p = path.join(os.tmpdir(), `bizcrm-backup-${crypto.randomBytes(8).toString('hex')}.db`);
  await fsp.writeFile(p, bytes);
  tmpFiles.push(p);
  return p;
}

afterEach(async () => {
  while (tmpFiles.length) {
    const p = tmpFiles.pop()!;
    for (const candidate of [p, `${p}.enc`, `${p}.restored`]) {
      try { await fsp.unlink(candidate); } catch { /* missing is fine */ }
    }
  }
});

describe('backup encryptFile/decryptFile round-trip (PROD112)', () => {
  it('decrypts a backup back to byte-equal plaintext', async () => {
    const plaintext = crypto.randomBytes(2048);
    const src = await makeTmp(plaintext);

    const encPath = await encryptFile(src);
    expect(encPath).toBe(`${src}.enc`);
    // Original was unlinked
    await expect(fsp.access(src)).rejects.toBeTruthy();

    const encBytes = await fsp.readFile(encPath);
    expect(encBytes.equals(plaintext)).toBe(false);
    // v1 magic header (4 bytes 'BZBK') + version byte (0x01)
    expect(encBytes.subarray(0, 4).equals(Buffer.from('BZBK', 'ascii'))).toBe(true);
    expect(encBytes[4]).toBe(1);

    const restored = `${src}.restored`;
    await decryptFile(encPath, restored);
    const restoredBytes = await fsp.readFile(restored);
    tmpFiles.push(restored);

    expect(restoredBytes.equals(plaintext)).toBe(true);
  });

  it('survives a SQLite-shaped payload (header + rows + WAL-like footer)', async () => {
    const header = Buffer.from('SQLite format 3\0');
    const middle = crypto.randomBytes(8192);
    const footer = Buffer.from('eof-marker');
    const plaintext = Buffer.concat([header, middle, footer]);
    const src = await makeTmp(plaintext);

    const encPath = await encryptFile(src);
    const restored = `${src}.restored`;
    await decryptFile(encPath, restored);
    tmpFiles.push(restored);

    const restoredBytes = await fsp.readFile(restored);
    expect(restoredBytes.length).toBe(plaintext.length);
    expect(restoredBytes.equals(plaintext)).toBe(true);
  });

  it('rejects a tampered ciphertext (auth tag mismatch)', async () => {
    const plaintext = crypto.randomBytes(512);
    const src = await makeTmp(plaintext);
    const encPath = await encryptFile(src);

    // Flip a byte in the ciphertext region (well past the header).
    const enc = await fsp.readFile(encPath);
    enc[enc.length - 1] ^= 0xff;
    await fsp.writeFile(encPath, enc);

    const restored = `${src}.restored`;
    await expect(decryptFile(encPath, restored)).rejects.toBeTruthy();
  });
});
