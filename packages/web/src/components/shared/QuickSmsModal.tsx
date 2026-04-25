import { useEffect, useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { X, MessageSquare, ChevronDown, Loader2, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface SmsTemplate {
  id: number | string;
  name: string;
  content: string;
  category?: string;
}

interface QuickSmsModalProps {
  onClose: () => void;
  customer: { first_name: string; last_name: string; phone?: string; mobile?: string };
  ticket?: { id: number; order_id: string };
  device?: { name: string };
  /** Override recipient phone */
  toPhone?: string;
}

export function QuickSmsModal({ onClose, customer, ticket, device, toPhone }: QuickSmsModalProps) {
  const phone = toPhone || customer.phone || customer.mobile || '';
  const [recipient, setRecipient] = useState(phone);
  const [message, setMessage] = useState('');
  // SCAN-1164: dropped the dead `selectedTemplate` state — only the setter
  // was referenced. applyTemplate still fires the content substitution
  // below; we just don't need to track which template was picked once
  // the text has been pasted.
  const [showTemplates, setShowTemplates] = useState(false);
  const MAX_CHARS = 160;

  // SCAN-1164: Escape-to-close. Matches sibling modals (PinModal, etc.).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
  });
  const rawTemplates = tplData?.data?.data?.templates;
  const templates: SmsTemplate[] = Array.isArray(rawTemplates) ? (rawTemplates as SmsTemplate[]) : [];

  // Template variable substitution
  const substituteTemplate = (content: string) => {
    const vars: Record<string, string> = {
      customer_name: `${customer.first_name} ${customer.last_name}`.trim(),
      first_name: customer.first_name,
      device_name: device?.name || 'your device',
      ticket_id: ticket?.order_id || '',
    };
    return content.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? `{{${k}}}`);
  };

  const applyTemplate = (tpl: SmsTemplate) => {
    setMessage(substituteTemplate(tpl.content));
    setShowTemplates(false);
  };

  const sendMutation = useMutation({
    mutationFn: () => smsApi.send({
      to: recipient,
      message,
      entity_type: ticket ? 'ticket' : 'customer',
      entity_id: ticket?.id,
    }),
    onSuccess: () => {
      toast.success('SMS sent');
      onClose();
    },
    onError: (e: unknown) => {
      const msg =
        e && typeof e === 'object' && 'response' in e
          ? (e as { response?: { data?: { message?: string } } }).response?.data?.message
          : null;
      toast.error(msg || 'Failed to send SMS');
    },
  });

  const handleSend = () => {
    if (!recipient.trim()) return toast.error('Recipient phone is required');
    if (!message.trim()) return toast.error('Message is required');
    sendMutation.mutate();
  };

  // Group templates by category
  const grouped = templates.reduce<Record<string, SmsTemplate[]>>((acc, tpl) => {
    const cat = tpl.category || 'General';
    if (!acc[cat]) acc[cat] = [];
    acc[cat].push(tpl);
    return acc;
  }, {});

  return (
    // SCAN-1164: backdrop click closes; inner card stops propagation.
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="quick-sms-title"
        className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-lg"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-surface-200 dark:border-surface-700">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center">
              <MessageSquare className="h-4 w-4 text-primary-600 dark:text-primary-400" />
            </div>
            <div>
              <h2 id="quick-sms-title" className="font-semibold text-surface-900 dark:text-surface-100">Send SMS</h2>
              <p className="text-xs text-surface-400">{customer.first_name} {customer.last_name}{ticket && ` · ${ticket.order_id}`}</p>
            </div>
          </div>
          <button type="button" aria-label="Close" onClick={onClose} className="h-8 w-8 flex items-center justify-center rounded-lg text-surface-400 hover:text-surface-600 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="p-6 space-y-4">
          {/* Recipient */}
          <div>
            <label htmlFor="quick-sms-recipient" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">To</label>
            <input
              id="quick-sms-recipient"
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              className="input w-full font-mono text-sm"
              placeholder="+1 303-555-0100"
            />
          </div>

          {/* Template picker */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300">Message</label>
              <button
                type="button"
                onClick={() => setShowTemplates(!showTemplates)}
                className="inline-flex items-center gap-1 text-xs text-primary-600 dark:text-primary-400 hover:text-primary-700 font-medium"
              >
                Use template <ChevronDown className={cn('h-3 w-3 transition-transform', showTemplates && 'rotate-180')} />
              </button>
            </div>

            {showTemplates && (
              <div className="mb-3 border border-surface-200 dark:border-surface-700 rounded-xl overflow-hidden max-h-52 overflow-y-auto">
                {Object.entries(grouped).map(([cat, tpls]) => (
                  <div key={cat}>
                    <div className="px-3 py-1.5 bg-surface-50 dark:bg-surface-800 text-xs font-semibold text-surface-500 dark:text-surface-400 uppercase tracking-wider sticky top-0">
                      {cat}
                    </div>
                    {tpls.map((tpl) => (
                      <button type="button" key={tpl.id} onClick={() => applyTemplate(tpl)}
                        className="w-full text-left px-3 py-2.5 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors border-b border-surface-100 dark:border-surface-700/50 last:border-0">
                        <p className="text-sm font-medium text-surface-800 dark:text-surface-200">{tpl.name}</p>
                        <p className="text-xs text-surface-400 truncate mt-0.5">{substituteTemplate(tpl.content)}</p>
                      </button>
                    ))}
                  </div>
                ))}
                {templates.length === 0 && (
                  <div className="px-3 py-4 text-sm text-center text-surface-400">No templates found. Add them in Settings.</div>
                )}
              </div>
            )}

            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              rows={4}
              maxLength={1600}
              className="input w-full text-sm resize-none"
              placeholder="Type your message..."
              autoFocus={!showTemplates}
            />
            <div className="flex items-center justify-between mt-1">
              <p className="text-xs text-surface-400">Reply STOP to opt out</p>
              <p className={cn('text-xs font-mono', message.length > MAX_CHARS ? 'text-amber-500' : 'text-surface-400')}>
                {message.length}/{MAX_CHARS}{message.length > MAX_CHARS && ` (${Math.ceil(message.length / MAX_CHARS)} msgs)`}
              </p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-6 py-4 border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 rounded-b-2xl">
          <button type="button" onClick={onClose} className="px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 hover:text-surface-800 dark:hover:text-surface-100 transition-colors">
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSend}
            disabled={!message.trim() || !recipient.trim() || sendMutation.isPending}
            className="inline-flex items-center gap-2 px-5 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-xl text-sm font-semibold transition-colors disabled:opacity-50"
          >
            {sendMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            Send SMS
          </button>
        </div>
      </div>
    </div>
  );
}
