import * as BlockChyp from '@blockchyp/blockchyp-ts';
import { db } from '../db/connection.js';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { config } from '../config.js';

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

function getConfigValue(key: string): string {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value: string } | undefined;
  return row?.value ?? '';
}

export function getBlockChypConfig(): BlockChypConfig {
  return {
    enabled: getConfigValue('blockchyp_enabled') === 'true',
    apiKey: getConfigValue('blockchyp_api_key'),
    bearerToken: getConfigValue('blockchyp_bearer_token'),
    signingKey: getConfigValue('blockchyp_signing_key'),
    terminalName: getConfigValue('blockchyp_terminal_name') || 'Front Counter',
    testMode: getConfigValue('blockchyp_test_mode') === 'true',
    tcEnabled: getConfigValue('blockchyp_tc_enabled') === 'true',
    tcContent: getConfigValue('blockchyp_tc_content') || 'I authorize this repair shop to perform diagnostic and repair services on my device.',
    tcName: getConfigValue('blockchyp_tc_name') || 'Repair Agreement',
    promptForTip: getConfigValue('blockchyp_prompt_for_tip') === 'true',
    sigRequiredPayment: getConfigValue('blockchyp_sig_required_payment') === 'true',
    sigFormat: (getConfigValue('blockchyp_sig_format') as 'png' | 'jpg') || 'png',
    sigWidth: parseInt(getConfigValue('blockchyp_sig_width') || '400', 10),
    autoCloseTicket: getConfigValue('blockchyp_auto_close_ticket') === 'true',
  };
}

export function isBlockChypEnabled(): boolean {
  const cfg = getBlockChypConfig();
  return cfg.enabled && !!cfg.apiKey && !!cfg.bearerToken && !!cfg.signingKey;
}

// ─── Client management ─────────────────────────────────────────────

let cachedClient: BlockChyp.BlockChypClient | null = null;
let cachedCredHash = '';

function credentialsHash(cfg: BlockChypConfig): string {
  return `${cfg.apiKey}|${cfg.bearerToken}|${cfg.signingKey}|${cfg.testMode}`;
}

export function getClient(): BlockChyp.BlockChypClient {
  const cfg = getBlockChypConfig();
  if (!cfg.apiKey || !cfg.bearerToken || !cfg.signingKey) {
    throw new Error('BlockChyp credentials not configured. Set API Key, Bearer Token, and Signing Key in Settings.');
  }

  const hash = credentialsHash(cfg);
  if (cachedClient && cachedCredHash === hash) {
    return cachedClient;
  }

  cachedClient = BlockChyp.newClient({
    apiKey: cfg.apiKey,
    bearerToken: cfg.bearerToken,
    signingKey: cfg.signingKey,
  });

  if (cfg.testMode) {
    // SDK bug: _resolveTerminalRoute doesn't pass the request to _assembleGatewayUrl,
    // so it always uses gatewayHost (production) even when request.test = true.
    cachedClient.setGatewayHost('https://test.blockchyp.com');

    // Sandbox has no physical terminal, so route resolution returns empty ipAddress
    // causing "Invalid URL" (https://:8443/...). Force cloud relay to skip terminal routing.
    (cachedClient as any).cloudRelay = true;
  }

  cachedCredHash = hash;
  return cachedClient;
}

export function refreshClient(): void {
  cachedClient = null;
  cachedCredHash = '';
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

export async function testConnection(terminalNameOverride?: string): Promise<TestConnectionResult> {
  const cfg = getBlockChypConfig();
  const client = getClient();
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
      firmwareVersion: data.firmwareVersion ?? undefined,
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

export async function capturePreTicketSignature(): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig();
  const client = getClient();

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as BlockChyp.SignatureFormat;
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

export async function captureCheckInSignature(ticketOrderId: string): Promise<CaptureSignatureResult> {
  const cfg = getBlockChypConfig();
  const client = getClient();

  try {
    const request = new BlockChyp.TermsAndConditionsRequest();
    request.terminalName = cfg.terminalName;
    request.test = cfg.testMode;
    request.tcAlias = null;
    request.tcName = cfg.tcName;
    request.tcContent = cfg.tcContent;
    request.sigFormat = cfg.sigFormat as BlockChyp.SignatureFormat;
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
  amount: number,
  ticketOrderId: string,
  tip?: number,
): Promise<ProcessPaymentResult> {
  const cfg = getBlockChypConfig();
  const client = getClient();

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
    request.sigFormat = cfg.sigFormat as BlockChyp.SignatureFormat;
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
      receiptSuggestions: data.receiptSuggestions as Record<string, unknown> | undefined,
    };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Terminal communication failed';
    return { success: false, error: message };
  }
}
