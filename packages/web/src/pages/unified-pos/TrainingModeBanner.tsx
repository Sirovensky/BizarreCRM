import { useState, useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { GraduationCap, Play, StopCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

/**
 * Training / sandbox mode banner (audit §43.15).
 *
 * Persists a per-user "active training session" flag in localStorage so the
 * banner stays visible across refreshes. When active, the checkout and
 * create-ticket paths should hit /pos-enrich/training/submit instead of the
 * real POS endpoints — we expose `useIsTraining()` as a helper that other
 * POS components can consult before wiring real mutations.
 *
 * Matches audit idea 15: "new hires can ring fake sales that don't touch
 * inventory or payments."
 */

const TRAINING_SESSION_KEY = 'pos.trainingSessionId';

interface TrainingSession {
  id: number;
  user_id: number;
  started_at: string;
  ended_at: string | null;
}

interface TrainingResponse {
  data: TrainingSession;
}

export function useIsTraining(): boolean {
  const [value, setValue] = useState(() => !!localStorage.getItem(TRAINING_SESSION_KEY));
  useEffect(() => {
    const handler = () => setValue(!!localStorage.getItem(TRAINING_SESSION_KEY));
    window.addEventListener('storage', handler);
    window.addEventListener('pos:training-changed', handler);
    return () => {
      window.removeEventListener('storage', handler);
      window.removeEventListener('pos:training-changed', handler);
    };
  }, []);
  return value;
}

function notifyTrainingChanged(): void {
  try {
    window.dispatchEvent(new CustomEvent('pos:training-changed'));
  } catch {
    /* no-op in non-browser envs */
  }
}

export function TrainingModeBanner() {
  const qc = useQueryClient();
  const [sessionId, setSessionId] = useState<number | null>(() => {
    const raw = localStorage.getItem(TRAINING_SESSION_KEY);
    return raw ? Number(raw) : null;
  });
  const [busy, setBusy] = useState(false);

  const startTraining = async () => {
    setBusy(true);
    try {
      const res = await api.post<TrainingResponse>('/pos-enrich/training/start');
      const id = res.data.data.id;
      setSessionId(id);
      localStorage.setItem(TRAINING_SESSION_KEY, String(id));
      notifyTrainingChanged();
      toast.success('Training mode ON — sales will not affect inventory');
      qc.invalidateQueries({ queryKey: ['pos-enrich'] });
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to start training');
    } finally {
      setBusy(false);
    }
  };

  const endTraining = async () => {
    if (!sessionId) return;
    setBusy(true);
    try {
      await api.post(`/pos-enrich/training/${sessionId}/end`);
      setSessionId(null);
      localStorage.removeItem(TRAINING_SESSION_KEY);
      notifyTrainingChanged();
      toast.success('Training mode OFF');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to end training');
    } finally {
      setBusy(false);
    }
  };

  if (!sessionId) {
    return (
      <button
        onClick={startTraining}
        disabled={busy}
        className="flex items-center gap-1.5 rounded-lg border border-surface-300 px-3 py-2 text-sm font-medium text-surface-600 hover:bg-surface-50 disabled:opacity-50 dark:border-surface-600 dark:text-surface-400 dark:hover:bg-surface-800"
        title="New-hire sandbox: fake sales, no inventory impact"
      >
        <GraduationCap className="h-4 w-4" />
        Training
      </button>
    );
  }

  return (
    <div className="flex flex-1 items-center justify-between gap-3 rounded-lg border-2 border-dashed border-purple-400 bg-purple-50 px-4 py-2 dark:border-purple-400/40 dark:bg-purple-500/10">
      <div className="flex items-center gap-2 text-sm font-semibold text-purple-700 dark:text-purple-300">
        <GraduationCap className="h-4 w-4" />
        Training Mode — sales are not recorded
      </div>
      <button
        onClick={endTraining}
        disabled={busy}
        className="flex items-center gap-1.5 rounded-md bg-purple-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-purple-700 disabled:opacity-50"
      >
        <StopCircle className="h-3.5 w-3.5" />
        End Training
      </button>
    </div>
  );
}
