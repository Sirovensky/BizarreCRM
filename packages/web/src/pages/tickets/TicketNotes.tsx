import { useState, useMemo } from 'react';
import {
  FileText, Wrench, MessageSquare, Send, Flag, Loader2, Clock,
} from 'lucide-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import DOMPurify from 'dompurify';
import { ticketApi, smsApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { useDraft } from '@/hooks/useDraft';
import { cn } from '@/utils/cn';
import { formatDateTime, formatPhone, timeAgo } from '@/utils/format';
import type { TicketNote, TicketHistory } from '@bizarre-crm/shared';

// ─── Constants ──────────────────────────────────────────────────────

const ACTIVITY_FILTERS = ['All', 'Notes', 'SMS', 'System'] as const;

// ─── Helpers ────────────────────────────────────────────────────────

function initials(first?: string, last?: string) {
  return `${(first || '?').charAt(0)}${(last || '').charAt(0)}`.toUpperCase();
}

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketNotesProps {
  ticketId: number;
  notes: TicketNote[];
  history: TicketHistory[];
  smsMessages: any[];
  customerPhone?: string | null;
  customerEmail?: string | null;
  activeTab: 'overview' | 'notes' | 'photos' | 'parts';
  invalidateTicket: () => void;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketNotes({
  ticketId,
  notes,
  history,
  smsMessages,
  customerPhone,
  activeTab,
  invalidateTicket,
}: TicketNotesProps) {
  const queryClient = useQueryClient();
  const currentUser = useAuthStore((s) => s.user);

  // ─── Local state ──────────────────────────────────────────────────
  const [noteType, setNoteType] = useState('internal');
  const [noteContent, setNoteContent, clearNoteDraft] = useDraft(`draft_note_ticket_${ticketId}`);
  const [noteFlagged, setNoteFlagged] = useState(false);
  const [noteTabFilter, setNoteTabFilter] = useState<typeof ACTIVITY_FILTERS[number]>('All');
  const [smsMode, setSmsMode] = useState(false);
  const [smsContent, setSmsContent] = useState('');

  // ─── Mutations ────────────────────────────────────────────────────
  // D4-1: Optimistic note append. We inject a temp note (negative id) into
  // the cached ticket so the new entry appears in the timeline the instant
  // the user clicks Save. Real server note replaces it on settle. If the
  // server rejects, we roll back to the pre-mutation cache snapshot.
  const addNoteMut = useMutation({
    mutationFn: (data: { type: string; content: string; is_flagged?: boolean }) =>
      ticketApi.addNote(ticketId, data),
    onMutate: async (vars) => {
      await queryClient.cancelQueries({ queryKey: ['ticket', ticketId] });
      const prev = queryClient.getQueryData(['ticket', ticketId]);
      const tempId = -Date.now();
      queryClient.setQueryData(['ticket', ticketId], (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const t = clone?.data?.data;
        if (t) {
          const noteType = (vars.type === 'diagnostic' || vars.type === 'email' || vars.type === 'customer')
            ? vars.type
            : 'internal';
          const optimisticNote: TicketNote = {
            id: tempId,
            ticket_id: ticketId,
            ticket_device_id: null,
            user_id: currentUser?.id ?? 0,
            type: noteType,
            content: vars.content,
            is_flagged: !!vars.is_flagged,
            parent_id: null,
            created_at: new Date().toISOString(),
            user: currentUser
              ? {
                  id: currentUser.id,
                  first_name: currentUser.first_name,
                  last_name: currentUser.last_name,
                  avatar_url: currentUser.avatar_url ?? null,
                }
              : undefined,
          };
          t.notes = Array.isArray(t.notes) ? [optimisticNote, ...t.notes] : [optimisticNote];
        }
        return clone;
      });
      // Clear draft eagerly so the textarea resets immediately.
      clearNoteDraft();
      return { prev };
    },
    onError: (_err, _vars, ctx: any) => {
      if (ctx?.prev) queryClient.setQueryData(['ticket', ticketId], ctx.prev);
      toast.error('Failed to add note');
    },
    onSuccess: () => {
      // Reset the flag toggle so a subsequent plain "Save" doesn't re-send is_flagged: true.
      setNoteFlagged(false);
      toast.success('Note added');
    },
    onSettled: () => {
      invalidateTicket();
    },
  });

  const sendSmsMut = useMutation({
    mutationFn: (message: string) => smsApi.send({ to: customerPhone!, message, entity_type: 'ticket', entity_id: ticketId }),
    onSuccess: () => {
      toast.success('SMS sent');
      setSmsContent('');
      queryClient.invalidateQueries({ queryKey: ['ticket-sms', customerPhone] });
    },
    onError: () => toast.error('Failed to send SMS'),
  });

  // ─── Unified timeline merge ─────────────────────────────────────
  const timelineEntries = useMemo(() => {
    const entries: { id: string; type: 'note' | 'sms' | 'system'; timestamp: string; data: any }[] = [];

    notes.forEach(n => entries.push({
      id: `note-${n.id}`,
      type: 'note',
      timestamp: n.created_at,
      data: n,
    }));

    history.filter(h => h.action !== 'note_added').forEach(h => entries.push({
      id: `sys-${h.id}`,
      type: 'system',
      timestamp: h.created_at,
      data: h,
    }));

    smsMessages.forEach(m => entries.push({
      id: `sms-${m.id}`,
      type: 'sms',
      timestamp: m.created_at,
      data: m,
    }));

    entries.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());

    if (noteTabFilter === 'Notes') return entries.filter(e => e.type === 'note');
    if (noteTabFilter === 'SMS') return entries.filter(e => e.type === 'sms');
    if (noteTabFilter === 'System') return entries.filter(e => e.type === 'system');
    return entries;
  }, [notes, history, smsMessages, noteTabFilter]);

  if (activeTab !== 'notes' && activeTab !== 'overview') return null;

  return (
    <div className="card p-6">
      {/* Filter chips */}
      <div className="flex gap-1.5 mb-4 overflow-x-auto">
        {ACTIVITY_FILTERS.map((filter) => {
          const count = filter === 'All' ? notes.length + history.length + smsMessages.length
            : filter === 'Notes' ? notes.length
            : filter === 'SMS' ? smsMessages.length
            : history.length;
          return (
            <button key={filter} onClick={() => setNoteTabFilter(filter)}
              className={cn(
                'whitespace-nowrap px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1.5 text-xs font-medium rounded-full border transition-colors',
                noteTabFilter === filter
                  ? 'border-primary-500 bg-primary-50 text-primary-700 dark:bg-primary-900/20 dark:text-primary-400 dark:border-primary-600'
                  : 'border-surface-200 text-surface-500 hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600',
              )}>
              {filter}
              {count > 0 && <span className="ml-1.5 text-[10px] bg-surface-200/70 dark:bg-surface-600 rounded-full px-1.5 py-0.5">{count}</span>}
            </button>
          );
        })}
      </div>

      {/* Compose area */}
      <div className="mb-5 border border-surface-200 dark:border-surface-700 rounded-lg overflow-hidden">
        <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
          {/* Internal / Diagnostic slider switch */}
          <div className={cn('relative flex items-center rounded-full border border-surface-200 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 p-0.5 transition-opacity',
            smsMode ? 'opacity-50' : '',
          )}>
            {!smsMode && (
              <div className={cn('absolute top-0.5 bottom-0.5 rounded-full bg-white dark:bg-surface-600 shadow-sm transition-all duration-200',
                noteType === 'diagnostic' ? 'left-[50%] right-0.5' : 'left-0.5 right-[50%]'
              )} />
            )}
            <button onClick={() => { setSmsMode(false); setNoteType('internal'); }} title="Internal note"
              className={cn('relative z-10 flex items-center gap-1 rounded-full px-4 py-2 min-h-[44px] md:min-h-0 md:px-2.5 md:py-1 text-[11px] font-medium transition-colors',
                !smsMode && noteType === 'internal' ? 'text-surface-800 dark:text-surface-100' : 'text-surface-400',
              )}>
              <FileText className="h-3 w-3" /> Internal
            </button>
            <button onClick={() => { setSmsMode(false); setNoteType('diagnostic'); }} title="Diagnostic note"
              className={cn('relative z-10 flex items-center gap-1 rounded-full px-4 py-2 min-h-[44px] md:min-h-0 md:px-2.5 md:py-1 text-[11px] font-medium transition-colors',
                !smsMode && noteType === 'diagnostic' ? 'text-amber-700 dark:text-amber-400' : 'text-surface-400',
              )}>
              <Wrench className="h-3 w-3" /> Diagnostic
            </button>
          </div>

          {/* SMS toggle button. Email note mode stays hidden until outbound email dispatch is wired. */}
          <div className="flex items-center gap-0.5">
            <button
              onClick={() => { if (customerPhone) { setSmsMode((v) => !v); if (!smsMode) setNoteType('internal'); } }}
              disabled={!customerPhone}
              title={customerPhone ? (smsMode ? 'Switch to notes' : 'Send SMS') : 'No phone on file'}
              aria-label={customerPhone ? (smsMode ? 'Switch to notes' : 'Send SMS') : 'Send SMS (no phone on file)'}
              aria-pressed={smsMode}
              className={cn('inline-flex items-center justify-center rounded-md transition-colors min-h-[44px] min-w-[44px] md:min-h-0 md:min-w-0 md:p-1.5',
                !customerPhone ? 'text-surface-300 dark:text-surface-600 cursor-not-allowed'
                : smsMode ? 'bg-green-100 text-green-600 dark:bg-green-900/30 dark:text-green-400'
                : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700',
              )}>
              <MessageSquare className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          </div>

          {/* SMS mode label */}
          {smsMode && (
            <span className="text-[11px] font-medium text-green-600 dark:text-green-400">
              SMS to {customerPhone ? formatPhone(customerPhone) : 'customer'}
            </span>
          )}

          <div className="ml-auto flex items-center gap-2">
            {!smsMode ? (
              <>
                <button
                  onClick={() => {
                    if (!noteContent.trim()) { toast.error('Note cannot be empty'); return; }
                    setNoteFlagged(true);
                    addNoteMut.mutate({ type: noteType, content: noteContent.trim(), is_flagged: true });
                  }}
                  disabled={addNoteMut.isPending || !noteContent.trim()}
                  className="inline-flex items-center justify-center gap-1 rounded-md border border-surface-200 dark:border-surface-700 px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-2.5 md:py-1 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 transition-colors"
                >
                  <Flag className="h-3 w-3" /> Save & Flag
                </button>
                <button
                  onClick={() => {
                    if (!noteContent.trim()) { toast.error('Note cannot be empty'); return; }
                    addNoteMut.mutate({ type: noteType, content: noteContent.trim(), is_flagged: noteFlagged });
                  }}
                  disabled={addNoteMut.isPending || !noteContent.trim()}
                  className="inline-flex items-center justify-center gap-1 rounded-md bg-primary-600 hover:bg-primary-700 text-white px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1 text-xs font-medium disabled:opacity-50 transition-colors"
                >
                  {addNoteMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Send className="h-3 w-3" />}
                  Save
                </button>
              </>
            ) : (
              <button
                onClick={() => {
                  if (!smsContent.trim()) { toast.error('Message cannot be empty'); return; }
                  sendSmsMut.mutate(smsContent.trim());
                }}
                disabled={sendSmsMut.isPending || !smsContent.trim()}
                className="inline-flex items-center justify-center gap-1 rounded-md bg-green-600 hover:bg-green-700 text-white px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1 text-xs font-medium disabled:opacity-50 transition-colors"
              >
                {sendSmsMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Send className="h-3 w-3" />}
                Send SMS
              </button>
            )}
          </div>
        </div>
        {!smsMode ? (
          <textarea value={noteContent} onChange={(e) => setNoteContent(e.target.value)}
            rows={3} placeholder={`Enter ${noteType} comment...`}
            className="w-full px-3 py-2 text-sm bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-y" />
        ) : (
          <div>
            <textarea value={smsContent} onChange={(e) => setSmsContent(e.target.value)}
              rows={3} placeholder="Type SMS message..."
              maxLength={1600}
              className="w-full px-3 py-2 text-sm bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-y" />
            {smsContent.length > 0 && (
              <div className="px-3 pb-1 text-right text-[10px] text-surface-400">
                {smsContent.length} / {Math.ceil(smsContent.length / 160) || 1} segment{Math.ceil(smsContent.length / 160) > 1 ? 's' : ''}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Unified timeline */}
      {timelineEntries.length === 0 ? (
        <p className="py-8 text-center text-sm text-surface-400">No activity yet</p>
      ) : (
        <div className="space-y-2 max-h-[600px] overflow-y-auto">
          {timelineEntries.map((entry) => {
            if (entry.type === 'note') {
              const note = entry.data;
              const bgColor = note.type === 'diagnostic'
                ? 'bg-amber-50/50 dark:bg-amber-900/10 border-l-2 border-l-amber-400'
                : note.type === 'email'
                ? 'bg-blue-50/50 dark:bg-blue-900/10 border-l-2 border-l-blue-400'
                : '';
              return (
                <div key={entry.id} className={cn('flex gap-3 rounded-lg p-3 group', bgColor)}>
                  <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary-100 text-xs font-medium text-primary-700 dark:bg-primary-900/30 dark:text-primary-300">
                    {initials(note.user?.first_name, note.user?.last_name)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-medium text-surface-800 dark:text-surface-200">
                        {note.user ? `${note.user.first_name} ${note.user.last_name}` : 'System'}
                      </span>
                      <span className={cn('text-[10px] font-medium px-1.5 py-0.5 rounded',
                        note.type === 'diagnostic' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                        : note.type === 'email' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                        : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                      )}>{note.type}</span>
                      {note.is_flagged && <Flag className="h-3 w-3 text-amber-500" />}
                      <span className="text-xs text-surface-400">{formatDateTime(note.created_at)}</span>
                    </div>
                    <p className="mt-1 text-sm text-surface-700 dark:text-surface-300 whitespace-pre-wrap">{note.content}</p>
                  </div>
                </div>
              );
            }

            if (entry.type === 'sms') {
              const msg = entry.data;
              const isOutbound = msg.direction === 'outbound';
              return (
                <div key={entry.id} className={cn('flex', isOutbound ? 'justify-end' : 'justify-start')}>
                  <div className={cn('max-w-[75%] rounded-xl px-3 py-2',
                    isOutbound
                      ? 'bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800'
                      : 'bg-surface-50 dark:bg-surface-800 border border-surface-200 dark:border-surface-700'
                  )}>
                    <p className="text-sm text-surface-800 dark:text-surface-200">{msg.message}</p>
                    <div className="mt-1 flex items-center gap-1.5 text-[10px] text-surface-400">
                      {isOutbound && (
                        <span className={cn(
                          msg.status === 'delivered' ? 'text-green-500' : msg.status === 'failed' ? 'text-red-500' : 'text-surface-400'
                        )}>
                          {msg.status === 'delivered' ? '\u2713\u2713' : msg.status === 'sent' ? '\u2713' : msg.status === 'failed' ? '\u2717' : '\u23F3'}
                        </span>
                      )}
                      <span>{isOutbound ? (msg.sender_name || 'Sent') : (msg.from_number || 'Customer')}</span>
                      <span>&middot;</span>
                      <span>{formatDateTime(msg.created_at)}</span>
                    </div>
                  </div>
                </div>
              );
            }

            // System event
            const event = entry.data;
            return (
              <div key={entry.id} className="flex gap-3 py-1.5 px-2 rounded-md bg-surface-50/50 dark:bg-surface-800/30">
                <div className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-surface-100 dark:bg-surface-800 text-surface-400">
                  {event.user ? (
                    <span className="text-[8px] font-semibold">{initials(event.user.first_name, event.user.last_name)}</span>
                  ) : (
                    <Clock className="h-3 w-3" />
                  )}
                </div>
                <div className="flex-1 flex items-center gap-2 min-w-0">
                  <p className="text-xs text-surface-500 dark:text-surface-400"
                    dangerouslySetInnerHTML={{
                      __html: DOMPurify.sanitize(event.description || '', {
                        ALLOWED_TAGS: ['b', 'i', 'em', 'strong'],
                        ALLOWED_ATTR: [],
                      })
                    }}
                  />
                  <span className="shrink-0 text-[10px] text-surface-300 dark:text-surface-500">{timeAgo(event.created_at)}</span>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
