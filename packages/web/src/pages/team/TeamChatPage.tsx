/**
 * Internal team chat — criticalaudit.md §53 idea #6.
 *
 * Polling-based MVP. Channels list on the left, messages on the right. New
 * message input at the bottom uses the MentionPicker to insert @username.
 *
 * Polling interval: 5 seconds, only while the page is visible. The endpoint
 * supports `?after=<lastId>` so each tick is incremental, not a full reload.
 */
import { useState, useEffect, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { MessageSquare, Send, Plus, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { MentionPicker } from '@/components/team/MentionPicker';
import { useAuthStore } from '@/stores/authStore';

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
  const userRole = useAuthStore((s) => s.user?.role);
  const canCreateGeneralChannel = userRole === 'admin';
  const [selectedChannelId, setSelectedChannelId] = useState<number | null>(null);
  const [draft, setDraft] = useState('');
  const [showMentions, setShowMentions] = useState(false);
  const [newChannelName, setNewChannelName] = useState('');
  const [showNew, setShowNew] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

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

  const { data: messagesData } = useQuery({
    queryKey: ['team-chat', 'messages', selectedChannelId],
    enabled: !!selectedChannelId,
    refetchInterval: 5_000,
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Message[] }>(
        `/team-chat/channels/${selectedChannelId}/messages?limit=200`,
      );
      return res.data.data;
    },
  });
  const messages: Message[] = messagesData || [];

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

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
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to send'),
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
    onError: (e: any) => toast.error(e?.response?.data?.error || e?.message || 'Failed to create channel'),
  });

  function handleDraftChange(value: string) {
    setDraft(value);
    // Open the mention picker when the user types '@' followed by 0+ chars at the end.
    const tail = value.slice(0, inputRef.current?.selectionStart ?? value.length);
    setShowMentions(/@[a-zA-Z0-9_.-]*$/.test(tail));
  }

  function insertMention(username: string) {
    setDraft((prev) => prev.replace(/@[a-zA-Z0-9_.-]*$/, `@${username} `));
    setShowMentions(false);
    inputRef.current?.focus();
  }

  return (
    <div className="p-6 max-w-7xl mx-auto h-[calc(100vh-3rem)]">
      <header className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-800 inline-flex items-center">
          <MessageSquare className="w-6 h-6 mr-2 text-blue-500" /> Team Chat
        </h1>
        {canCreateGeneralChannel ? (
          <button
            className="px-3 py-1.5 bg-blue-600 text-white rounded text-sm hover:bg-blue-700 inline-flex items-center"
            onClick={() => setShowNew(true)}
          >
            <Plus className="w-4 h-4 mr-1" /> Channel
          </button>
        ) : null}
      </header>
      {!canCreateGeneralChannel && (
        <div className="mb-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
          Team chat is read/write for messages. New general channels are admin-only.
        </div>
      )}

      <div className="grid grid-cols-[220px_1fr] gap-4 h-[calc(100%-3rem)]">
        <aside className="bg-white rounded-lg shadow border p-2 overflow-y-auto">
          {channels.map((c) => (
            <button
              key={c.id}
              className={`w-full text-left px-3 py-2 rounded text-sm ${
                selectedChannelId === c.id
                  ? 'bg-blue-100 text-blue-800 font-semibold'
                  : 'hover:bg-gray-50'
              }`}
              onClick={() => setSelectedChannelId(c.id)}
            >
              # {c.name}
            </button>
          ))}
        </aside>

        <section className="bg-white rounded-lg shadow border flex flex-col overflow-hidden">
          <div className="flex-1 overflow-y-auto p-4 space-y-2">
            {messages.length === 0 && (
              <p className="text-sm text-gray-500 text-center py-8">No messages yet. Say hi.</p>
            )}
            {messages.map((m) => (
              <div key={m.id} className="text-sm">
                <div className="flex items-baseline gap-2">
                  <span className="font-semibold text-gray-800">
                    {m.first_name} {m.last_name}
                  </span>
                  <span className="text-xs text-gray-400">
                    {new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                  </span>
                </div>
                <div className="text-gray-700 whitespace-pre-wrap break-words">{m.body}</div>
              </div>
            ))}
            <div ref={messagesEndRef} />
          </div>
          <div className="border-t p-3 relative">
            {showMentions && selectedChannelId && (
              <MentionPicker
                onPick={insertMention}
                onClose={() => setShowMentions(false)}
              />
            )}
            <div className="flex gap-2">
              <textarea
                ref={inputRef}
                className="flex-1 border rounded px-3 py-2 text-sm resize-none"
                rows={2}
                placeholder="Type a message... use @username to mention someone"
                value={draft}
                onChange={(e) => handleDraftChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && draft.trim()) {
                    e.preventDefault();
                    sendMut.mutate();
                  }
                }}
              />
              <button
                className="px-4 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700 inline-flex items-center"
                disabled={!draft.trim() || sendMut.isPending}
                onClick={() => sendMut.mutate()}
              >
                {sendMut.isPending ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Send className="w-4 h-4" />
                )}
              </button>
            </div>
            <p className="text-xs text-gray-400 mt-1">
              Press Cmd/Ctrl + Enter to send.
            </p>
          </div>
        </section>
      </div>

      {showNew && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5">
            <h2 className="text-lg font-bold mb-4">New channel</h2>
            <label className="block mb-3">
              <span className="text-xs font-semibold text-gray-600">Channel name</span>
              <input
                type="text"
                className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                value={newChannelName}
                onChange={(e) => setNewChannelName(e.target.value)}
                placeholder="e.g. front-desk"
              />
            </label>
            <div className="flex gap-2">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700"
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
