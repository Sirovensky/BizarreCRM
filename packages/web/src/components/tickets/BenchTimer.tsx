/**
 * BenchTimer — live work-in-progress timer for the ticket detail sidebar.
 *
 * Audit 44.6: "start work -> live counter in sidebar, pause for breaks,
 *              stop logs duration + labor cost at the tech's rate."
 *
 * SWITCHABILITY:
 *   The whole component auto-hides when bench_timer_enabled = false in the
 *   store config. Shops that don't want to track labor time get nothing on
 *   screen — zero friction, zero cognitive overhead.
 *
 * Ownership model:
 *   A user can have ONE active timer at a time. Starting a timer on a new
 *   ticket while another is running auto-stops the old one (server side),
 *   so the UI never needs to show a confusing "you have another timer
 *   elsewhere" modal.
 */

import { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Play, Pause, Square, Timer, DollarSign } from 'lucide-react';
import toast from 'react-hot-toast';
import { benchApi } from '@/api/endpoints';
import { formatCents } from '@/utils/format';
import { useAuthStore } from '@/stores/authStore';

interface EmployeeMin {
  id: number;
  first_name?: string;
  last_name?: string;
  full_name?: string;
}

interface BenchTimerProps {
  ticketId: number;
  ticketDeviceId?: number;
  /** Employee list from the parent page — used to resolve tech names for other-user timers. */
  employees?: EmployeeMin[];
}

// WEB-FD-012 (Fixer-426B 2026-04-26): typed response shape for benchApi.timer.stop.
// A server rename of `total_seconds` or `labor_cost_cents` now fails at build
// instead of silently producing zero/NaN in the sidebar.
interface BenchStopResponse {
  total_seconds?: number;
  labor_cost_cents?: number;
}

interface TimerData {
  id: number;
  ticket_id: number;
  elapsed_seconds: number;
  paused: boolean;
  labor_rate_cents: number | null;
}

function formatHMS(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
}

// Defers to formatCents() so stores on non-USD currencies (from settings)
// get the correct glyph and thousands grouping. The stored labor rate is
// still always integer cents — only the display string changes.
function centsToDisplay(cents: number): string {
  return formatCents(cents);
}

export function BenchTimer({ ticketId, ticketDeviceId, employees = [] }: BenchTimerProps) {
  const qc = useQueryClient();
  const currentUserId = useAuthStore((s) => s.user?.id ?? null);

  // Is the feature even on for this store?
  const { data: cfgData, isLoading: cfgLoading } = useQuery({
    queryKey: ['bench-config'],
    queryFn: () => benchApi.config(),
    staleTime: 60_000,
  });
  const enabled = !!cfgData?.data?.data?.bench_timer_enabled;
  const laborRateCents = Number(cfgData?.data?.data?.bench_labor_rate_cents) || 0;

  const { data: currentData, refetch } = useQuery({
    queryKey: ['bench-timer-current'],
    queryFn: () => benchApi.timer.current(),
    enabled,
    // WEB-FAD-010 (Fixer-C3 2026-04-25): drop the per-component override of
    // the global refetchOnWindowFocus:false. Bench timer state is derived
    // from started_at + clientside seconds tick; the WS `ticket:` event
    // already invalidates ['tickets'] when another user pauses/closes.
  });
  const currentTimer: TimerData | null = currentData?.data?.data ?? null;

  // Only show a live, ticking clock if the current active timer belongs to
  // THIS ticket. Otherwise the user might see another ticket's timer here.
  const isOurs = !!currentTimer && currentTimer.ticket_id === ticketId;

  // WEB-UIUX-651: fetch all timers for this ticket so we can detect when
  // another technician has an active (non-ended) timer running. The server
  // returns all rows for admins/managers; for plain techs it only returns
  // their own — so the "other tech running" path activates for privileged
  // viewers who are not the timer owner.
  interface ByTicketTimer {
    id: number;
    user_id: number;
    ended_at: string | null;
    elapsed_seconds: number;
    paused: boolean;
  }
  const { data: byTicketData } = useQuery({
    queryKey: ['bench-timer-by-ticket', ticketId],
    queryFn: () => benchApi.timer.byTicket(ticketId),
    enabled,
    staleTime: 10_000,
    refetchInterval: 15_000,
  });
  const ticketTimers: ByTicketTimer[] = byTicketData?.data?.data?.timers ?? [];

  // Find the first active (running) timer on this ticket owned by someone else.
  const otherActiveTimer = isOurs
    ? null
    : ticketTimers.find(
        (t) => t.ended_at === null && !t.paused && t.user_id !== currentUserId,
      ) ?? null;

  // Resolve the owning tech's display name from the employees list.
  const otherTechName = useMemo(() => {
    if (!otherActiveTimer) return null;
    const emp = employees.find((e) => e.id === otherActiveTimer.user_id);
    if (!emp) return 'Another tech';
    if (emp.full_name) return emp.full_name;
    const parts = [emp.first_name, emp.last_name].filter(Boolean);
    return parts.length > 0 ? parts.join(' ') : 'Another tech';
  }, [otherActiveTimer, employees]);

  // Ticking state — this is what drives the displayed seconds.
  const [localElapsed, setLocalElapsed] = useState(0);
  // While a wake-refetch is in flight, freeze the display at the last known
  // value to avoid a "snap high then snap to server" jitter (WEB-UIUX-790).
  const [wakeRefetching, setWakeRefetching] = useState(false);
  // Ticking state for an other-tech's running timer (read-only display).
  const [otherElapsed, setOtherElapsed] = useState(0);

  useEffect(() => {
    if (!isOurs || !currentTimer) {
      setLocalElapsed(0);
      setWakeRefetching(false);
      return;
    }
    // A fresh server value just landed — clear the refetch freeze and adopt it.
    setWakeRefetching(false);
    setLocalElapsed(currentTimer.elapsed_seconds ?? 0);
    if (currentTimer.paused) return;

    const start = Date.now();
    const anchor = currentTimer.elapsed_seconds ?? 0;
    const interval = window.setInterval(() => {
      setLocalElapsed(anchor + Math.floor((Date.now() - start) / 1000));
    }, 1000);

    // WEB-FO-014 (Fixer-426B 2026-04-26): re-anchor the client-side counter on
    // visibility resume. When the laptop wakes from sleep the `start` anchor is
    // stale — the interval fires immediately but `Date.now() - start` has
    // jumped by the sleep duration, causing a visible snap. By refetching from
    // the server on visibility resume we get the authoritative `elapsed_seconds`
    // and the dep-array change restarts this effect with a fresh anchor.
    //
    // WEB-UIUX-790: additionally freeze the local counter during the inflight
    // refetch so the stale-anchor jump is never visible. The interval is cleared
    // immediately on wake; display stays at the pre-sleep value until the server
    // responds and this effect re-runs with the authoritative elapsed_seconds.
    const handleVisible = () => {
      if (document.visibilityState === 'visible') {
        // Freeze counter — clear interval so the stale anchor can't tick.
        window.clearInterval(interval);
        setWakeRefetching(true);
        refetch();
      }
    };
    document.addEventListener('visibilitychange', handleVisible);

    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisible);
    };
  }, [isOurs, currentTimer?.id, currentTimer?.paused, currentTimer?.elapsed_seconds, refetch]);

  // Tick for the other tech's live timer (read-only). Uses the elapsed_seconds
  // returned by byTicket as the anchor — stale by up to 15 s but close enough
  // for a read-only "X:XX" display.
  useEffect(() => {
    if (!otherActiveTimer) {
      setOtherElapsed(0);
      return;
    }
    setOtherElapsed(otherActiveTimer.elapsed_seconds ?? 0);
    const start = Date.now();
    const anchor = otherActiveTimer.elapsed_seconds ?? 0;
    const interval = window.setInterval(() => {
      setOtherElapsed(anchor + Math.floor((Date.now() - start) / 1000));
    }, 1000);
    return () => window.clearInterval(interval);
  }, [otherActiveTimer?.id, otherActiveTimer?.elapsed_seconds]);

  const laborCost = useMemo(() => {
    const rate = currentTimer?.labor_rate_cents ?? laborRateCents;
    return Math.round((localElapsed / 3600) * rate);
  }, [localElapsed, currentTimer?.labor_rate_cents, laborRateCents]);

  const invalidate = () => {
    qc.invalidateQueries({ queryKey: ['bench-timer-current'] });
    qc.invalidateQueries({ queryKey: ['bench-timer-by-ticket', ticketId] });
  };

  const startMut = useMutation({
    mutationFn: () =>
      benchApi.timer.start({
        ticket_id: ticketId,
        ticket_device_id: ticketDeviceId,
      }),
    onSuccess: () => {
      toast.success('Timer started');
      invalidate();
      refetch();
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to start timer';
      toast.error(msg);
    },
  });

  const pauseMut = useMutation({
    mutationFn: () => benchApi.timer.pause(currentTimer!.id),
    onSuccess: () => {
      toast.success('Timer paused');
      invalidate();
    },
    onError: () => toast.error('Failed to pause timer'),
  });

  const resumeMut = useMutation({
    mutationFn: () => benchApi.timer.resume(currentTimer!.id),
    onSuccess: () => {
      toast.success('Timer resumed');
      invalidate();
    },
    onError: () => toast.error('Failed to resume timer'),
  });

  const stopMut = useMutation({
    mutationFn: () => benchApi.timer.stop(currentTimer!.id),
    onSuccess: (res: { data?: { data?: BenchStopResponse } }) => {
      const secs = res?.data?.data?.total_seconds ?? localElapsed;
      const cost = res?.data?.data?.labor_cost_cents ?? laborCost;
      toast.success(`Timer stopped. ${formatHMS(secs)} (${centsToDisplay(cost)})`);
      invalidate();
    },
    onError: () => toast.error('Failed to stop timer'),
  });

  if (cfgLoading) return null;
  if (!enabled) return null;

  const running = isOurs && currentTimer && !currentTimer.paused;
  const paused = isOurs && currentTimer && currentTimer.paused;
  // "idle" from the current user's perspective — no timer of their own on this ticket.
  const idle = !isOurs;
  // WEB-UIUX-651: another tech is actively running a timer on this ticket.
  const otherRunning = idle && !!otherActiveTimer && !!otherTechName;

  return (
    <div className="card p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-surface-900 dark:text-surface-100">
          <Timer className="h-4 w-4 text-primary-500" />
          Bench Timer
        </div>
        {/* Show Running badge for own timer OR another tech's timer */}
        {(!idle || otherRunning) && (
          <span
            className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${
              running || otherRunning
                ? 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300'
                : 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300'
            }`}
          >
            {running || otherRunning ? 'Running' : 'Paused'}
          </span>
        )}
      </div>

      {/* WEB-UIUX-651: read-only view for another tech's live timer */}
      {otherRunning ? (
        <>
          <div className="mb-3 text-center">
            <div className="font-mono text-3xl tabular-nums text-surface-900 dark:text-surface-100">
              {formatHMS(otherElapsed)}
            </div>
            <div className="mt-1 text-xs text-surface-500">
              {otherTechName} running
            </div>
          </div>
          {/* Start/Pause buttons hidden — another tech owns this timer */}
          <div className="rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-center text-xs text-surface-500 dark:border-surface-700 dark:bg-surface-800/50">
            Timer controlled by {otherTechName}
          </div>
        </>
      ) : (
        <>
          <div className="mb-3 text-center">
            {/* WEB-UIUX-790: dim digits during wake-refetch so frozen counter is visually explained */}
            <div className={`font-mono text-3xl tabular-nums text-surface-900 dark:text-surface-100 transition-opacity duration-150 ${wakeRefetching ? 'opacity-40' : 'opacity-100'}`}>
              {idle ? '00:00:00' : formatHMS(localElapsed)}
            </div>
            <div className="mt-1 flex items-center justify-center gap-1 text-xs text-surface-500">
              <DollarSign className="h-3 w-3" />
              Labor: {centsToDisplay(laborCost)}
            </div>
          </div>

          {idle && (
            <button
              onClick={() => startMut.mutate()}
              disabled={startMut.isPending}
              className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary-600 px-3 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              <Play className="h-4 w-4" />
              Start work
            </button>
          )}

          {running && (
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => pauseMut.mutate()}
                disabled={pauseMut.isPending}
                className="flex items-center justify-center gap-1 rounded-lg border border-surface-300 px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
              >
                <Pause className="h-4 w-4" /> Pause
              </button>
              <button
                onClick={() => stopMut.mutate()}
                disabled={stopMut.isPending}
                className="flex items-center justify-center gap-1 rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                <Square className="h-4 w-4" /> Stop
              </button>
            </div>
          )}

          {paused && (
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => resumeMut.mutate()}
                disabled={resumeMut.isPending}
                className="flex items-center justify-center gap-1 rounded-lg bg-primary-600 px-3 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                <Play className="h-4 w-4" /> Resume
              </button>
              <button
                onClick={() => stopMut.mutate()}
                disabled={stopMut.isPending}
                className="flex items-center justify-center gap-1 rounded-lg bg-red-600 px-3 py-2 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                <Square className="h-4 w-4" /> Stop
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
