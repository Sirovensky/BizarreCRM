import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Check, Copy, Loader2, AlertCircle, ExternalLink, Phone, MessageSquare, Mic, Bot } from 'lucide-react';
import { ComingSoonBadge } from './components/ComingSoonBadge';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import axios from '@/api/client';

interface ProviderField {
  key: string;
  label: string;
  placeholder: string;
  sensitive: boolean;
  required: boolean;
}

interface ProviderInfo {
  type: string;
  label: string;
  description: string;
  fields: ProviderField[];
  supportsSms: boolean;
  supportsMms: boolean;
  supportsVoice: boolean;
  supportsRecording: boolean;
  supportsTranscription: boolean;
}

export function SmsVoiceSettings() {
  const queryClient = useQueryClient();
  const [selectedProvider, setSelectedProvider] = useState<string>('console');
  const [credentials, setCredentials] = useState<Record<string, string>>({});
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  // WEB-W1-029: auto-reply controlled state
  const [autoReplyEnabled, setAutoReplyEnabled] = useState(false);
  const [autoReplyMessage, setAutoReplyMessage] = useState('');

  // Load provider registry
  const { data: providersData } = useQuery({
    queryKey: ['sms-providers'],
    queryFn: async () => {
      const res = await axios.get('/settings/sms/providers');
      return res.data.data as ProviderInfo[];
    },
  });

  // Load current config — use the canonical ['settings', 'config'] key so this
  // component shares the same cache entry as ReceiptSettings, PosSettings, etc.
  // Previously used ['settings-config'] which meant saves from other tabs were
  // invisible here and vice-versa.
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
  });

  // Populate from saved config
  useEffect(() => {
    if (!configData?.data?.data) return;
    const cfg = configData.data.data;
    const saved = cfg.sms_provider_type || 'console';
    setSelectedProvider(saved);
    // Load saved credentials for the selected provider
    const creds: Record<string, string> = {};
    for (const [key, val] of Object.entries(cfg)) {
      if (key.startsWith(`sms_${saved}_`)) {
        const field = key.replace(`sms_${saved}_`, '');
        creds[field] = val as string;
      }
    }
    setCredentials(creds);
    // WEB-W1-029: populate auto-reply state
    setAutoReplyEnabled(cfg.auto_reply_enabled === '1');
    setAutoReplyMessage(cfg.auto_reply_message || '');
  }, [configData]);

  const providers = providersData || [];
  const activeProvider = providers.find(p => p.type === selectedProvider);

  function handleProviderSelect(type: string) {
    setSelectedProvider(type);
    setTestResult(null);
    // Load saved credentials for this provider from config
    const cfg = configData?.data?.data || {};
    const creds: Record<string, string> = {};
    for (const [key, val] of Object.entries(cfg)) {
      if (key.startsWith(`sms_${type}_`)) {
        creds[key.replace(`sms_${type}_`, '')] = val as string;
      }
    }
    setCredentials(creds);
  }

  function updateCredential(field: string, value: string) {
    setCredentials(prev => ({ ...prev, [field]: value }));
    setTestResult(null);
  }

  async function handleTestConnection() {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await axios.post('/settings/sms/test-connection', {
        provider_type: selectedProvider,
        credentials,
      });
      setTestResult({ ok: true, message: res.data.data.message });
    } catch (err: unknown) {
      const msg = (err as any)?.response?.data?.message || 'Connection test failed';
      setTestResult({ ok: false, message: msg });
    } finally {
      setTesting(false);
    }
  }

  async function handleSave() {
    try {
      // Build config entries
      const entries: Record<string, string> = { sms_provider_type: selectedProvider };
      for (const [field, value] of Object.entries(credentials)) {
        entries[`sms_${selectedProvider}_${field}`] = value;
      }
      // Also save voice settings
      const voiceFields = ['voice_auto_record', 'voice_auto_transcribe', 'voice_announce_recording', 'voice_forward_number', 'voice_inbound_action'];
      for (const key of voiceFields) {
        const el = document.getElementById(key) as HTMLInputElement | HTMLSelectElement | null;
        if (el) {
          entries[key] = el.type === 'checkbox' ? ((el as HTMLInputElement).checked ? '1' : '0') : el.value;
        }
      }

      // WEB-W1-029: persist auto-reply settings
      entries['auto_reply_enabled'] = autoReplyEnabled ? '1' : '0';
      entries['auto_reply_message'] = autoReplyMessage;

      await settingsApi.updateConfig(entries);
      // Reload provider on server
      await axios.post('/settings/sms/reload');
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      toast.success('SMS & Voice settings saved');
    } catch (err: unknown) {
      toast.error((err as any)?.response?.data?.message || 'Failed to save');
    }
  }

  function copyToClipboard(text: string, label: string) {
    navigator.clipboard.writeText(text);
    setCopiedField(label);
    setTimeout(() => setCopiedField(null), 2000);
    toast.success(`${label} copied`);
  }

  const cfg = configData?.data?.data || {};
  const serverUrl = window.location.origin;

  return (
    <div className="space-y-8">
      {/* Provider Selection */}
      <section>
        <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-3">SMS/MMS Provider</h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {providers.map(p => (
            <button
              key={p.type}
              onClick={() => handleProviderSelect(p.type)}
              className={`text-left rounded-lg border p-4 transition-all ${
                selectedProvider === p.type
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 ring-1 ring-primary-500'
                  : 'border-surface-200 dark:border-surface-700 hover:border-surface-300 dark:hover:border-surface-600'
              }`}
            >
              <div className="flex items-center justify-between mb-1">
                <span className="font-medium text-sm text-surface-900 dark:text-surface-100">{p.label}</span>
                <div className="flex gap-1">
                  {p.supportsSms && <MessageSquare className="w-3.5 h-3.5 text-green-500" />}
                  {p.supportsVoice && <Phone className="w-3.5 h-3.5 text-blue-500" />}
                  {p.supportsRecording && <Mic className="w-3.5 h-3.5 text-purple-500" />}
                </div>
              </div>
              <p className="text-xs text-surface-500 dark:text-surface-400">{p.description}</p>
            </button>
          ))}
        </div>
      </section>

      {/* Credentials */}
      {activeProvider && activeProvider.fields.length > 0 && (
        <section>
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-3">
            {activeProvider.label} Credentials
          </h3>
          <div className="space-y-3 max-w-lg">
            {activeProvider.fields.map(field => (
              <div key={field.key}>
                <label htmlFor={`cred-${field.key}`} className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">
                  {field.label} {field.required && <span className="text-red-500">*</span>}
                </label>
                <input
                  id={`cred-${field.key}`}
                  type={field.sensitive ? 'password' : 'text'}
                  placeholder={field.placeholder}
                  value={credentials[field.key] || ''}
                  onChange={e => updateCredential(field.key, e.target.value)}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                />
              </div>
            ))}
            <div className="flex gap-3 pt-2">
              <button
                onClick={handleTestConnection}
                disabled={testing}
                className="rounded-lg border border-surface-300 dark:border-surface-600 px-4 py-2 text-sm font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-50"
              >
                {testing ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Test Connection'}
              </button>
              <button
                onClick={handleSave}
                className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 hover:bg-primary-700"
              >
                Save Provider
              </button>
            </div>
            {testResult && (
              <div className={`flex items-center gap-2 text-sm ${testResult.ok ? 'text-green-600' : 'text-red-600'}`}>
                {testResult.ok ? <Check className="w-4 h-4" /> : <AlertCircle className="w-4 h-4" />}
                {testResult.message}
              </div>
            )}
          </div>
        </section>
      )}

      {/* Webhook URLs */}
      <section>
        <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-1">Webhook URLs</h3>
        <p className="text-xs text-surface-400 dark:text-surface-500 mb-3">
          Paste these URLs into your provider's dashboard to receive inbound messages and delivery updates.
        </p>
        <div className="space-y-2 max-w-lg">
          {[
            { label: 'SMS Inbound', url: `${serverUrl}/api/v1/sms/inbound-webhook` },
            { label: 'SMS Delivery Status', url: `${serverUrl}/api/v1/sms/status-webhook` },
            { label: 'Voice Inbound', url: `${serverUrl}/api/v1/voice/inbound-webhook` },
            { label: 'Voice Status', url: `${serverUrl}/api/v1/voice/status-webhook` },
            { label: 'Recording Ready', url: `${serverUrl}/api/v1/voice/recording-webhook` },
            { label: 'Transcription', url: `${serverUrl}/api/v1/voice/transcription-webhook` },
          ].map(wh => (
            <div key={wh.label} className="flex items-center gap-2">
              <span className="text-xs text-surface-500 dark:text-surface-400 w-32 flex-shrink-0">{wh.label}</span>
              <code className="flex-1 text-xs bg-surface-100 dark:bg-surface-800 px-2 py-1.5 rounded border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 truncate">{wh.url}</code>
              <button
                onClick={() => copyToClipboard(wh.url, wh.label)}
                className="text-surface-400 hover:text-primary-600 flex-shrink-0"
                title="Copy to clipboard"
              >
                {copiedField === wh.label ? <Check className="w-4 h-4 text-green-500" /> : <Copy className="w-4 h-4" />}
              </button>
            </div>
          ))}
        </div>
      </section>

      {/* Voice Settings */}
      <section>
        <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-3">Voice Settings</h3>
        <div className="space-y-3 max-w-lg">
          <label className="flex items-center gap-3">
            <input
              id="voice_auto_record"
              type="checkbox"
              defaultChecked={cfg.voice_auto_record === '1'}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Automatically record all calls</span>
          </label>
          <label className="flex items-center gap-3">
            <input
              id="voice_auto_transcribe"
              type="checkbox"
              defaultChecked={cfg.voice_auto_transcribe === '1'}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Automatically transcribe recordings</span>
          </label>
          <label className="flex items-center gap-3">
            <input
              id="voice_announce_recording"
              type="checkbox"
              defaultChecked={cfg.voice_announce_recording === '1'}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Announce "this call may be recorded" to callers</span>
          </label>
          <div>
            <label htmlFor="voice_inbound_action" className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">
              Inbound call action
            </label>
            <select
              id="voice_inbound_action"
              defaultValue={cfg.voice_inbound_action || 'ring'}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
            >
              <option value="ring">Ring in browser</option>
              <option value="forward">Forward to phone</option>
              <option value="voicemail">Voicemail</option>
            </select>
          </div>
          <div>
            <label htmlFor="voice_forward_number" className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">
              Forward inbound calls to
            </label>
            <input
              id="voice_forward_number"
              type="tel"
              placeholder="+13035551234 (leave blank to disable)"
              defaultValue={cfg.voice_forward_number || ''}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
            />
          </div>
        </div>
      </section>

      {/* Auto-Reply — WEB-W1-029 */}
      <section>
        <div className="flex items-center gap-2 mb-3">
          <Bot className="w-4 h-4 text-surface-500" />
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200">Auto-Reply</h3>
        </div>
        <div className="space-y-3 max-w-lg">
          <label className="flex items-center gap-3">
            <input
              type="checkbox"
              checked={autoReplyEnabled}
              onChange={(e) => setAutoReplyEnabled(e.target.checked)}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Enable auto-reply for inbound SMS</span>
          </label>
          {autoReplyEnabled && (
            <div>
              <label className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">
                Auto-reply message
              </label>
              <textarea
                value={autoReplyMessage}
                onChange={(e) => setAutoReplyMessage(e.target.value)}
                placeholder="e.g. Thanks for reaching out! We'll get back to you shortly."
                rows={3}
                className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none resize-none"
              />
              <p className="mt-1 text-xs text-surface-400">Sent once per sender per 24-hour window.</p>
            </div>
          )}
          <button
            onClick={handleSave}
            className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 hover:bg-primary-700"
          >
            Save Auto-Reply
          </button>
        </div>
      </section>

      {/* 3CX Integration — WEB-W1-030: Coming Soon */}
      <section>
        <div className="flex items-center gap-2 mb-3">
          <Phone className="w-4 h-4 text-surface-500" />
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200">3CX Phone System</h3>
          <ComingSoonBadge status="coming_soon" />
        </div>
        <div className="rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 p-4 max-w-lg opacity-60 pointer-events-none select-none">
          <div className="space-y-3">
            {[
              { key: 'tcx_server', label: '3CX Server URL', placeholder: 'https://your-3cx.domain.com' },
              { key: 'tcx_extension', label: 'Extension', placeholder: '101' },
              { key: 'tcx_api_key', label: 'API Key', placeholder: 'Paste your 3CX API key' },
            ].map(f => (
              <div key={f.key}>
                <label className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">{f.label}</label>
                <input
                  type="text"
                  placeholder={f.placeholder}
                  disabled
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-100 dark:bg-surface-800 px-3 py-2 text-sm text-surface-400 cursor-not-allowed"
                />
              </div>
            ))}
          </div>
          <p className="mt-3 text-xs text-surface-400">3CX click-to-call and call logging will be available in a future release.</p>
        </div>
      </section>

      {/* 10DLC Guidance */}
      <section>
        <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200 mb-1">A2P 10DLC Registration</h3>
        <p className="text-xs text-surface-400 dark:text-surface-500 mb-3">
          US carriers require A2P 10DLC registration for business SMS. Register through your provider's dashboard.
        </p>
        <div className="rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 p-4 max-w-lg">
          <div className="space-y-2 text-sm text-amber-800 dark:text-amber-200">
            <p className="font-medium">What you need:</p>
            <ul className="list-disc list-inside text-xs space-y-1 text-amber-700 dark:text-amber-300">
              <li>Your business EIN (Employer Identification Number)</li>
              <li>Business name and address</li>
              <li>Use case description (e.g. "Repair status updates")</li>
              <li>Sample messages you'll send</li>
            </ul>
            <div className="flex flex-wrap gap-2 pt-2">
              {[
                { label: 'Twilio', url: 'https://console.twilio.com/us1/develop/sms/regulatory-compliance' },
                { label: 'Telnyx', url: 'https://portal.telnyx.com/#/app/messaging/10dlc' },
                { label: 'Bandwidth', url: 'https://dashboard.bandwidth.com' },
                { label: 'Plivo', url: 'https://console.plivo.com/messaging/10dlc' },
                { label: 'Vonage', url: 'https://dashboard.nexmo.com/sms/brands' },
              ].map(link => (
                <a
                  key={link.label}
                  href={link.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-xs text-primary-600 hover:underline"
                >
                  {link.label} <ExternalLink className="w-3 h-3" />
                </a>
              ))}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
