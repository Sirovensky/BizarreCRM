/**
 * activityLog — lightweight helper to insert rows into activity_events.
 *
 * Designed to be called fire-and-forget from route handlers. Never throws:
 * any DB or serialization error is caught and logged as a warning so that
 * an audit failure never blocks the primary request path.
 */
import { createLogger } from './logger.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('activityLog');

// Cap metadata JSON at 8 KB to prevent log-table bloat.
const MAX_METADATA_BYTES = 8 * 1024;

interface ActivityLogParams {
  actor_user_id: number | null;
  entity_kind: string;
  entity_id?: number | null;
  action: string;
  metadata?: Record<string, unknown>;
}

/**
 * Insert one row into `activity_events`. Silently swallows any error.
 *
 * @param adb   - AsyncDb instance (req.asyncDb in route handlers)
 * @param params - Event descriptor
 */
export async function logActivity(
  adb: AsyncDb,
  params: ActivityLogParams,
): Promise<void> {
  try {
    let metaJson: string | null = null;
    if (params.metadata !== undefined) {
      let serialized: string;
      try {
        serialized = JSON.stringify(params.metadata);
      } catch {
        serialized = JSON.stringify({ error: 'unserializable_metadata' });
      }
      // Enforce the size cap — store a truncation marker rather than the raw blob.
      if (Buffer.byteLength(serialized, 'utf8') > MAX_METADATA_BYTES) {
        metaJson = JSON.stringify({ truncated: true, original_bytes: Buffer.byteLength(serialized, 'utf8') });
      } else {
        metaJson = serialized;
      }
    }

    await adb.run(
      `INSERT INTO activity_events (actor_user_id, entity_kind, entity_id, action, metadata_json)
       VALUES (?, ?, ?, ?, ?)`,
      params.actor_user_id ?? null,
      params.entity_kind,
      params.entity_id ?? null,
      params.action,
      metaJson,
    );
  } catch (err) {
    logger.warn('logActivity: failed to insert activity_event', {
      error: err instanceof Error ? err.message : String(err),
      action: params.action,
      entity_kind: params.entity_kind,
    });
  }
}
