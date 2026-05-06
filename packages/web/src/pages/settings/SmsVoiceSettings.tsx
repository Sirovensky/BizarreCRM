import { useState, useEffect, useRef } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Check, Copy, Loader2, AlertCircle, ExternalLink, Phone, MessageSquare, Mic, Bot } from 'lucide-react';
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

type SaveScope = 'provider' | 'voice' | 'autoReply' | 'tcx';

type VoiceConfigKey =
  | 'voice_auto_record'
  | 'voice_auto_transcribe'
  | 'voice_announce_recording'
  | 'voice_forward_number'
  | 'voice_inbound_action';

export function SmsVoiceSettings() {
  const queryClient = useQueryClient();
  const [selectedProvider, setSelectedProvider] = useState<string>('console');
  const [credentials, setCredentials] = useState<Record<string, string>>({});
  const [testing, setTesting] = useState(false);
  const [savingScope, setSavingScope] = useState<SaveScope | null>(null);
  const [testResult, setTestResult] = useState<{ ok: boolean; message: string } | null>(null);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  // Voice settings controlled state
  const [voiceAutoRecord, setVoiceAutoRecord] = useState(false);
  const [voiceAutoTranscribe, setVoiceAutoTranscribe] = useState(false);
  const [voiceAnnounceRecording, setVoiceAnnounceRecording] = useState(false);
  const [voiceForwardNumber, setVoiceForwardNumber] = useState('');
  const [voiceInboundAction, setVoiceInboundAction] = useState('ring');
  const [voiceDirty, setVoiceDirty] = useState(false);
  const voiceDirtyRef = useRef(false);

  // WEB-W1-029: auto-reply controlled state
  const [autoReplyEnabled, setAutoReplyEnabled] = useState(false);
  const [autoReplyMessage, setAutoReplyMessage] = useState('');
  const [tcxConfig, setTcxConfig] = useState({
    tcx_host: '',
    tcx_extension: '',
    tcx_password: '',
  });

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
    // Populate voice settings state unless the user has local unsaved edits.
    if (!voiceDirtyRef.current) {
      setVoiceAutoRecord(cfg.voice_auto_record === '1');
      setVoiceAutoTranscribe(cfg.voice_auto_transcribe === '1');
      setVoiceAnnounceRecording(cfg.voice_announce_recording === '1');
      setVoiceForwardNumber(cfg.voice_forward_number || '');
      setVoiceInboundAction(cfg.voice_inbound_action || 'ring');
      voiceDirtyRef.current = false;
      setVoiceDirty(false);
    }

    // WEB-W1-029: populate auto-reply state
    setAutoReplyEnabled(cfg.auto_reply_enabled === '1');
    setAutoReplyMessage(cfg.auto_reply_message || '');
    setTcxConfig({
      tcx_host: cfg.tcx_host || '',
      tcx_extension: cfg.tcx_extension || '',
      tcx_password: cfg.tcx_password || '',
    });
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

  function markVoiceDirty() {
    voiceDirtyRef.current = true;
    setVoiceDirty(true);
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

  function buildProviderEntries(): Record<string, string> {
    const entries: Record<string, string> = { sms_provider_type: selectedProvider };
    for (const [field, value] of Object.entries(credentials)) {
      entries[`sms_${selectedProvider}_${field}`] = value;
    }
    return entries;
  }

  function buildVoiceEntries(): Record<VoiceConfigKey, string> {
    return {
      voice_auto_record: voiceAutoRecord ? '1' : '0',
      voice_auto_transcribe: voiceAutoTranscribe ? '1' : '0',
      voice_announce_recording: voiceAnnounceRecording ? '1' : '0',
      voice_forward_number: voiceForwardNumber,
      voice_inbound_action: voiceInboundAction,
    };
  }

  function buildAutoReplyEntries(): Record<string, string> {
    return {
      auto_reply_enabled: autoReplyEnabled ? '1' : '0',
      auto_reply_message: autoReplyMessage,
    };
  }

  function buildTcxEntries(): Record<string, string> {
    const entries: Record<string, string> = {
      tcx_host: tcxConfig.tcx_host,
      tcx_extension: tcxConfig.tcx_extension,
    };
    if (tcxConfig.tcx_password) entries['tcx_password'] = tcxConfig.tcx_password;
    return entries;
  }

  async function saveConfig(scope: SaveScope, entries: Record<string, string>, successMessage: string, reloadSms = false) {
    setSavingScope(scope);
    try {
      await settingsApi.updateConfig(entries);
      if (reloadSms) {
        await axios.post('/settings/sms/reload');
      }
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      if (scope === 'voice') {
        voiceDirtyRef.current = false;
        setVoiceDirty(false);
      }
      toast.success(successMessage);
    } catch (err: unknown) {
      toast.error((err as any)?.response?.data?.message || 'Failed to save');
    } finally {
      setSavingScope(null);
    }
  }

  function handleSaveProvider() {
    saveConfig('provider', buildProviderEntries(), 'SMS provider saved', true);
  }

  function handleSaveVoice() {
    saveConfig('voice', buildVoiceEntries(), 'Voice settings saved');
  }

  function handleSaveAutoReply() {
    saveConfig('autoReply', buildAutoReplyEntries(), 'Auto-reply settings saved');
  }

  function handleSaveTcx() {
    saveConfig('tcx', buildTcxEntries(), '3CX settings saved');
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
                type="button"
                onClick={handleTestConnection}
                disabled={testing}
                className="btn btn-secondary btn-sm border border-surface-300 dark:border-surface-600"
              >
                {testing ? <Loader2 className="w-4 h-4 animate-spin" /> : 'Test Connection'}
              </button>
              <button
                type="button"
                onClick={handleSaveProvider}
                disabled={savingScope !== null}
                className="btn btn-primary btn-sm"
              >
                {savingScope === 'provider' ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Saving...
                  </>
                ) : 'Save Provider'}
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
                className="btn-icon btn-xs text-surface-400 hover:text-primary-600"
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
              checked={voiceAutoRecord}
              onChange={(e) => {
                setVoiceAutoRecord(e.target.checked);
                markVoiceDirty();
              }}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Automatically record all calls</span>
          </label>
          <label className="flex items-center gap-3">
            <input
              id="voice_auto_transcribe"
              type="checkbox"
              checked={voiceAutoTranscribe}
              onChange={(e) => {
                setVoiceAutoTranscribe(e.target.checked);
                markVoiceDirty();
              }}
              className="rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-200">Automatically transcribe recordings</span>
          </label>
          <label className="flex items-center gap-3">
            <input
              id="voice_announce_recording"
              type="checkbox"
              checked={voiceAnnounceRecording}
              onChange={(e) => {
                setVoiceAnnounceRecording(e.target.checked);
                markVoiceDirty();
              }}
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
              value={voiceInboundAction}
              onChange={(e) => {
                setVoiceInboundAction(e.target.value);
                markVoiceDirty();
              }}
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
              value={voiceForwardNumber}
              onChange={(e) => {
                setVoiceForwardNumber(e.target.value);
                markVoiceDirty();
              }}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
            />
          </div>
          <div className="flex items-center gap-3 pt-2">
            <button
              type="button"
              onClick={handleSaveVoice}
              disabled={savingScope !== null || !voiceDirty}
              className="btn btn-primary btn-sm"
            >
              {savingScope === 'voice' ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Saving...
                </>
              ) : 'Save Voice'}
            </button>
            <span className={`text-xs ${voiceDirty ? 'text-amber-600 dark:text-amber-400' : 'text-surface-400 dark:text-surface-500'}`}>
              {voiceDirty ? 'Unsaved voice changes' : 'Voice settings saved'}
            </span>
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
            type="button"
            onClick={handleSaveAutoReply}
            disabled={savingScope !== null}
            className="btn btn-primary btn-sm"
          >
            {savingScope === 'autoReply' ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                Saving...
              </>
            ) : 'Save Auto-Reply'}
          </button>
        </div>
      </section>

      {/* 3CX Integration */}
      <section>
        <div className="flex items-center gap-2 mb-3">
          <Phone className="w-4 h-4 text-surface-500" />
          <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-200">3CX Phone System</h3>
        </div>
        <div className="rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 p-4 max-w-lg">
          <div className="space-y-3">
            {[
              { key: 'tcx_host', label: '3CX Server URL', placeholder: 'https://your-3cx.domain.com', type: 'text' },
              { key: 'tcx_extension', label: 'Extension', placeholder: '101' },
              { key: 'tcx_password', label: 'API Key / Password', placeholder: 'Paste your 3CX API key', type: 'password' },
            ].map(f => (
              <div key={f.key}>
                <label className="block text-sm font-medium text-surface-600 dark:text-surface-300 mb-1">{f.label}</label>
                <input
                  type={f.type || 'text'}
                  placeholder={f.placeholder}
                  value={tcxConfig[f.key as keyof typeof tcxConfig]}
                  onChange={(e) => setTcxConfig((prev) => ({ ...prev, [f.key]: e.target.value }))}
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100"
                />
              </div>
            ))}
          </div>
          <p className="mt-3 text-xs text-surface-400">When all 3CX fields are saved, CRM click-to-call uses 3CX Call Control. Leave them blank to use the selected SMS/voice provider.</p>
          <button
            type="button"
            onClick={handleSaveTcx}
            disabled={savingScope !== null}
            className="btn btn-primary btn-sm mt-4"
          >
            {savingScope === 'tcx' ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                Saving...
              </>
            ) : 'Save 3CX'}
          </button>
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
