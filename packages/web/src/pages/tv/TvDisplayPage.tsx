import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Wrench, Monitor } from 'lucide-react';
import { ticketApi, settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { safeColor } from '@/utils/safeColor';

// ─── Types ──────────────────────────────────────────────────────────
interface TvTicket {
  id: number;
  order_id: string | number;
  customer_first_name: string;
  device_names: string[];
  status: { name: string; color: string };
  assigned_tech: string | null;
}

// ─── Live Clock ─────────────────────────────────────────────────────
function useLiveClock() {
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(timer);
  }, []);

  return now;
}

function LiveClock({ now }: { now: Date }) {
  return (
    <span className="tabular-nums">
      {now.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        second: '2-digit',
      })}
    </span>
  );
}

// ─── Status Badge (large, for TV readability) ───────────────────────
function TvStatusBadge({ status }: { status: { name: string; color: string } }) {
  return (
    <span
      className="inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-sm font-bold"
      style={{ backgroundColor: `${safeColor(status.color)}25`, color: safeColor(status.color) }}
    >
      <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: safeColor(status.color) }} />
      {status.name}
    </span>
  );
}

// ─── Main Component ─────────────────────────────────────────────────
export function TvDisplayPage() {
  const now = useLiveClock();
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['tv-display'],
    queryFn: () => ticketApi.tvDisplay(),
    refetchInterval: 30000,
  });
  const { data: storeData } = useQuery({
    queryKey: ['store-info-tv'],
    queryFn: async () => { const r = await settingsApi.getStore(); return r.data.data as any; },
    staleTime: 300000,
  });
  const storeName = storeData?.name || 'Repair Shop';

  const tickets: TvTicket[] = (data?.data as any)?.data ?? [];

  return (
    <div className="fixed inset-0 overflow-hidden bg-gradient-to-br from-surface-950 via-surface-900 to-surface-950 text-white">
      {/* Header bar */}
      <div className="flex items-center justify-between border-b border-surface-700/50 bg-surface-900/80 px-8 py-4 backdrop-blur-sm">
        <div className="flex items-center gap-4">
          <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary-600">
            <Wrench className="h-5 w-5 text-white" />
          </div>
          <div>
            <h1 className="text-2xl font-bold tracking-tight">{storeName}</h1>
            <p className="text-sm text-surface-400">Repair Status Board</p>
          </div>
        </div>
        <div className="text-right">
          <div className="text-3xl font-bold text-surface-100">
            <LiveClock now={now} />
          </div>
          <div className="text-sm text-surface-400">
            {now.toLocaleDateString('en-US', {
              weekday: 'long',
              month: 'long',
              day: 'numeric',
            })}
          </div>
        </div>
      </div>

      {/* Ticket grid */}
      <div className="flex-1 overflow-y-auto p-6">
        {isError ? (
          <div className="flex flex-col items-center justify-center" style={{ height: 'calc(100vh - 10rem - var(--dev-banner-h, 0px))' }}>
            <Monitor className="mb-6 h-24 w-24 text-red-500/70" />
            <h2 className="mb-2 text-3xl font-bold text-red-300">Display Offline</h2>
            <p className="mb-6 text-lg text-surface-400">Could not reach the server. Retrying automatically.</p>
            <button
              type="button"
              onClick={() => refetch()}
              className="rounded-lg bg-primary-600 px-6 py-2.5 text-base font-medium text-white hover:bg-primary-700"
            >
              Retry now
            </button>
          </div>
        ) : isLoading ? (
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-2 xl:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={`tv-skel-${i}`} className="animate-pulse rounded-xl bg-surface-800/50 p-6">
                <div className="mb-3 h-8 w-24 rounded bg-surface-700" />
                <div className="mb-2 h-5 w-32 rounded bg-surface-700" />
                <div className="h-5 w-48 rounded bg-surface-700" />
              </div>
            ))}
          </div>
        ) : tickets.length === 0 ? (
          <div className="flex flex-col items-center justify-center" style={{ height: 'calc(100vh - 10rem - var(--dev-banner-h, 0px))' }}>
            <Monitor className="mb-6 h-24 w-24 text-surface-700" />
            <h2 className="mb-2 text-3xl font-bold text-surface-400">No Active Repairs</h2>
            <p className="text-lg text-surface-500">All caught up! Check back later.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">
            {tickets.map((ticket) => (
              <TicketCard key={ticket.id} ticket={ticket} />
            ))}
          </div>
        )}
      </div>

      {/* Footer with ticket count */}
      <div className="border-t border-surface-700/50 bg-surface-900/80 px-8 py-3 backdrop-blur-sm">
        <div className="flex items-center justify-between text-sm text-surface-400">
          <span>{tickets.length} active repair{tickets.length !== 1 ? 's' : ''}</span>
          <span>Auto-refreshes every 30 seconds</span>
        </div>
      </div>
    </div>
  );
}

// ─── Ticket Card ────────────────────────────────────────────────────
function TicketCard({ ticket }: { ticket: TvTicket }) {
  const orderId = typeof ticket.order_id === 'string'
    ? `T-${ticket.order_id.padStart(4, '0')}`
    : `T-${String(ticket.order_id).padStart(4, '0')}`;

  return (
    <div
      className={cn(
        'rounded-xl border border-surface-700/50 bg-surface-800/60 p-5 backdrop-blur-sm',
        'transition-all duration-500 hover:border-surface-600/50 hover:bg-surface-800/80',
      )}
    >
      {/* Top row: ticket ID + status */}
      <div className="mb-3 flex items-start justify-between gap-3">
        <span className="text-2xl font-bold text-surface-100">{orderId}</span>
        <TvStatusBadge status={ticket.status} />
      </div>

      {/* Customer initial — show only first letter to avoid PII leak on a public lobby screen */}
      <div className="mb-2">
        <span className="text-lg text-surface-300">
          {ticket.customer_first_name
            ? `${ticket.customer_first_name.charAt(0).toUpperCase()}.`
            : 'Walk-in'}
        </span>
      </div>

      {/* Device(s) */}
      <div className="mb-3">
        {ticket.device_names.length > 0 ? (
          ticket.device_names.map((d, i) => (
            <span
              key={i}
              className="mr-2 mt-1 inline-block rounded-lg bg-surface-700/60 px-2.5 py-1 text-sm text-surface-300"
            >
              {d}
            </span>
          ))
        ) : (
          <span className="text-sm text-surface-500">No device specified</span>
        )}
      </div>

      {/* Assigned tech */}
      {ticket.assigned_tech && (
        <div className="border-t border-surface-700/30 pt-2 text-sm text-surface-400">
          Tech: <span className="font-medium text-surface-300">{ticket.assigned_tech}</span>
        </div>
      )}
    </div>
  );
}
