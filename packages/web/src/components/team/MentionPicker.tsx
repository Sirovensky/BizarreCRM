/**
 * @mention picker — criticalaudit.md §53 idea #5.
 *
 * Tiny dropdown that lists active employees. Used by TeamChatPage and (later)
 * the ticket note editor. Closes on Esc or click-outside.
 */
import { useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/api/client';

interface Employee {
  id: number;
  username: string;
  first_name: string;
  last_name: string;
}

interface MentionPickerProps {
  onPick: (username: string) => void;
  onClose: () => void;
}

export function MentionPicker({ onPick, onClose }: MentionPickerProps) {
  const ref = useRef<HTMLDivElement>(null);

  const { data } = useQuery({
    queryKey: ['employees', 'simple-mention'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Employee[] }>('/employees');
      return res.data.data;
    },
    staleTime: 60_000,
  });
  const employees: Employee[] = data || [];

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
      <div className="px-3 py-1.5 border-b text-xs font-semibold text-gray-500 uppercase">
        Mention
      </div>
      {employees.length === 0 && (
        <p className="px-3 py-3 text-xs text-gray-500">No employees found.</p>
      )}
      {employees.map((e) => (
        <button
          key={e.id}
          className="w-full text-left px-3 py-2 text-sm hover:bg-blue-50 flex items-center justify-between"
          onClick={() => onPick(e.username)}
        >
          <span>
            <span className="font-semibold">{e.first_name} {e.last_name}</span>
            <span className="text-gray-500 text-xs ml-1">@{e.username}</span>
          </span>
        </button>
      ))}
    </div>
  );
}
