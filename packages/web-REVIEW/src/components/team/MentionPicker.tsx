/**
 * @mention picker — criticalaudit.md §53 idea #5.
 *
 * Tiny dropdown that lists active employees. Used by TeamChatPage and (later)
 * the ticket note editor. Closes on Esc or click-outside.
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/api/client';

interface Employee {
  id: number;
  username: string;
  first_name: string;
  last_name: string;
  // WEB-FD-022 (Fixer-C5 2026-04-25): server may project an `active` /
  // `is_active` flag depending on shop (employees route varies). Marked
  // optional so we can drop terminated rows when present without forcing a
  // server contract change. If neither field is set the row passes — same
  // behaviour as before for shops that don't track activity.
  active?: boolean;
  is_active?: boolean;
}

interface MentionPickerProps {
  onPick: (username: string) => void;
  onClose: () => void;
}

export function MentionPicker({ onPick, onClose }: MentionPickerProps) {
  const ref = useRef<HTMLDivElement>(null);
  // WEB-FD-022 (Fixer-C5 2026-04-25): typed-name filter so a 50-employee
  // shop can narrow the dropdown to a typed prefix instead of scrolling
  // a 50-button list.
  const [filter, setFilter] = useState('');

  const { data } = useQuery({
    queryKey: ['employees', 'simple-mention'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Employee[] }>('/employees');
      return res.data.data;
    },
    staleTime: 60_000,
  });
  const allEmployees: Employee[] = data || [];
  // WEB-FD-022: drop terminated/inactive rows when the server projects an
  // active flag. Falls back to "include" for older payloads that don't.
  const employees = useMemo(() => {
    const q = filter.trim().toLowerCase();
    return allEmployees
      .filter((e) => {
        if (e.active === false) return false;
        if (e.is_active === false) return false;
        return true;
      })
      .filter((e) => {
        if (!q) return true;
        const hay = `${e.first_name} ${e.last_name} ${e.username}`.toLowerCase();
        return hay.includes(q);
      });
  }, [allEmployees, filter]);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    }
    document.addEventListener('keydown', onKey);
    document.addEventListener('mousedown', onClick);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('mousedown', onClick);
    };
  }, [onClose]);

  return (
    <div
      ref={ref}
      className="absolute bottom-full left-0 mb-2 w-64 max-h-60 overflow-y-auto bg-white border rounded-lg shadow-xl z-10"
    >
      <div className="px-3 py-1.5 border-b text-xs font-semibold text-surface-500 dark:text-surface-400 uppercase">
        Mention
      </div>
      {/* WEB-FD-022 (Fixer-C5 2026-04-25): typed-name filter input. Autofocus
       * so the user can keep typing without re-clicking after the picker
       * opens. */}
      <div className="px-2 py-1.5 border-b">
        <input
          autoFocus
          type="text"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Search…"
          className="w-full text-xs px-2 py-1 border rounded focus:outline-none focus:ring-1 focus:ring-primary-500"
          aria-label="Filter employees"
        />
      </div>
      {employees.length === 0 && (
        <p className="px-3 py-3 text-xs text-surface-500 dark:text-surface-400">No employees found.</p>
      )}
      {employees.map((e) => (
        <button
          key={e.id}
          className="w-full text-left px-3 py-2 text-sm hover:bg-primary-50 flex items-center justify-between"
          onClick={() => onPick(e.username)}
        >
          <span>
            <span className="font-semibold">{e.first_name} {e.last_name}</span>
            <span className="text-surface-500 dark:text-surface-400 text-xs ml-1">@{e.username}</span>
          </span>
        </button>
      ))}
    </div>
  );
}
