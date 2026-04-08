import { useState, useEffect } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { X, MessageSquare, ChevronDown, Loader2, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

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
  const [selectedTemplate, setSelectedTemplate] = useState<any>(null);
  const [showTemplates, setShowTemplates] = useState(false);
  const MAX_CHARS = 160;

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
  });
  const templates: any[] = tplData?.data?.data?.templates || [];

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

  const applyTemplate = (tpl: any) => {
    setSelectedTemplate(tpl);
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
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to send SMS'),
  });

  const handleSend = () => {
    if (!recipient.trim()) return toast.error('Recipient phone is required');
    if (!message.trim()) return toast.error('Message is required');
    sendMutation.mutate();
  };

  // Group templates by category
  const grouped = templates.reduce((acc: Record<string, any[]>, tpl: any) => {
    const cat = tpl.category || 'General';
    if (!acc[cat]) acc[cat] = [];
    acc[cat].push(tpl);
    return acc;
  }, {});

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 backdrop-blur-sm p-4">
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-lg">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-surface-200 dark:border-surface-700">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center">
              <MessageSquare className="h-4 w-4 text-primary-600 dark:text-primary-400" />
            </div>
            <div>
              <h2 className="font-semibold text-surface-900 dark:text-surface-100">Send SMS</h2>
              <p className="text-xs text-surface-400">{customer.first_name} {customer.last_name}{ticket && ` · ${ticket.order_id}`}</p>
            </div>
          </div>
          <button onClick={onClose} className="h-8 w-8 flex items-center justify-center rounded-lg text-surface-400 hover:text-surface-600 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="p-6 space-y-4">
          {/* Recipient */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">To</label>
            <input
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
                    {(tpls as any[]).map((tpl: any) => (
                      <button key={tpl.id} onClick={() => applyTemplate(tpl)}
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
          <button onClick={onClose} className="px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 hover:text-surface-800 dark:hover:text-surface-100 transition-colors">
            Cancel
          </button>
          <button
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
