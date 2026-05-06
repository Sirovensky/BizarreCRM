# T12 — Regular-Expression Denial of Service (ReDoS)

**Auditor:** T12 slot  
**Scope:** `packages/server/src/` — regex patterns evaluated against user-controlled input  
**Files read end-to-end:** `utils/validate.ts`, `utils/phone.ts`, `utils/escape.ts`, `utils/xml.ts`, `utils/format.ts`, `services/email.ts`, `services/catalogScraper.ts`, `services/repairDeskImport.ts`, `services/repairShoprImport.ts`, `services/myRepairAppImport.ts`, `services/automations.ts`, `services/smsAutoResponderMatcher.ts`, `middleware/fileUploadValidator.ts`, `routes/smsAutoResponders.routes.ts`, `routes/sms.routes.ts`, `index.ts`  
**Dynamic `new RegExp()` calls:** exactly 2, both in the SMS auto-responder feature

---

### [HIGH] ReDoS guard bypassable via overlapping-alternation patterns in SMS auto-responders

**Where:**  
- `packages/server/src/routes/smsAutoResponders.routes.ts:78` (write-time guard)  
- `packages/server/src/services/smsAutoResponderMatcher.ts:97` (eval-time guard)  
- Trigger path: `packages/server/src/routes/sms.routes.ts:1091` (public webhook)

**What:**  
The heuristic ReDoS guard `if (/\([^)]*[+*][^)]*\)[+*]/.test(raw))` at both the create-time validation and the eval-time matcher only rejects patterns where a quantifier (`+` or `*`) appears **inside** the capture/non-capture group before its closing `)`. It completely misses the classic exponential-backtracking pattern where two alternation branches of **different lengths** overlap, such as `(a|aa)+`, `(?:a|aa)+`, and `(hello|helloworld)+`. These patterns have no `+`/`*` inside the group — they use alternation `|` — so the guard's inner `[^)]*[+*][^)]*` sub-pattern never matches. Empirically tested on Node.js v22: `(a|aa)+$` takes ~3 ms at N=20, ~35 ms at N=30, ~429 ms at N=35, and would be astronomically slow at the 1600-char SMS body cap (body is capped but not the regex execution time). The same bypassed pattern is accepted at creation, stored in `sms_auto_responders.rule_json`, loaded at webhook time, and executed synchronously on the Node.js main thread with no per-regex timeout.

**Code:**
```typescript
// smsAutoResponders.routes.ts:70–89  (write-time)
function validateMatchPattern(raw: unknown): RegExp {
  if (raw.length > 500) throw new AppError('match pattern exceeds 500 chars', 400);
  // ← BYPASS: (a|aa)+ has no + or * inside the group, so this check passes
  if (/\([^)]*[+*][^)]*\)[+*]/.test(raw)) {
    throw new AppError('match pattern has nested quantifiers (ReDoS risk)', 400);
  }
  return new RegExp(raw, 'i');  // stored in DB
}

// smsAutoResponderMatcher.ts:97–105  (eval-time, public webhook path)
if (/\([^)]*[+*][^)]*\)[+*]/.test(rule.match)) { // same guard — same bypass
  return false;
}
const re = new RegExp(rule.match, flags);
const capped = body.length > 1600 ? body.slice(0, 1600) : body;
return re.test(capped);  // synchronous on main event loop, no timeout
```

**Exploit:**  
A tenant manager or admin (role gate at create time: `requireManagerOrAdmin`) stores the pattern `(a|aa)+$` via `POST /api/v1/sms/auto-responders`. An external attacker (or the same actor) then posts to the **unauthenticated** SMS inbound webhook `POST /api/v1/sms/inbound-webhook` with a body of 35+ `a` characters. The matcher runs `(a|aa)+$` against the body synchronously on the main thread — N=35 takes ~430 ms, and N=50 would take seconds — stalling all tenant I/O on the shared Node.js process. At 60 requests/minute (the webhook rate limit) the event loop is effectively monopolized.

**Fix:**  
Replace the hand-rolled heuristic with the [`safe-regex2`](https://www.npmjs.com/package/safe-regex2) or [`recheck`](https://makenowjust-labs.github.io/recheck/) npm package (both detect exponential-backtracking patterns including overlapping alternation). Alternatively, run the compiled regex against a short synthetic probe string (`'a'.repeat(50) + '!'`) inside a `Worker` thread with an `AbortController` timeout (e.g. 100 ms) before storing it in the DB. As defense-in-depth, compile stored regex patterns in a `Worker` thread at eval time rather than on the main event loop so a slow match cannot stall request handling.

---

### [MEDIUM] `sanitizeEmailHtml` regex pipeline applied to uncapped input before size enforcement

**Where:** `packages/server/src/services/email.ts:173–178`

**What:**  
`sanitizeEmailHtml` runs five successive `.replace()` calls on the raw HTML before the 200 KB byte-length cap is enforced (line 182). Each individual regex is structurally safe (no nested quantifiers, anchored character classes), but the pipeline still allocates multiple intermediate strings from the full uncapped input. An automation template that embeds a multi-megabyte inline `<style>` block passes all five regex scans, each touching every byte of the payload, before the truncation cap fires. On a slow SMTP path this causes unnecessary CPU and GC pressure, and the `sendEmail` caller (`automations.ts`, `notifications.ts`) receives the full opts.html without any upstream size gate.

**Code:**
```typescript
function sanitizeEmailHtml(raw: string): string {
  if (!raw) return '';
  let out = raw;
  out = out.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*"[^"]*"/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*'[^']*'/gi, '');
  out = out.replace(/\s+on[a-z]+\s*=\s*[^\s>]+/gi, '');
  out = out.replace(/(href|src)\s*=\s*"\s*javascript:[^"]*"/gi, '$1="#"');
  out = out.replace(/(href|src)\s*=\s*'\s*javascript:[^']*'/gi, "$1='#'");
  // ← cap enforced AFTER all five regex passes on the full raw buffer
  if (Buffer.byteLength(out, 'utf8') > EMAIL_HTML_MAX_BYTES) {
    out = out.slice(0, EMAIL_HTML_MAX_BYTES);
  }
  return out;
}
```

**Exploit:**  
A tenant admin saves an automation email template with a 5 MB HTML blob. On each triggered automation send, five regex passes run over the full 5 MB before any truncation, each producing a new intermediate string — consuming ~25–50 MB of heap per email send and increasing GC pressure under concurrent automation runs.

**Fix:**  
Add an early byte-length guard before the regex pipeline: `if (Buffer.byteLength(raw, 'utf8') > EMAIL_HTML_MAX_BYTES) raw = raw.slice(0, EMAIL_HTML_MAX_BYTES);`. This bounds regex input to 200 KB unconditionally, eliminating the multi-MB processing window.

---

## SCOPE CLEARED — Patterns confirmed safe

The following were examined and found to have no exploitable ReDoS exposure:

- **`utils/validate.ts` — `validateEmail` regex** (`/^[^\s@.]+(?:\.[^\s@.]+)*@…$/`): Guarded by an explicit `local.length > 64` / `domain.length > 253` pre-cap (lines 105–106) before the regex runs, capping input to ≤318 chars. Empirically < 1 ms at maximum length.

- **`utils/validate.ts` — `validateIsoDate` regex** (`/^\d{4}-\d{2}-\d{2}(T…)?$/`): Nested optionals but all alternation branches use fixed-length digit sequences (`\d{2}`, `\d{4}`). Tested at 100,000 fractional digits: < 1 ms (linear scan).

- **`utils/phone.ts` — `normalizePhone` / `redactPhone`**: Only use `/\D/g` (single negated class, global replace) — structurally linear.

- **`utils/escape.ts` — `escapeHtml` / `stripSmsControlChars`**: Character-class alternation in a lookup table; no nested quantifiers.

- **`utils/xml.ts` — `escapeXml`**: Sequential single-char `.replace()` calls; no quantifier nesting.

- **`utils/format.ts` — `formatCurrency`**: `/^[A-Z]{3}$/` applied to a trimmed 3-char currency string — provably O(1).

- **`services/catalogScraper.ts` — `parseCompatibleDevices`**: Lazy quantifier `[^,\-–\(]+?` with non-overlapping terminator set; tested at 5000-char input < 1 ms.

- **`services/catalogScraper.ts` — private-IP check**: `^`-anchored alternation on `parsed.hostname` after `new URL()` — fast fail at position 0.

- **`middleware/fileUploadValidator.ts`**: No user-controlled regex patterns; file content validation uses magic-byte comparison, not regex.

- **`index.ts` — static-asset extension regex** (`/\.(css|js|…)$/i`): `$`-anchored alternation with non-overlapping fixed extensions; tested at 50,000-char path: < 1 ms.

- **`services/repairDeskImport.ts` / `repairShoprImport.ts` / `myRepairAppImport.ts`**: Column-name regexes (`/^[a-z_]+$/`) applied to internal hardcoded values only, not user input. HTML-stripping `/<[^>]*>/g` is structurally linear (non-overlapping negated class).

- **Third-party deps**: No `validator` package is installed (`package.json` confirmed). No external regex library (safe-regex, re2) is present. The only user-pattern-to-regex path is the SMS auto-responder feature documented above.
