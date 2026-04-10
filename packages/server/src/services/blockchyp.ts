import * as BlockChyp from '@blockchyp/blockchyp-ts';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';
import { getConfigValue } from '../utils/configEncryption.js';

// ─── Config helpers ────────────────────────────────────────────────

interface BlockChypConfig {
  enabled: boolean;
  apiKey: string;
  bearerToken: string;
  signingKey: string;
  terminalName: string;
  testMode: boolean;
  tcEnabled: boolean;
  tcContent: string;
  tcName: string;
  promptForTip: boolean;
  sigRequiredPayment: boolean;
  sigFormat: 'png' | 'jpg';
  sigWidth: number;
  autoCloseTicket: boolean;
}

export function getBlockChypConfig(db: any): BlockChypConfig {
  return {
    enabled: getConfigValue(db, 'blockchyp_enabled') === 'true',
    apiKey: getConfigValue(db, 'blockchyp_api_key') || '',
    bearerToken: getConfigValue(db, 'blockchyp_bearer_token') || '',
    signingKey: getConfigValue(db, 'blockchyp_signing_key') || '',
    terminalName: getConfigValue(db, 'blockchyp_terminal_name') || 'Front Counter',
    testMode: getConfigValue(db, 'blockchyp_test_mode') === 'true',
    tcEnabled: getConfigValue(db, 'blockchyp_tc_enabled') === 'true',
    tcContent: getConfigValue(db, 'blockchyp_tc_content') || 'I authorize this repair shop to perform diagnostic and repair services on my device.',
    tcName: getConfigValue(db, 'blockchyp_tc_name') || 'Repair Agreement',
    promptForTip: getConfigValue(db, 'blockchyp_prompt_for_tip') === 'true',
    sigRequiredPayment: getConfigValue(db, 'blockchyp_sig_required_payment') === 'true',
    sigFormat: (getConfigValue(db, 'blockchyp_sig_format') as 'png' | 'jpg') || 'png',
    sigWidth: parseInt(getConfigValue(db, 'blockchyp_sig_width') || '400', 10),
    autoCloseTicket: getConfigValue(db, 'blockchyp_auto_close_ticket') === 'true',
  };
}

export function isBlockChypEnabled(db: any): boolean {
  const cfg = getBlockChypConfig(db);
  return cfg.enabled && !!cfg.apiKey && !!cfg.bearerToken && !!cfg.signingKey;
}

// ─── Client management ─────────────────────────────────────────────

const CLIENT_TTL_MS = 5 * 60 * 1000; // 5 minutes

type BlockChypClientInstance = ReturnType<typeof BlockChyp.newClient>;
const clientCache = new Map<string, { client: BlockChypClientInstance; createdAt: number }>();

function credentialsHash(cfg: BlockChypConfig): string {
  return `${cfg.apiKey}|${cfg.bearerToken}|${cfg.signingKey}|${cfg.testMode}`;
}

export function getClient(db: any): BlockChypClientInstance {
  const cfg = getBlockChypConfig(db);
  if (!cfg.apiKey || !cfg.bearerToken || !cfg.signingKey) {
    throw new Error('BlockChyp credentials not configured. Set API Key, Bearer Token, and Signing Key in Settings.');
  }

  const hash = credentialsHash(cfg);
  const now = Date.now();
  const cached = clientCache.get(hash);
  if (cached && (now - cached.createdAt) < CLIENT_TTL_MS) {
    return cached.client;
  }

  const client = BlockChyp.newClient({
    apiKey: cfg.apiKey,
    bearerToken: cfg.bearerToken,
    signingKey: cfg.signingKey,
  });

  if (cfg.testMode) {
    // SDK bug: _resolveTerminalRoute doesn't pass the request to _assembleGatewayUrl,
    // so it always uses gatewayHost (production) even when request.test = true.
    client.setGatewayHost('https://test.blockchyp.com');

    // Sandbox has no physical terminal, so route resolution returns empty ipAddress
    // causing "Invalid URL" (https://:8443/...). Force cloud relay to skip terminal routing.
    // WARNING: This uses an undocumented SDK internal. If a BlockChyp SDK update breaks
    // test-mode payments, check whether this property was renamed or removed.
    if ('cloudRelay' in client || typeof (client as any).cloudRelay !== 'undefined') {
      (client as any).cloudRelay = true;
    } else {
      console.warn('[BlockChyp] SDK may have changed — cloudRelay property not found. Test mode terminal routing may fail.');
      (client as any).cloudRelay = true; // Try anyway
    }
  }

  clientCache.set(hash, { client, createdAt: now });
  return client;
}

export function refreshClient(): void {
  clientCache.clear();
}

// ─── Signature file saving ─────────────────────────────────────────

function saveSignatureFile(sigFileHex: string, format: string): string {
  const buffer = Buffer.from(sigFileHex, 'hex');
  const ext = format === 'jpg' ? '.jpg' : '.png';
  const filename = `sig-${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  const filePath = path.join(config.uploadsPath, filename);
  fs.writeFileSync(filePath, buffer);
  return filename;
}

// ─── Public API methods ────────────────────────────────────────────

export interface TestConnectionResult {
  success: boolean;
  terminalName: string;
  firmwareVersion?: string;
  error?: string;
}

export async function testConnection(db: any, terminalNameOverride?: string): Promise<TestConnectionResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);
  const terminalName = terminalNameOverride || cfg.terminalName;

  try {
    const request = new BlockChyp.PingRequest();
    request.terminalName = terminalName;
    request.test = cfg.testMode;

    const response = await client.ping(request);
    const data = response.data;

    return {
      success: !!data.success,
      terminalName,
      firmwareVersion: (data as any).firmwareVersion ?? undefined,
      error: data.success ? undefined : (data.error ?? 'Unknown error'),
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Connection failed';
    return { success: false, terminalName, error: message };
  }
}

export interface CaptureSignatureResult {
  success: boolean;
  signatureFile?: string;
  transactionId?: string;
  error?: string;
}

export async function capturePreTicketSignature(db: any): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfg.sigWidth;
    request.sigRequired = true;
    request.transactionRef = `checkin-pre-${Date.now()}`;

    const response = await client.termsAndConditions(request);
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Customer declined or terminal error' };
    }

    let signatureFile: string | undefined;
    if (data.sigFile) {
      signatureFile = saveSignatureFile(data.sigFile, cfg.sigFormat);
    }

    return {
      success: true,
      signatureFile,
      transactionId: data.transactionId ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

export async function captureCheckInSignature(db: any, ticketOrderId: string): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfg.sigWidth;
    request.sigRequired = true;
    request.transactionRef = `checkin-${ticketOrderId}`;

    const response = await client.termsAndConditions(request);
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Customer declined or terminal error' };
    }

    let signatureFile: string | undefined;
    if (data.sigFile) {
      signatureFile = saveSignatureFile(data.sigFile, cfg.sigFormat);
    }

    return {
      success: true,
      signatureFile,
      transactionId: data.transactionId ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

export interface ProcessPaymentResult {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  amount?: string;
  cardType?: string;
  last4?: string;
  signatureFile?: string;
  receiptSuggestions?: Record<string, unknown>;
  error?: string;
  responseDescription?: string;
}

export async function processPayment(
  db: any,
  amount: number,
  ticketOrderId: string,
  tip?: number,
): Promise<ProcessPaymentResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.AuthorizationRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.amount = amount.toFixed(2);
    request.transactionRef = `payment-${ticketOrderId}-${Date.now()}`;
    request.description = `Ticket ${ticketOrderId}`;

    if (tip && tip > 0) {
      request.tipAmount = tip.toFixed(2);
    }
    if (cfg.promptForTip) {
      request.promptForTip = true;
    }
    if (!cfg.sigRequiredPayment) {
      request.disableSignature = true;
    }
    request.sigFormat = cfg.sigFormat as "" | "png" | "jpg" | "gif";
    request.sigWidth = cfg.sigWidth;

    const response = await client.charge(request);
    const data = response.data;

    if (!data.approved) {
      return {
        success: false,
        error: data.responseDescription ?? 'Payment declined',
        responseDescription: data.responseDescription ?? undefined,
      };
    }

    let signatureFile: string | undefined;
    if (data.sigFile) {
      signatureFile = saveSignatureFile(data.sigFile, cfg.sigFormat);
    }

    return {
      success: true,
      transactionId: data.transactionId ?? undefined,
      authCode: data.authCode ?? undefined,
      amount: data.authorizedAmount ?? undefined,
      cardType: data.paymentType ?? undefined,
      last4: data.maskedPan?.slice(-4) ?? undefined,
      signatureFile,
      receiptSuggestions: data.receiptSuggestions as unknown as Record<string, unknown> | undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

// ─── Membership: Card Enrollment (tokenization) ───────────────────

export interface EnrollResult {
  success: boolean;
  token?: string;
  maskedPan?: string;
  cardType?: string;
  error?: string;
}

/**
 * Enroll a card on the terminal for recurring billing.
 * Presents the card capture screen, tokenizes the card, returns a token for future charges.
 */
export async function enrollCard(db: any): Promise<EnrollResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.EnrollRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.transactionRef = `enroll-${Date.now()}`;

    const response = await client.enroll(request);
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Card enrollment failed' };
    }

    return {
      success: true,
      token: data.token ?? undefined,
      maskedPan: data.maskedPan ?? undefined,
      cardType: data.paymentType ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}

// ─── Membership: Token-based charge (recurring billing) ───────────

export interface TokenChargeResult {
  success: boolean;
  transactionId?: string;
  authCode?: string;
  amount?: string;
  error?: string;
}

/**
 * Charge a previously tokenized card (for monthly membership renewal).
 * No terminal interaction — runs server-side via BlockChyp gateway.
 */
export async function chargeToken(db: any, token: string, amount: string, description: string): Promise<TokenChargeResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.AuthorizationRequest();
    request.token = token;
    request.amount = amount;
    request.test = cfg.testMode;
    request.description = description;
    request.transactionRef = `membership-${Date.now()}`;

    const response = await client.charge(request);
    const data = response.data;

    if (!data.approved) {
      return { success: false, error: data.responseDescription ?? 'Payment declined' };
    }

    return {
      success: true,
      transactionId: data.transactionId ?? undefined,
      authCode: data.authCode ?? undefined,
      amount: data.authorizedAmount ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Payment processing failed';
    return { success: false, error: message };
  }
}

// ─── Membership: Payment Link (for remote signup) ─────────────────

export interface PaymentLinkResult {
  success: boolean;
  linkUrl?: string;
  linkCode?: string;
  error?: string;
}

/**
 * Create a BlockChyp payment link for remote membership signup.
 * Customer receives a link (via SMS/email/QR code) to enter card details.
 */
export async function createPaymentLink(db: any, amount: string, description: string, callbackUrl?: string): Promise<PaymentLinkResult> {
  const cfg = getBlockChypConfig(db);
  const client = getClient(db);

  try {
    const request = new BlockChyp.PaymentLinkRequest();
    request.amount = amount;
    request.description = description;
    request.test = cfg.testMode;
    request.autoSend = false; // We send the link ourselves via SMS
    request.transactionRef = `membership-link-${Date.now()}`;
    if (callbackUrl) {
      request.callbackUrl = callbackUrl;
    }
    request.enroll = true; // Tokenize the card for recurring

    const response = await client.sendPaymentLink(request);
    const data = response.data;

    if (!data.success) {
      return { success: false, error: data.error ?? data.responseDescription ?? 'Failed to create payment link' };
    }

    return {
      success: true,
      linkUrl: data.url ?? undefined,
      linkCode: data.linkCode ?? undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Failed to create payment link';
    return { success: false, error: message };
  }
}
