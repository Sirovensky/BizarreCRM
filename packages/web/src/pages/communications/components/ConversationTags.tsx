import { useState, type KeyboardEvent } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Tag, X, Plus } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

/**
 * Conversation tags — audit §51.6.
 *
 * Manual tagging only (v1). The inbox supports filtering by tag via the
 * `/inbox/conversations?tags=...` query param. Common presets suggested:
 * "waiting for parts", "repair complete", "follow-up".
 */

interface ConversationTagsProps {
  phone: string;
  className?: string;
}

interface AssignmentRow {
  phone: string;
  tags: string[];
}

const TAG_SUGGESTIONS = [
  'waiting-for-parts',
  'repair-complete',
  'follow-up',
  'priority',
  'escalate',
] as const;

async function fetchTags(phone: string): Promise<string[]> {
  const res = await api.get<{ success: boolean; data: AssignmentRow[] }>(
    '/inbox/conversations',
  );
  const row = (res.data.data || []).find((r) => r.phone === phone);
  return row?.tags ?? [];
}

export function ConversationTags({ phone, className }: ConversationTagsProps) {
  const qc = useQueryClient();
  const [input, setInput] = useState('');
  const [adding, setAdding] = useState(false);

  const { data: tags = [] } = useQuery({
    queryKey: ['inbox-tags', phone],
    queryFn: () => fetchTags(phone),
    enabled: !!phone,
  });

  const addMut = useMutation({
    mutationFn: (tag: string) =>
      api.post(`/inbox/conversation/${encodeURIComponent(phone)}/tag`, { tag }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inbox-tags', phone] });
      setInput('');
      setAdding(false);
    },
    onError: () => toast.error('Failed to add tag'),
  });

  const removeMut = useMutation({
    mutationFn: (tag: string) =>
      api.delete(
        `/inbox/conversation/${encodeURIComponent(phone)}/tag/${encodeURIComponent(tag)}`,
      ),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inbox-tags', phone] });
    },
    onError: () => toast.error('Failed to remove tag'),
  });

  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && input.trim()) {
      addMut.mutate(input.trim().toLowerCase());
    } else if (e.key === 'Escape') {
      setAdding(false);
      setInput('');
    }
  };

  return (
    <div className={cn('flex flex-wrap items-center gap-1', className)}>
      {tags.map((tag) => (
        <span
          key={tag}
          className="inline-flex items-center gap-1 rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-medium text-surface-700 dark:bg-surface-700 dark:text-surface-300"
        >
          <Tag className="h-2.5 w-2.5" />
          {tag}
          <button
            onClick={() => removeMut.mutate(tag)}
            aria-label={`Remove tag ${tag}`}
            className="ml-0.5 rounded-full hover:bg-surface-200 dark:hover:bg-surface-600"
          >
            <X className="h-2.5 w-2.5" />
          </button>
        </span>
      ))}
      {adding ? (
        <input
          autoFocus
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onBlur={() => {
            if (!input.trim()) setAdding(false);
          }}
          onKeyDown={onKeyDown}
          placeholder="tag…"
          className="h-5 w-24 rounded-full border border-surface-300 bg-white px-2 text-[10px] text-surface-900 focus:border-primary-400 focus:outline-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
        />
      ) : (
        <button
          onClick={() => setAdding(true)}
          className="inline-flex items-center gap-0.5 rounded-full border border-dashed border-surface-300 px-2 py-0.5 text-[10px] text-surface-500 hover:border-primary-400 hover:text-primary-600 dark:border-surface-600"
        >
          <Plus className="h-2.5 w-2.5" />
          Tag
        </button>
      )}
      {adding && tags.length === 0 && (
        <div className="flex w-full flex-wrap gap-1 pt-1 text-[9px] text-surface-400">
          {TAG_SUGGESTIONS.map((s) => (
            <button
              key={s}
              onClick={() => addMut.mutate(s)}
              className="rounded-full bg-surface-50 px-1.5 py-0.5 hover:bg-surface-100 dark:bg-surface-800 dark:hover:bg-surface-700"
            >
              {s}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
