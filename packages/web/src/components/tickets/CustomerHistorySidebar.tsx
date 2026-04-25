/**
 * CustomerHistorySidebar — audit 44.8.
 *
 * "Sidebar shows past 5 repairs with photos, dates, costs. Highlights
 *  repeat faults."
 *
 * We fetch the customer's last N tickets via the existing /customers/:id
 * endpoint (which already returns the ticket list) and filter client-side.
 * Repeat-fault highlighting: we group previous device names and bold the
 * ones that match the CURRENT ticket's device.
 */

import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Clock, Repeat2, Loader2 } from 'lucide-react';
import { customerApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

interface CustomerHistorySidebarProps {
  customerId: number;
  currentTicketId: number;
  currentDeviceName?: string;
}

interface HistoryTicket {
  id: number;
  order_id: number | string;
  created_at: string;
  total?: number;
  devices?: Array<{ device_name?: string; name?: string; photos?: Array<{ url?: string; path?: string }> }>;
  first_device?: { device_name?: string; name?: string };
}

function formatTicketLabel(orderId: string | number) {
  const s = String(orderId);
  return s.startsWith('T-') ? s : `T-${s.padStart(4, '0')}`;
}

// Allow-list raw photo URLs before letting them flow into <img src>. A
// poisoned tenant row or malicious CSV import could otherwise land
// `data:image/svg+xml,<svg onload=...>` (the live XSS vector — `javascript:`
// is blocked by browsers in img, but `data:` SVG is not) directly into the
// sidebar render. Mirror the http/https-only stance from `getIFixitUrl`.
//
// Server-relative paths (`/uploads/...`) are accepted because they resolve
// to the same origin which the auth/CSP boundary already trusts; protocol-
// relative `//evil/...` is rejected explicitly.
function isSafePhotoUrl(raw: unknown): raw is string {
  if (typeof raw !== 'string' || raw.length === 0) return false;
  // Reject protocol-relative form before URL parsing (it parses successfully).
  if (raw.startsWith('//')) return false;
  // Same-origin server path — safe.
  if (raw.startsWith('/')) return true;
  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:';
  } catch {
    return false;
  }
}

function photoUrl(
  device?: HistoryTicket['devices'] extends Array<infer E> ? E : never,
): string | null {
  const photos = (device as any)?.photos;
  if (!Array.isArray(photos) || photos.length === 0) return null;
  const candidate = photos[0]?.url || photos[0]?.path || null;
  return isSafePhotoUrl(candidate) ? candidate : null;
}

export function CustomerHistorySidebar({
  customerId,
  currentTicketId,
  currentDeviceName,
}: CustomerHistorySidebarProps) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-history', customerId],
    queryFn: () => customerApi.getTickets(customerId),
    enabled: !!customerId,
    staleTime: 30_000,
  });

  // customerApi.getTickets() returns the axios response. Its body is
  // { success, data: { tickets, pagination } }. So the payload lives at
  // data.data.data.tickets — the previous code mistakenly called
  // customerApi.get() which never returns a tickets array and left the
  // sidebar permanently empty.
  const ticketsRaw: HistoryTicket[] = data?.data?.data?.tickets ?? [];

  const tickets = ticketsRaw
    .filter((t) => t.id !== currentTicketId)
    .slice(0, 5);

  const hasRepeatFault =
    !!currentDeviceName &&
    tickets.some((t) => {
      const name =
        t.first_device?.device_name ||
        (t.devices && t.devices[0] && (t.devices[0].device_name || t.devices[0].name)) ||
        '';
      return name && name.toLowerCase() === currentDeviceName.toLowerCase();
    });

  return (
    <div className="card p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-surface-900 dark:text-surface-100">
          <Clock className="h-4 w-4 text-primary-500" />
          Customer history
        </div>
        {hasRepeatFault && (
          <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-700 dark:bg-amber-900/40 dark:text-amber-300">
            <Repeat2 className="h-3 w-3" /> Repeat fault
          </span>
        )}
      </div>

      {isLoading ? (
        <div className="flex justify-center py-4">
          <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
        </div>
      ) : tickets.length === 0 ? (
        <p className="py-2 text-xs text-surface-400">No previous repairs.</p>
      ) : (
        <ul className="space-y-2">
          {tickets.map((t) => {
            const device =
              (t.devices && t.devices[0]) ||
              (t.first_device as any) ||
              {};
            const name = (device as any).device_name || (device as any).name || 'Unknown device';
            const isRepeat =
              !!currentDeviceName && name.toLowerCase() === currentDeviceName.toLowerCase();
            const img = photoUrl(device as any);
            return (
              <li
                key={t.id}
                className={`rounded-lg border p-2 text-xs ${
                  isRepeat
                    ? 'border-amber-300 bg-amber-50 dark:border-amber-700 dark:bg-amber-900/20'
                    : 'border-surface-200 dark:border-surface-700'
                }`}
              >
                <div className="flex items-start gap-2">
                  {img ? (
                    <img src={img} alt={name} className="h-10 w-10 shrink-0 rounded object-cover" />
                  ) : (
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded bg-surface-100 text-surface-400 dark:bg-surface-800">
                      ?
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center justify-between gap-2">
                      <Link
                        to={`/tickets/${t.id}`}
                        className="truncate font-semibold text-primary-600 hover:underline dark:text-primary-400"
                      >
                        {formatTicketLabel(t.order_id || t.id)}
                      </Link>
                      {typeof t.total === 'number' && (
                        <span className="text-surface-500">{formatCurrency(t.total)}</span>
                      )}
                    </div>
                    <div
                      className={`truncate ${
                        isRepeat
                          ? 'font-medium text-amber-800 dark:text-amber-200'
                          : 'text-surface-600 dark:text-surface-400'
                      }`}
                    >
                      {name}
                    </div>
                    <div className="text-[10px] text-surface-400">
                      {new Date(t.created_at).toLocaleDateString()}
                    </div>
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
