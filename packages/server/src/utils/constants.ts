/**
 * Named constants for magic numbers used across the server.
 * Import from here instead of using hardcoded values.
 */

// ─── Pagination ──────────────────────────────────────────────────────────────
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 1000;
export const DEFAULT_PAGE = 1;

// ─── Rate Limiting ───────────────────────────────────────────────────────────
export const LOGIN_RATE_LIMIT_MAX = 5;
export const LOGIN_RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000; // 15 minutes
export const SMS_RATE_LIMIT_MAX = 5;
export const SMS_RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
export const TRACKING_RATE_LIMIT_MS = 5000; // 5 seconds between tracking requests

// ─── Tokens ──────────────────────────────────────────────────────────────────
export const ACCESS_TOKEN_EXPIRY = '1h';
export const REFRESH_TOKEN_EXPIRY_DAYS = 30;
export const CHALLENGE_TOKEN_TTL_MS = 5 * 60 * 1000; // 5 minutes
export const ADMIN_TOKEN_TTL_MS = 30 * 60 * 1000; // 30 minutes
/** TTL for idempotency key rows. Must stay in sync with retentionSweeper RULES (retentionDays: 1). */
export const IDEMPOTENCY_KEY_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

// ─── Timeouts ────────────────────────────────────────────────────────────────
export const SESSION_CLEANUP_INTERVAL_MS = 60 * 60 * 1000; // 1 hour
export const APPOINTMENT_REMINDER_INTERVAL_MS = 15 * 60 * 1000; // 15 minutes
export const APPOINTMENT_REMINDER_AHEAD_HOURS = 24;

// ─── File Uploads ────────────────────────────────────────────────────────────
export const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10MB
export const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

// ─── Validation ──────────────────────────────────────────────────────────────
export const MAX_NOTE_LENGTH = 10_000;
export const MAX_DATE_RANGE_DAYS = 365;
export const PIN_MIN_LENGTH = 4;
export const PIN_MAX_LENGTH = 8;
export const TOTP_CODE_LENGTH = 6;
export const BACKUP_CODE_COUNT = 8;
export const BCRYPT_ROUNDS = 12;

// ─── Business Logic ──────────────────────────────────────────────────────────
export const STALE_TICKET_WARN_DAYS = 3;
export const STALE_TICKET_CRITICAL_DAYS = 7;
export const DEFAULT_TAX_RATE = 8.865; // Colorado sales tax
export const PAYMENT_DEDUP_WINDOW_MS = 5000; // 5 seconds

// ─── Query Limits ────────────────────────────────────────────────────────────
export const TV_DISPLAY_LIMIT = 50;
export const MISSING_PARTS_LIMIT = 100;
export const NEEDS_ATTENTION_LIMIT = 20;
export const SEARCH_RESULTS_LIMIT = 50;
export const LOW_STOCK_REPORT_LIMIT = 50;
export const TOP_MOVING_ITEMS_LIMIT = 10;

// ─── Backup ──────────────────────────────────────────────────────────────────
export const DEFAULT_BACKUP_RETENTION = 30;
export const DEFAULT_BACKUP_SCHEDULE = '0 3 * * *'; // 3 AM daily
