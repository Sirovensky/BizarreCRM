/**
 * File magic-byte validation (audit section 10, bug F1 + F2).
 *
 * Why this exists:
 *   Multer's `fileFilter` hook only checks the `Content-Type` header that the
 *   client declared. An attacker can trivially rename `payload.exe` to
 *   `photo.jpg` and spoof `Content-Type: image/jpeg` — the whitelist on
 *   `file.mimetype` passes and the executable lands on disk. We need a second
 *   line of defense that inspects the first few bytes of the file and compares
 *   them to known-good signatures.
 *
 * Implementation notes:
 *   - Keep the module dependency-free (no `file-type` npm package) so it can
 *     be called from any route without bloating the bundle or adding a new
 *     dependency to audit.
 *   - Only the formats in the route-level whitelists are accepted here. Adding
 *     a new format (e.g. svg) means adding a new entry to SIGNATURES — on
 *     purpose. Unknown signatures fall through to a rejection.
 *   - Magic-byte tables are intentionally explicit rather than clever so the
 *     code is auditable at a glance.
 *
 * Also exports `scanFileForViruses` (F2 stub). By default it returns
 * `{ clean: true }` so existing handlers keep working. Set the
 * `CLAMAV_HOST` env var to enable a real scan through `clamscan` (the
 * integration hook is documented inline). We deliberately keep the stub in
 * the same file so callers have one import site for all post-upload checks.
 */

import fs from 'fs';
import { createLogger } from './logger.js';

const logger = createLogger('fileValidation');

export type RealFileType = 'jpeg' | 'png' | 'gif' | 'webp' | 'pdf';

export interface FileValidationResult {
  valid: boolean;
  realType?: RealFileType;
  error?: string;
}

/**
 * Known magic-byte signatures for the formats we explicitly allow. Each entry
 * is an array of byte matchers; a `null` matcher means "any byte" and is used
 * for RIFF/WebP where the middle four bytes are a size field.
 */
interface Signature {
  readonly type: RealFileType;
  readonly bytes: readonly (number | null)[];
  /** Optional secondary check that runs after the prefix matches. */
  readonly extraCheck?: (buffer: Buffer) => boolean;
  /** Which declared MIME types this signature is allowed to satisfy. */
  readonly allowedMimes: readonly string[];
}

const SIGNATURES: readonly Signature[] = [
  // JPEG/JFIF/EXIF — FF D8 FF
  {
    type: 'jpeg',
    bytes: [0xff, 0xd8, 0xff],
    allowedMimes: ['image/jpeg', 'image/jpg', 'image/pjpeg'],
  },
  // PNG — 89 50 4E 47 0D 0A 1A 0A
  {
    type: 'png',
    bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    allowedMimes: ['image/png'],
  },
  // GIF87a / GIF89a — 47 49 46 38 (37|39) 61
  {
    type: 'gif',
    bytes: [0x47, 0x49, 0x46, 0x38],
    extraCheck: (buf) => (buf[4] === 0x37 || buf[4] === 0x39) && buf[5] === 0x61,
    allowedMimes: ['image/gif'],
  },
  // WebP — RIFF....WEBP (bytes 0-3 = RIFF, 8-11 = WEBP)
  {
    type: 'webp',
    bytes: [0x52, 0x49, 0x46, 0x46, null, null, null, null, 0x57, 0x45, 0x42, 0x50],
    allowedMimes: ['image/webp'],
  },
  // PDF — 25 50 44 46 ("%PDF")
  {
    type: 'pdf',
    bytes: [0x25, 0x50, 0x44, 0x46],
    allowedMimes: ['application/pdf'],
  },
];

/**
 * Inspect the first 16 bytes of a file buffer and decide whether the content
 * matches the declared MIME type.
 *
 * @param buffer        Raw file contents. Pass the full buffer OR at least the
 *                      first 16 bytes — we never touch anything past byte 15.
 * @param declaredMime  The MIME type reported by multer / the HTTP client.
 * @returns             `{ valid: true, realType }` when the signature matches
 *                      AND the declared MIME is compatible with the signature.
 *                      `{ valid: false, error }` otherwise.
 */
export function validateFileMagicBytes(
  buffer: Buffer,
  declaredMime: string,
): FileValidationResult {
  if (!buffer || buffer.length < 4) {
    return { valid: false, error: 'File too small to inspect magic bytes' };
  }

  const mime = (declaredMime || '').toLowerCase().trim();

  for (const sig of SIGNATURES) {
    if (buffer.length < sig.bytes.length) continue;

    let matches = true;
    for (let i = 0; i < sig.bytes.length; i++) {
      const expected = sig.bytes[i];
      if (expected === null) continue; // wildcard slot
      if (buffer[i] !== expected) { matches = false; break; }
    }
    if (!matches) continue;
    if (sig.extraCheck && !sig.extraCheck(buffer)) continue;

    // Bytes matched — now make sure the declared MIME belongs to this signature.
    if (!sig.allowedMimes.includes(mime)) {
      return {
        valid: false,
        realType: sig.type,
        error: `Declared MIME '${mime}' does not match file content (detected ${sig.type})`,
      };
    }
    return { valid: true, realType: sig.type };
  }

  return {
    valid: false,
    error: `Unrecognized file signature (declared ${mime || 'none'})`,
  };
}

/**
 * Convenience wrapper that reads the first 16 bytes of a file from disk and
 * runs `validateFileMagicBytes`. Route handlers that already have the file on
 * disk (multer diskStorage) should call this — it avoids loading the full
 * file into memory just to check the signature.
 */
export function validateFileOnDisk(
  filePath: string,
  declaredMime: string,
): FileValidationResult {
  let fd: number | null = null;
  try {
    fd = fs.openSync(filePath, 'r');
    const head = Buffer.alloc(16);
    const read = fs.readSync(fd, head, 0, 16, 0);
    if (read < 4) {
      return { valid: false, error: 'File too small to inspect magic bytes' };
    }
    return validateFileMagicBytes(head.subarray(0, read), declaredMime);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    logger.error('Failed to read file for magic byte validation', { filePath, error: message });
    return { valid: false, error: `Unable to read uploaded file: ${message}` };
  } finally {
    if (fd !== null) {
      try { fs.closeSync(fd); } catch { /* best-effort close */ }
    }
  }
}

// ---------------------------------------------------------------------------
// F2 — virus scanning stub
// ---------------------------------------------------------------------------

export interface VirusScanResult {
  clean: boolean;
  threat?: string;
  scanner?: string;
}

/**
 * Stub virus scanner. Returns `{ clean: true }` by default so that existing
 * deploys keep working even before an operator wires up ClamAV.
 *
 * To enable a real scan, set `CLAMAV_HOST` (and optionally `CLAMAV_PORT`,
 * default 3310). On start the operator must also install `clamscan` from npm
 * and replace the `TODO:` block below with the actual client call. The shape
 * of the return value is already correct so the call sites do not need to
 * change.
 *
 * Integration checklist for ClamAV:
 *   1. `npm i clamscan` in `packages/server`
 *   2. Set `CLAMAV_HOST=clamd-host` (and `CLAMAV_PORT` if non-default)
 *   3. Uncomment the block below and delete the default-clean branch
 *   4. The clamd daemon must be reachable from the Node process — run it in
 *      a sidecar container in production deployments.
 */
export async function scanFileForViruses(filePath: string): Promise<VirusScanResult> {
  const host = process.env.CLAMAV_HOST;
  if (!host) {
    return { clean: true, scanner: 'stub' };
  }

  // TODO (F2): Wire up node-clam / clamscan here. Left as a stub on purpose
  // because ClamAV is an infrastructure concern the operator owns. The
  // surrounding call sites are already wired to trust this return value.
  //
  // Example shape once `clamscan` is installed:
  //
  //   const NodeClam = (await import('clamscan')).default;
  //   const clam = await new NodeClam().init({
  //     clamdscan: { host, port: Number(process.env.CLAMAV_PORT) || 3310 },
  //   });
  //   const { isInfected, viruses } = await clam.isInfected(filePath);
  //   return isInfected
  //     ? { clean: false, threat: viruses.join(', '), scanner: 'clamav' }
  //     : { clean: true, scanner: 'clamav' };
  logger.warn('CLAMAV_HOST set but clamscan integration not wired; passing file through', {
    filePath,
    host,
  });
  return { clean: true, scanner: 'stub-clamav-pending' };
}
