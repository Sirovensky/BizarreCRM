import { useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { smsApi } from '@/api/endpoints';

/**
 * Canned response hotkeys — audit §51.2.
 *
 * Rules (STRICT — don't paraphrase):
 *   - Ctrl+1 / Ctrl+2 / Ctrl+3 each insert a preset template.
 *   - NEVER autosends.
 *   - NEVER overwrites free-typed text. A "preset" means text that a prior
 *     hotkey inserted via this component. If the current value matches a
 *     previously-inserted preset, replacing it with another preset is OK.
 *     If the user has typed anything that doesn't match the last preset
 *     exactly, the hotkey is a no-op.
 *   - Disabled when the user is not focused inside the compose textarea.
 *
 * The first 3 templates returned by smsApi.templates() (sorted by name) are
 * used. Template list is refetched when shortcuts are shown so edits to
 * the template bank take effect on next render.
 */

interface CannedResponseHotkeysProps {
  /** Current compose value (controlled) */
  value: string;
  onChange: (value: string) => void;
  /** True when compose textarea is focused — otherwise hotkey is ignored */
  composeFocused: boolean;
}

interface SmsTemplate {
  id: number;
  name: string;
  content: string;
}

export function CannedResponseHotkeys({
  value,
  onChange,
  composeFocused,
}: CannedResponseHotkeysProps) {
  // Remember the last preset we inserted — if value still matches it, we
  // can safely replace it with another preset.
  const lastPresetRef = useRef<string>('');

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
  });
  const templates: SmsTemplate[] = (tplData?.data as any)?.data?.templates ?? [];
  const top3 = templates.slice(0, 3);

  useEffect(() => {
    if (!composeFocused) return;

    function handler(e: KeyboardEvent) {
      // Only fire on Ctrl+1..3 (digit keys). No modifier fallthrough to
      // avoid clobbering native shortcuts.
      if (!e.ctrlKey && !e.metaKey) return;
      if (e.altKey || e.shiftKey) return;
      const idx = ['1', '2', '3'].indexOf(e.key);
      if (idx < 0) return;
      if (!top3[idx]) return;

      const isEmpty = value.trim() === '';
      const matchesLast = value === lastPresetRef.current && lastPresetRef.current !== '';
      if (!isEmpty && !matchesLast) return; // respect free-typed text

      e.preventDefault();
      const next = top3[idx].content;
      lastPresetRef.current = next;
      onChange(next);
    }

    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [composeFocused, top3, value, onChange]);

  // Also reset lastPresetRef whenever the user types free text over a preset.
  useEffect(() => {
    if (value !== lastPresetRef.current) {
      // Don't clobber — just forget the preset once edited.
      if (!value.startsWith(lastPresetRef.current.slice(0, 8))) {
        lastPresetRef.current = '';
      }
    }
  }, [value]);

  if (top3.length === 0) return null;

  return (
    <div className="flex items-center gap-1 text-[10px] text-surface-500">
      {top3.map((t, i) => (
        <span
          key={t.id}
          title={t.content}
          className="inline-flex items-center gap-0.5 rounded border border-surface-200 bg-surface-50 px-1 py-0.5 dark:border-surface-700 dark:bg-surface-800"
        >
          <kbd className="font-mono text-[9px] text-surface-400">Ctrl+{i + 1}</kbd>
          <span className="max-w-[8rem] truncate">{t.name}</span>
        </span>
      ))}
    </div>
  );
}
