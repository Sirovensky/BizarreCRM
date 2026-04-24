/**
 * SMS Auto-Responder Matcher
 *
 * Matches an inbound message against all active auto-responders in the DB.
 * Returns the first matching responder's response body.
 *
 * Caller is responsible for actually sending the response — this module
 * only evaluates rules and increments counters.
 *
 * Rule evaluation cap: only the first MATCHER_LIMIT (200) active rules are
 * loaded, ordered by id ASC. Rules are evaluated in that order — first match
 * wins. Tenants with more than 200 rules should consolidate them.
 *
 * Rule shapes supported:
 *   { type: 'keyword', match: string, case_sensitive?: boolean }
 *   { type: 'regex',   match: string, case_sensitive?: boolean }
 *
 * Default for both: case-insensitive.
 *
 * Never throws — all errors are caught and logged. Callers receive
 * { matched: false } on any internal failure.
 */
import type { AsyncDb } from '../db/async-db.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('sms-auto-responder-matcher');

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface InboundSmsMessage {
  from: string;
  body: string;
  tenant_slug?: string;
}

export interface MatchResult {
  matched: boolean;
  response?: string;
  responder_id?: number;
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

interface AutoResponderRow {
  id: number;
  rule_json: string;
  response_body: string;
}

interface AutoResponderRule {
  type: 'keyword' | 'regex';
  match: string;
  case_sensitive?: boolean;
}

// ---------------------------------------------------------------------------
// Rule evaluation
// ---------------------------------------------------------------------------

/**
 * Test one rule against the inbound message body.
 * Returns true if the rule matches; false on any parse/runtime error.
 */
function evaluateRule(rule: AutoResponderRule, body: string): boolean {
  const caseSensitive = rule.case_sensitive === true;

  if (rule.type === 'keyword') {
    const needle = caseSensitive ? rule.match : rule.match.toLowerCase();
    const haystack = caseSensitive ? body : body.toLowerCase();
    // Match on word boundaries so "STOP" doesn't trigger on "Stopping"
    // but still catches "STOP" mid-sentence with surrounding whitespace.
    // Use trimmed full-message exact match first (common case), then substring.
    const trimmed = haystack.trim();
    if (trimmed === needle) return true;
    // Substring keyword — space-delimited token match
    const tokens = trimmed.split(/\s+/);
    return tokens.includes(needle);
  }

  if (rule.type === 'regex') {
    // SCAN-1100 [HIGH/ReDoS]: admin-authored regexes are compiled + run
    // synchronously against inbound SMS bodies. A pathological pattern
    // like `(a+)+$` against a long `a…` body pins the Node event loop for
    // seconds/minutes and stalls the whole webhook queue (shared by the
    // entire tenant). Defence in depth:
    //   (1) Reject nested-quantifier shapes (`(…+)+`, `(…*)+`, etc) at
    //       compile time. This is a heuristic — not every dangerous regex
    //       matches, but the most common ReDoS foot-guns do.
    //   (2) Cap body length at 1600 chars (GSM-7 concat ceiling). SMS
    //       gateways truncate at ~1600 anyway; any longer content is
    //       already meaningless for keyword/auto-reply matching.
    try {
      if (/\([^)]*[+*][^)]*\)[+*]/.test(rule.match)) {
        logger.warn('sms auto-responder: rejecting regex with nested quantifiers (ReDoS guard)', {
          match: rule.match,
        });
        return false;
      }
      const flags = caseSensitive ? '' : 'i';
      const re = new RegExp(rule.match, flags);
      const capped = body.length > 1600 ? body.slice(0, 1600) : body;
      return re.test(capped);
    } catch (err) {
      logger.warn('sms auto-responder: invalid regex in rule', {
        match: rule.match,
        error: err instanceof Error ? err.message : String(err),
      });
      return false;
    }
  }

  return false;
}

/**
 * Parse rule_json from a DB row. Returns null on any parse/shape error
 * so a corrupt rule doesn't crash the entire matching pass.
 */
function parseRule(raw: string): AutoResponderRule | null {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return null;
    const obj = parsed as Record<string, unknown>;
    if (obj.type !== 'keyword' && obj.type !== 'regex') return null;
    if (typeof obj.match !== 'string' || !obj.match) return null;
    return {
      type: obj.type,
      match: obj.match,
      ...(typeof obj.case_sensitive === 'boolean' ? { case_sensitive: obj.case_sensitive } : {}),
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Public export
// ---------------------------------------------------------------------------

/**
 * tryAutoRespond — inbound SMS auto-responder matching.
 *
 * SECURITY: this helper MUST be called with a per-tenant `adb` (the
 * request's tenant-bound async DB). The function does NOT filter by
 * tenant_id internally because the per-tenant DB file model isolates
 * tables naturally. Callers that pass the master DB would match rules
 * across all tenants — do NOT do this.
 *
 * @param adb   - AsyncDb handle (req.asyncDb in route context)
 * @param msg   - Inbound message with `from` and `body` fields
 * @returns     MatchResult — matched=true with response text when a rule fires
 */
export async function tryAutoRespond(
  adb: AsyncDb,
  msg: InboundSmsMessage,
): Promise<MatchResult> {
  try {
    const MATCHER_LIMIT = 200;
    const rows = await adb.all<AutoResponderRow>(
      `SELECT id, rule_json, response_body
         FROM sms_auto_responders
        WHERE is_active = 1
        ORDER BY id ASC
        LIMIT ?`,
      MATCHER_LIMIT,
    );

    if (rows.length === 0) return { matched: false };

    const inboundBody = (msg.body || '').trim();

    for (const row of rows) {
      const rule = parseRule(row.rule_json);
      if (!rule) {
        logger.warn('sms auto-responder: skipping row with unparseable rule_json', {
          responder_id: row.id,
        });
        continue;
      }

      if (!evaluateRule(rule, inboundBody)) continue;

      // Match found — increment stats (non-blocking; failure is non-fatal)
      try {
        await adb.run(
          `UPDATE sms_auto_responders
              SET match_count      = match_count + 1,
                  last_matched_at  = datetime('now'),
                  updated_at       = datetime('now')
            WHERE id = ?`,
          row.id,
        );
      } catch (updateErr) {
        logger.warn('sms auto-responder: failed to increment match_count', {
          responder_id: row.id,
          error: updateErr instanceof Error ? updateErr.message : String(updateErr),
        });
      }

      return {
        matched: true,
        response: row.response_body,
        responder_id: row.id,
      };
    }

    return { matched: false };
  } catch (err) {
    // Never throw — callers depend on this being safe to fire-and-check
    logger.error('sms auto-responder matcher: unexpected error', {
      error: err instanceof Error ? err.message : String(err),
      from: msg.from ? msg.from.slice(-4) : 'unknown',
    });
    return { matched: false };
  }
}
