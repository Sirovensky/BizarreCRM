import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Moon, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

/**
 * Off-hours auto-reply toggle — audit §51.13.
 *
 * Switchable flag stored in store_config under:
 *   - inbox_off_hours_autoreply_enabled ('0' | '1')
 *   - inbox_off_hours_autoreply_message (string body)
 *
 * The actual business-hours logic lives in the existing automations engine
 * — this component just flips the flag. When enabled, the automations
 * engine will use the stored message as the first auto-reply sent during
 * non-business hours.
 */

interface OffHoursAutoReplyToggleProps {
  className?: string;
}

interface ConfigResponse {
  inbox_off_hours_autoreply_enabled?: string;
  inbox_off_hours_autoreply_message?: string;
}

async function fetchConfig(): Promise<ConfigResponse> {
  // Scoped inbox-config endpoint — returns just the inbox_* keys.
  const res = await api.get<{ success: boolean; data: Record<string, string> }>(
    '/inbox/config',
  );
  const data = res.data.data || {};
  return {
    inbox_off_hours_autoreply_enabled: data.inbox_off_hours_autoreply_enabled,
    inbox_off_hours_autoreply_message: data.inbox_off_hours_autoreply_message,
  };
}

async function updateConfig(patch: ConfigResponse): Promise<void> {
  // PATCH /inbox/config — admin-only, whitelisted to inbox_* keys.
  await api.patch('/inbox/config', patch);
}

export function OffHoursAutoReplyToggle({ className }: OffHoursAutoReplyToggleProps) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');

  const { data: config, isLoading } = useQuery({
    queryKey: ['store-config-inbox'],
    queryFn: fetchConfig,
  });

  useEffect(() => {
    if (config?.inbox_off_hours_autoreply_message && !editing) {
      setDraft(config.inbox_off_hours_autoreply_message);
    }
  }, [config, editing]);

  const enabled = config?.inbox_off_hours_autoreply_enabled === '1';

  const saveMut = useMutation({
    mutationFn: updateConfig,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['store-config-inbox'] });
      toast.success('Saved');
    },
    onError: () => toast.error('Failed to save'),
  });

  function toggle() {
    saveMut.mutate({
      inbox_off_hours_autoreply_enabled: enabled ? '0' : '1',
    });
  }

  function saveMessage() {
    saveMut.mutate({ inbox_off_hours_autoreply_message: draft });
    setEditing(false);
  }

  return (
    <div
      className={cn(
        'rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-800',
        className,
      )}
    >
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1.5 text-xs font-semibold text-surface-700 dark:text-surface-300">
          <Moon className="h-3.5 w-3.5 text-indigo-500" />
          Off-hours auto-reply
        </div>
        <button
          onClick={toggle}
          disabled={isLoading || saveMut.isPending}
          role="switch"
          aria-checked={enabled}
          className={cn(
            'relative inline-flex h-5 w-9 items-center rounded-full transition-colors',
            enabled ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600',
          )}
        >
          <span
            className={cn(
              'inline-block h-4 w-4 transform rounded-full bg-white transition-transform',
              enabled ? 'translate-x-4' : 'translate-x-0.5',
            )}
          />
        </button>
      </div>
      <div className="mt-2 text-[11px] text-surface-500">
        {isLoading ? (
          <Loader2 className="h-3 w-3 animate-spin" />
        ) : editing ? (
          <div className="space-y-1">
            <textarea
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              rows={2}
              className="w-full rounded-md border border-surface-300 bg-white p-1.5 text-[11px] dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
            <div className="flex justify-end gap-1">
              <button
                onClick={() => {
                  setEditing(false);
                  setDraft(config?.inbox_off_hours_autoreply_message ?? '');
                }}
                className="rounded px-2 py-0.5 text-[10px] text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-700"
              >
                Cancel
              </button>
              <button
                onClick={saveMessage}
                disabled={saveMut.isPending}
                className="rounded bg-primary-600 px-2 py-0.5 text-[10px] text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                Save
              </button>
            </div>
          </div>
        ) : (
          <button
            onClick={() => setEditing(true)}
            className="block w-full text-left italic hover:text-primary-600"
          >
            {draft || 'Click to set auto-reply message'}
          </button>
        )}
      </div>
    </div>
  );
}
