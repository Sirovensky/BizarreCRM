/**
 * Internal team chat — criticalaudit.md §53 idea #6.
 *
 * Polling-based MVP. Channels list on the left, messages on the right. New
 * message input at the bottom uses the MentionPicker to insert @username.
 *
 * Polling interval: 15 seconds, only while the page is visible. The endpoint
 * supports `?after=<lastId>` so each tick is incremental, not a full reload.
 *
 * @audit-fixed (WEB-FAD-003): the original 5s tick had no visibility gate,
 * so background tabs hammered `/team-chat/channels/:id/messages?limit=200`
 * at 720 reqs/hr. Now: 15s tick + `refetchIntervalInBackground: false` +
 * a visibilitychange listener that triggers an immediate refetch when the
 * tab comes forward (so chat doesn't look frozen on tab switch).
 */
import { useState, useEffect, useRef } from 'react';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { MessageSquare, Send, Plus, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import axios from 'axios';
import { api } from '@/api/client';

// @audit-fixed (WEB-FA-007 / Fixer-B1 2026-04-25): typed error narrowing for
// mutation onError handlers. Previous `e: any` lost contract guards on the
// API response shape; this helper gives us a stable string regardless of
// whether the error is an axios response (`{error}` body), a thrown Error
// (timeout / aborted / network), or something else.
function describeError(e: unknown, fallback: string): string {
  if (axios.isAxiosError(e)) {
    const data = e.response?.data as { error?: unknown; message?: unknown } | undefined;
    if (typeof data?.error === 'string') return data.error;
    if (typeof data?.message === 'string') return data.message;
    if (e.message) return e.message;
  }
  if (e instanceof Error && e.message) return e.message;
  return fallback;
}

function formatMessageTime(isoString: string): string {
  const date = new Date(isoString);
  const now = new Date();
  const timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  const isToday =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (isToday) return timeStr;
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  const isYesterday =
    date.getFullYear() === yesterday.getFullYear() &&
    date.getMonth() === yesterday.getMonth() &&
    date.getDate() === yesterday.getDate();
  if (isYesterday) return `Yesterday ${timeStr}`;
  return `${date.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })} ${timeStr}`;
}
import { MentionPicker } from '@/components/team/MentionPicker';
import { useHasRole } from '@/hooks/useHasRole';

interface Channel {
  id: number;
  name: string;
  kind: 'general' | 'ticket' | 'direct';
  ticket_id: number | null;
  created_at: string;
}

interface Message {
  id: number;
  channel_id: number;
  user_id: number;
  body: string;
  created_at: string;
  first_name: string | null;
  last_name: string | null;
  username: string | null;
}

export function TeamChatPage() {
  const queryClient = useQueryClient();
  // WEB-FAE-001 follow-up: route role gate through shared useHasRole hook.
  const canCreateGeneralChannel = useHasRole('admin');
  const [selectedChannelId, setSelectedChannelId] = useState<number | null>(null);
  const [olderMessages, setOlderMessages] = useState<Message[]>([]);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [hasOlder, setHasOlder] = useState(true);
  const [draft, setDraft] = useState('');
  const [showMentions, setShowMentions] = useState(false);
  const [newChannelName, setNewChannelName] = useState('');
  const [showNew, setShowNew] = useState(false);
  // WEB-UIUX-557: focus-trap + scroll-lock for the New-channel modal.
  const newChannelTrapRef = useFocusTrap(showNew, { initialFocusSelector: 'input' }) as { current: HTMLDivElement | null };
  useBodyScrollLock(showNew);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const isAtBottomRef = useRef(true);

  const { data: channelsData } = useQuery({
    queryKey: ['team-chat', 'channels'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Channel[] }>('/team-chat/channels');
      const list = res.data.data;
      if (list.length && selectedChannelId === null) {
        const general = list.find((c) => c.kind === 'general') || list[0];
        setSelectedChannelId(general.id);
      }
      return list;
    },
  });
  const channels: Channel[] = channelsData || [];

  const { data: messagesData, refetch: refetchMessages } = useQuery({
    queryKey: ['team-chat', 'messages', selectedChannelId],
    enabled: !!selectedChannelId,
    // 15s tick + skip-when-hidden. TanStack respects
    // refetchIntervalInBackground:false by suspending the timer on
    // visibilitychange, but we still gate refetchInterval below as a
    // belt-and-braces guard for browsers that fire the timer anyway.
    refetchInterval: () =>
      typeof document !== 'undefined' && document.visibilityState !== 'visible'
        ? false
        : 15_000,
    refetchIntervalInBackground: false,
    staleTime: 4_000,
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Message[] }>(
        `/team-chat/channels/${selectedChannelId}/messages?limit=50`,
      );
      return res.data.data;
    },
  });
  const recentMessages: Message[] = messagesData || [];
  // Merge: olderMessages (prepended) + recentMessages. De-dupe by id so
  // a page refresh or channel switch doesn't show duplicates.
  const allIds = new Set(recentMessages.map((m) => m.id));
  const dedupedOlder = olderMessages.filter((m) => !allIds.has(m.id));
  const messages: Message[] = [...dedupedOlder, ...recentMessages];

  // Resume immediately when the tab comes back to the foreground so users
  // don't stare at a stale chat for up to 15s after switching tabs.
  useEffect(() => {
    if (!selectedChannelId) return;
    const onVis = () => {
      if (document.visibilityState === 'visible') {
        refetchMessages();
      }
    };
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, [selectedChannelId, refetchMessages]);

  // Track whether the user is near the bottom so auto-scroll doesn't yank
  // them away when they scroll up to read history (WEB-UIUX-535).
  useEffect(() => {
    const el = scrollContainerRef.current;
    if (!el) return;
    const onScroll = () => {
      isAtBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 100;
    };
    el.addEventListener('scroll', onScroll, { passive: true });
    return () => el.removeEventListener('scroll', onScroll);
  }, []);

  useEffect(() => {
    if (isAtBottomRef.current) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages.length]);

  // WEB-FX-003: Esc dismisses the New-channel modal.
  useEffect(() => {
    if (!showNew) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setShowNew(false);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [showNew]);

  const sendMut = useMutation({
    mutationFn: async () => {
      const res = await api.post(`/team-chat/channels/${selectedChannelId}/messages`, {
        body: draft.trim(),
      });
      return res.data.data;
    },
    onSuccess: () => {
      setDraft('');
      queryClient.invalidateQueries({ queryKey: ['team-chat', 'messages', selectedChannelId] });
    },
    onError: (e: unknown) => toast.error(describeError(e, 'Failed to send')),
  });

  const createChannelMut = useMutation({
    mutationFn: async () => {
      if (!canCreateGeneralChannel) throw new Error('Only admins can create general channels');
      const res = await api.post('/team-chat/channels', {
        name: newChannelName,
        kind: 'general',
      });
      return res.data.data;
    },
    onSuccess: (created: Channel) => {
      toast.success('Channel created');
      queryClient.invalidateQueries({ queryKey: ['team-chat', 'channels'] });
      setShowNew(false);
      setNewChannelName('');
      if (created?.id) setSelectedChannelId(created.id);
    },
    onError: (e: unknown) => toast.error(describeError(e, 'Failed to create channel')),
  });

  // WEB-FA-020 (Fixer-C7 2026-04-25): bound the mention regex to 0-32 chars
  // and the same character class (`[a-zA-Z0-9_.\-]`) the server uses in
  // `parseMentionUsernames` (teamChat.routes.ts:86). Without the upper bound,
  // typing `@` then a 100-char run of dots would still open the picker even
  // though the server would discard the token (>32 char cap). The picker
  // popup is also dismissed once the typed run exceeds 32 chars so the user
  // gets a visible signal that the candidate is now invalid.
  const MENTION_TAIL_RE = /@[a-zA-Z0-9_.\-]{0,32}$/;
  function handleDraftChange(value: string) {
    setDraft(value);
    const tail = value.slice(0, inputRef.current?.selectionStart ?? value.length);
    setShowMentions(MENTION_TAIL_RE.test(tail));
  }

  function insertMention(username: string) {
    setDraft((prev) => prev.replace(MENTION_TAIL_RE, `@${username} `));
    setShowMentions(false);
    inputRef.current?.focus();
  }

  async function loadOlder() {
    if (!selectedChannelId || loadingOlder) return;
    const oldestId = messages[0]?.id;
    if (!oldestId) return;
    setLoadingOlder(true);
    try {
      const res = await api.get<{ success: boolean; data: Message[] }>(
        `/team-chat/channels/${selectedChannelId}/messages?before=${oldestId}&limit=50`,
      );
      const older = res.data.data;
      if (older.length === 0) {
        setHasOlder(false);
      } else {
        setOlderMessages((prev) => {
          const existing = new Set(prev.map((m) => m.id));
          return [...older.filter((m) => !existing.has(m.id)), ...prev];
        });
        if (older.length < 50) setHasOlder(false);
      }
    } catch {
      toast.error('Failed to load older messages');
    } finally {
      setLoadingOlder(false);
    }
  }

  return (
    <div className="p-6 max-w-7xl mx-auto h-[calc(100vh-3rem)] text-surface-900 dark:text-surface-100">
      <header className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-surface-800 dark:text-surface-100 inline-flex items-center">
          <MessageSquare className="w-6 h-6 mr-2 text-primary-500" /> Team Chat
        </h1>
        {canCreateGeneralChannel ? (
          <button
            className="px-3 py-1.5 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            onClick={() => setShowNew(true)}
          >
            <Plus className="w-4 h-4 mr-1" /> Channel
          </button>
        ) : null}
      </header>
      {!canCreateGeneralChannel && (
        <div className="mb-4 rounded-md border border-surface-200 bg-surface-50 px-4 py-3 text-sm text-surface-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200">
          Team chat is read/write for messages. New general channels are admin-only.
        </div>
      )}

      <div className="grid grid-cols-[220px_1fr] gap-4 h-[calc(100%-3rem)]">
        <aside className="bg-white rounded-lg shadow border border-surface-200 p-2 overflow-y-auto dark:bg-surface-900 dark:border-surface-700">
          {channels.map((c) => (
            <button
              key={c.id}
              className={`w-full text-left px-3 py-2 rounded text-sm ${
                selectedChannelId === c.id
                  ? 'bg-primary-100 text-primary-800 font-semibold dark:bg-primary-500/15 dark:text-primary-200'
                  : 'text-surface-700 hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-800'
              }`}
              onClick={() => { setSelectedChannelId(c.id); setOlderMessages([]); setHasOlder(true); }}
            >
              # {c.name}
            </button>
          ))}
        </aside>

        <section className="bg-white rounded-lg shadow border border-surface-200 flex flex-col overflow-hidden dark:bg-surface-900 dark:border-surface-700">
          <div ref={scrollContainerRef} className="flex-1 overflow-y-auto p-4 space-y-2">
            {messages.length > 0 && hasOlder && (
              <div className="flex justify-center pb-2">
                <button
                  className="px-3 py-1 text-xs rounded border border-surface-200 text-surface-600 hover:bg-surface-50 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none inline-flex items-center gap-1 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
                  disabled={loadingOlder}
                  onClick={loadOlder}
                >
                  {loadingOlder && <Loader2 className="w-3 h-3 animate-spin" />}
                  Load older
                </button>
              </div>
            )}
            {messages.length === 0 && (
              <p className="text-sm text-surface-500 text-center py-8 dark:text-surface-400">No messages yet. Say hi.</p>
            )}
            {messages.map((m) => (
              <div key={m.id} className="text-sm">
                <div className="flex items-baseline gap-2">
                  <span className="font-semibold text-surface-800 dark:text-surface-100">
                    {m.first_name} {m.last_name}
                  </span>
                  <span className="text-xs text-surface-400 dark:text-surface-500">
                    {formatMessageTime(m.created_at)}
                  </span>
                </div>
                <div className="text-surface-700 whitespace-pre-wrap break-words dark:text-surface-300">{m.body}</div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
          <div className="border-t border-surface-200 p-3 relative dark:border-surface-700">
            {showMentions && selectedChannelId && (
              <MentionPicker
                onPick={insertMention}
                onClose={() => setShowMentions(false)}
              />
            )}
            <div className="flex gap-2">
              <textarea
                ref={inputRef}
                className="flex-1 border border-surface-300 rounded px-3 py-2 text-sm resize-none bg-white text-surface-900 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 dark:placeholder:text-surface-500"
                rows={2}
                placeholder="Type a message... use @username to mention someone"
                value={draft}
                aria-controls="mention-picker"
                aria-expanded={showMentions}
                aria-autocomplete="list"
                onChange={(e) => handleDraftChange(e.target.value)}
                onKeyDown={(e) => {
                  // Slack/Discord-style send shortcut:
                  //   Enter           → send (when the draft isn't empty)
                  //   Shift+Enter     → newline
                  //   Ctrl/Cmd+Enter  → send (power-user muscle memory)
                  // IME composition is respected so mid-composition Enter still
                  // commits the candidate instead of firing the message.
                  if (e.key !== 'Enter' || e.nativeEvent.isComposing) return;
                  if (e.shiftKey) return;
                  if (!draft.trim()) return;
                  e.preventDefault();
                  sendMut.mutate();
                }}
              />
              <button
                className="px-4 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                disabled={!draft.trim() || sendMut.isPending}
                onClick={() => sendMut.mutate()}
                aria-label="Send message"
              >
                {sendMut.isPending ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Send className="w-4 h-4" />
                )}
              </button>
            </div>
            <p className="text-xs text-surface-400 mt-1 dark:text-surface-500">
              Press Enter to send. Shift + Enter adds a new line.
            </p>
          </div>
        </section>
      </div>

      {showNew && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
          onClick={(e) => {
            if (e.target === e.currentTarget) setShowNew(false);
          }}
        >
          <div
            ref={newChannelTrapRef}
            role="dialog"
            aria-modal="true"
            aria-labelledby="new-channel-title"
            className="bg-white rounded-lg shadow-xl max-w-md w-full p-5 dark:bg-surface-900"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 id="new-channel-title" className="text-lg font-bold mb-4 text-surface-900 dark:text-surface-100">New channel</h2>
            <label className="block mb-3">
              <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Channel name</span>
              <input
                type="text"
                className="mt-1 w-full border border-surface-300 rounded px-2 py-1.5 text-sm bg-white text-surface-900 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 dark:placeholder:text-surface-500"
                value={newChannelName}
                onChange={(e) => setNewChannelName(e.target.value)}
                placeholder="e.g. front-desk"
              />
            </label>
            <div className="flex gap-2">
              <button
                className="flex-1 px-3 py-2 border border-surface-200 rounded text-sm text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                disabled={!newChannelName || createChannelMut.isPending}
                onClick={() => createChannelMut.mutate()}
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
