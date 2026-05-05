/**
 * Formatting utilities for the dashboard.
 */
import { formatDistanceToNow } from 'date-fns';

/**
 * Format seconds into a human-readable uptime string.
 * e.g. 90061 -> "1d 1h 1m"
 */
export function formatUptime(seconds: number): string {
  if (seconds < 60) return `${Math.floor(seconds)}s`;

  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);

  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (hours > 0) parts.push(`${hours}h`);
  if (minutes > 0) parts.push(`${minutes}m`);

  return parts.join(' ') || '0m';
}

/**
 * Format bytes into human-readable size.
 * e.g. 1536000 -> "1.46 MB"
 */
export function formatBytes(bytes: number, decimals = 2): string {
  if (bytes === 0) return '0 B';

  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const value = bytes / Math.pow(k, i);

  return `${value.toFixed(decimals)} ${sizes[i]}`;
}

/**
 * Format a number with commas for thousands.
 * e.g. 123456 -> "123,456"
 *
 * Explicit 'en-US' locale prevents non-ASCII separators (e.g. thin-space in
 * fr-FR) that would break CSV re-import or downstream numeric parsing.
 */
export function formatNumber(n: number): string {
  return n.toLocaleString('en-US');
}

/**
 * Format a number to 1 decimal place.
 * e.g. 3.456 -> "3.5"
 */
export function formatDecimal(n: number, places = 1): string {
  return n.toFixed(places);
}

/**
 * Format an ISO date string to a readable local date/time.
 *
 * Explicit 'en-US' locale + dateStyle/timeStyle prevents OS-locale variance
 * (e.g. "24.4.2026, 14:23" on de-DE or "2026/4/24" on ja-JP) so every
 * operator sees the same "Apr 24, 2026, 2:23 PM" format regardless of their
 * system locale settings (DASH-ELEC-052).
 */
export function formatDateTime(iso: string): string {
  try {
    // SQLite stores datetime('now') as UTC without 'Z' suffix.
    // Append 'Z' if missing so Date parses it as UTC, then toLocaleString
    // converts to the user's local timezone.
    const utcIso = iso.includes('Z') || iso.includes('+') ? iso : iso.replace(' ', 'T') + 'Z';
    return new Date(utcIso).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
  } catch {
    return iso;
  }
}

/**
 * Format an ISO date string to relative time (e.g. "2 minutes ago", "3 hours ago").
 * Uses date-fns formatDistanceToNow for locale-aware output (DASH-ELEC-119).
 */
export function formatRelativeTime(iso: string): string {
  try {
    // SQLite stores datetime('now') as UTC without 'Z' suffix.
    const utcIso = iso.includes('Z') || iso.includes('+') ? iso : iso.replace(' ', 'T') + 'Z';
    return formatDistanceToNow(new Date(utcIso), { addSuffix: true });
  } catch {
    return iso;
  }
}
