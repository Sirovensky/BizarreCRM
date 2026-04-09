/**
 * Formatting utilities for the dashboard.
 */

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
 */
export function formatNumber(n: number): string {
  return n.toLocaleString();
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
 */
export function formatDateTime(iso: string): string {
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

/**
 * Format an ISO date string to relative time (e.g. "2m ago", "3h ago").
 */
export function formatRelativeTime(iso: string): string {
  const now = Date.now();
  const then = new Date(iso).getTime();
  const diff = Math.floor((now - then) / 1000);

  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}
