/**
 * SMS Provider — backward-compatible re-export shim.
 *
 * The full provider implementation is now in packages/server/src/providers/sms/.
 * This file re-exports everything so existing imports continue to work.
 */

export {
  // Types
  type SmsProvider,
  type SmsProviderResult,
  type MmsMedia,
  type InboundMessage,
  type DeliveryStatus,
  type CallOptions,
  type VoiceCallResult,
  type CallEvent,
  type ProviderType,
  type ProviderInfo,
  PROVIDER_REGISTRY,

  // Functions
  initSmsProvider,
  reloadSmsProvider,
  createTestProvider,
  getSmsProvider,
  setSmsProvider,
  sendSms,
  sendSmsTenant,
  getProviderForDb,
  getVoiceConfig,
  getProviderRegistry,
  isProviderRealOrSimulated,
  IncompleteSmsCredentialsError,
} from '../providers/sms/index.js';
