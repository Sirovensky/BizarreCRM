import { WebSocketServer, WebSocket } from 'ws';
import { JWT_VERIFY_OPTIONS } from '../middleware/auth.js';
import { verifyJwtWithRotation } from '../utils/jwtSecrets.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('ws');

// SEC (WS2 rerun §24): Fields in a broadcast ticket payload that must NEVER
// reach a non-finance socket. Anything else in the payload is considered
// non-sensitive for realtime UI updates. Derived from getFullTicketAsync /
// getInvoiceDetail shapes in routes/tickets.routes.ts + routes/invoices.routes.ts.
//
// The ticket object itself ("safe") carries ids, status, totals, labels, and
// devices. The customer sub-object carries email/phone/address — which non
// finance users don't need on a realtime tick — and the payments array carries
// transaction_id, method_detail, and notes which are effectively financial
// PII. We scrub both before shipping the message.
const FINANCE_ROLES: ReadonlySet<string> = new Set(['admin', 'manager', 'accountant']);

const SENSITIVE_CUSTOMER_FIELDS = [
  'email',
  'phone',
  'mobile',
  'address',
  'city',
  'state',
  'zip',
  'postal_code',
  'dob',
  'tax_id',
] as const;

const SENSITIVE_PAYMENT_FIELDS = [
  'transaction_id',
  'method_detail',
  'card_last_four',
  'card_brand',
  'auth_code',
  'notes',
] as const;

/**
 * Return a new object with sensitive customer/payment fields removed. The
 * original `payload` is never mutated. We check for the existence of `customer`
 * or `payments` on the top-level payload and rebuild them. Everything else
 * passes through.
 */
function scrubSensitive(payload: unknown): unknown {
  if (!payload || typeof payload !== 'object') return payload;
  // Never mutate arrays — recurse into entries instead.
  if (Array.isArray(payload)) {
    return payload.map((entry) => scrubSensitive(entry));
  }

  const p = payload as Record<string, unknown>;
  const needsScrub =
    (p.customer && typeof p.customer === 'object') ||
    Array.isArray(p.payments) ||
    typeof p.transaction_id === 'string' ||
    typeof p.method_detail === 'string';
  if (!needsScrub) return payload;

  const out: Record<string, unknown> = { ...p };

  // Top-level payment fields (e.g. direct payment-received broadcasts).
  for (const f of SENSITIVE_PAYMENT_FIELDS) {
    if (f in out) delete out[f];
  }

  if (p.customer && typeof p.customer === 'object' && !Array.isArray(p.customer)) {
    const customer = p.customer as Record<string, unknown>;
    const scrubbedCustomer: Record<string, unknown> = { ...customer };
    for (const f of SENSITIVE_CUSTOMER_FIELDS) {
      if (f in scrubbedCustomer) delete scrubbedCustomer[f];
    }
    out.customer = scrubbedCustomer;
  }

  if (Array.isArray(p.payments)) {
    out.payments = p.payments.map((pay) => {
      if (!pay || typeof pay !== 'object') return pay;
      const payObj = pay as Record<string, unknown>;
      const scrubbedPay: Record<string, unknown> = { ...payObj };
      for (const f of SENSITIVE_PAYMENT_FIELDS) {
        if (f in scrubbedPay) delete scrubbedPay[f];
      }
      return scrubbedPay;
    });
  }

  return out;
}

// SEC (WS3): Cap inbound messages at 60/min per socket. Anything above that
// is treated as abuse and the connection is closed. Kept in memory per
// socket — no DB, no cross-process sync required because we only run one
// websocket server instance.
const MAX_MESSAGES_PER_WINDOW = 60;
const RATE_WINDOW_MS = 60_000;

// SEC (WS3): Cap raw inbound payloads to avoid obvious DoS.
const MAX_INBOUND_BYTES = 16 * 1024;

interface AuthenticatedSocket extends WebSocket {
  userId?: number;
  tenantSlug?: string | null;
  // SEC (WS2 rerun §24): remembered so we can decide whether to strip sensitive
  // fields before broadcasting. Defaults to 'staff' (strip) if absent.
  role?: string;
  // SEC (WS1 rerun §24): the Origin header captured at connection time, so
  // we can validate it against the tenant's store_config.allowed_origins
  // allowlist AFTER we know which tenant this socket belongs to.
  origin?: string | null;
  isAlive?: boolean;
  // SEC (WS3): Sliding-window counter for rate limiting.
  msgWindowStart?: number;
  msgWindowCount?: number;
  // SEC-H86: Tenant cap map key stored on socket so the close handler can
  // decrement the correct bucket without re-deriving the key.
  _tenantCapKey?: string;
}

// SEC-H86: Per-IP and per-tenant concurrent WebSocket connection caps.
// Prevents a single client or compromised tenant from exhausting server FDs/memory.
const MAX_WS_CONNECTIONS_PER_IP = 20;
const MAX_WS_CONNECTIONS_PER_TENANT = 200;

// In-memory counters keyed by IP and tenantSlug respectively.
// Decremented on socket close; entry deleted when count reaches 0.
const wsConnsByIp = new Map<string, number>();
const wsConnsByTenant = new Map<string, number>();

// SEC-H86: Periodic sweeper removes any zero-count entries that survived a
// race between increment and a very-early-close (edge case, belt-and-suspenders).
setInterval(() => {
  for (const [k, v] of wsConnsByIp) if (v <= 0) wsConnsByIp.delete(k);
  for (const [k, v] of wsConnsByTenant) if (v <= 0) wsConnsByTenant.delete(k);
}, 60_000).unref();

// SEC: Use composite key "tenantSlug:userId" to prevent cross-tenant userId collision.
// In single-tenant mode, key is "null:userId".
const clients = new Map<string, Set<AuthenticatedSocket>>();
const allClients = new Set<AuthenticatedSocket>();

function clientKey(tenantSlug: string | null | undefined, userId: number): string {
  return `${tenantSlug || 'null'}:${userId}`;
}

// SEC (WS3): Minimal inline schema check so we don't pull zod into the hot path.
// A valid inbound message is `{ type: string, payload?: unknown, id?: string, ...extras }`.
// Anything else is dropped.
interface InboundMessage {
  type: string;
  payload?: unknown;
  id?: string;
  raw: Record<string, unknown>;
}

function parseInbound(raw: string): InboundMessage | null {
  let obj: unknown;
  try {
    obj = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return null;
  const o = obj as Record<string, unknown>;
  if (typeof o.type !== 'string' || o.type.length === 0 || o.type.length > 64) return null;
  if (o.id !== undefined && (typeof o.id !== 'string' || o.id.length > 128)) return null;
  // payload is intentionally left as `unknown` — specific handlers narrow it.
  return { type: o.type, payload: o.payload, id: o.id as string | undefined, raw: o };
}

// SEC (WS3): Per-socket sliding-window rate check. Returns `true` if the
// message should be accepted, `false` if the socket just crossed the limit.
function checkRateLimit(ws: AuthenticatedSocket): boolean {
  const nowMs = Date.now();
  if (!ws.msgWindowStart || nowMs - ws.msgWindowStart >= RATE_WINDOW_MS) {
    ws.msgWindowStart = nowMs;
    ws.msgWindowCount = 1;
    return true;
  }
  ws.msgWindowCount = (ws.msgWindowCount || 0) + 1;
  return ws.msgWindowCount <= MAX_MESSAGES_PER_WINDOW;
}

/**
 * SEC (WS1 rerun §24): Per-tenant origin allowlist.
 *
 * Called from the `auth` handler AFTER the JWT is verified so we know which
 * tenant DB to read. Opens the tenant DB lazily via the existing openTenantDb
 * helper, loads `store_config.allowed_origins` (JSON array of strings), and
 * checks the Origin header captured at connect time against that list.
 *
 * Returns `true` when the origin is allowed OR the tenant has not configured
 * any allowlist OR we are in single-tenant mode where store_config belongs to
 * the primary DB. Returns `false` only when the tenant explicitly configured
 * an allowlist AND the origin is not in it.
 */
async function isTenantOriginAllowed(
  tenantSlug: string | null,
  origin: string | null | undefined,
): Promise<boolean> {
  // No origin captured — the original upgrade-time check in index.ts already
  // decided whether this is acceptable (dev vs prod). Nothing more to do here.
  if (!origin) return true;

  // Single-tenant mode (no slug on the JWT) means there is no per-tenant
  // store_config to enforce — we've already run the platform-level check
  // at upgrade time.
  if (!tenantSlug) return true;

  try {
    // Lazy import keeps ws/server.ts free of DB concerns on the hot path for
    // non-auth messages and avoids a circular init in single-tenant mode.
    const { getTenantDb } = await import('../db/tenant-pool.js');
    const tdb = getTenantDb(tenantSlug);
    if (!tdb) return true;

    const row = tdb
      .prepare("SELECT value FROM store_config WHERE key = 'allowed_origins'")
      .get() as { value?: string } | undefined;
    if (!row?.value) return true; // Tenant has not configured an allowlist.

    let list: unknown;
    try {
      list = JSON.parse(row.value);
    } catch {
      // SEC-H86: Corrupt allowlist config — fail closed to prevent bypass via
      // intentionally malformed store_config rows.
      log.warn('ws tenant allowed_origins is not valid JSON — rejecting origin', { tenantSlug, origin });
      return false;
    }
    if (!Array.isArray(list) || list.length === 0) return true;

    const allowlist = list.filter((x): x is string => typeof x === 'string');
    return allowlist.includes(origin);
  } catch (err) {
    // SEC-H86: DB error or parse error during origin check — fail closed.
    // Logging before reject so ops can investigate without granting access.
    log.warn('ws tenant origin check failed — rejecting origin', {
      tenantSlug,
      origin,
      error: err instanceof Error ? err.message : String(err),
    });
    return false;
  }
}

// @audit-fixed: WS heartbeat timer was previously an un-cleared setInterval() that
// leaked across restarts and could fire after shutdown. We expose a module-level
// handle so shutdown() in index.ts can cancel it alongside other background timers,
// and we .unref() so an abandoned ws heartbeat cannot hold the process open when
// every other timer has exited.
let wsHeartbeatHandle: NodeJS.Timeout | null = null;

export function stopWebSocketHeartbeat(): void {
  if (wsHeartbeatHandle) {
    clearInterval(wsHeartbeatHandle);
    wsHeartbeatHandle = null;
  }
}

export function setupWebSocket(wss: WebSocketServer): void {
  wss.on('connection', (ws: AuthenticatedSocket, req) => {
    ws.isAlive = true;
    // SEC (WS1 rerun §24): capture the Origin header exactly once at handshake
    // time. We can't use req.headers.origin later because req is gone after
    // the connection event finishes.
    ws.origin = (req.headers.origin as string | undefined) ?? null;

    // SEC-H86: Resolve client IP from socket directly. We intentionally do NOT
    // use X-Forwarded-For here — the WS upgrade `req` is not an Express request
    // with trust-proxy applied, so XFF can be trivially spoofed. remoteAddress
    // is the actual TCP peer and is always authoritative at this layer.
    const clientIp = req.socket?.remoteAddress ?? 'unknown';

    // SEC-H86: Per-IP concurrent connection cap. Checked before allClients.add
    // so rejected sockets are never registered in the tracking set.
    const ipCount = (wsConnsByIp.get(clientIp) ?? 0) + 1;
    if (ipCount > MAX_WS_CONNECTIONS_PER_IP) {
      log.warn('ws per-IP connection cap exceeded, closing socket', {
        ip: clientIp,
        count: ipCount,
        cap: MAX_WS_CONNECTIONS_PER_IP,
      });
      try {
        ws.close(1008, 'Too many connections from this IP');
      } catch {
        /* already closed */
      }
      return;
    }
    wsConnsByIp.set(clientIp, ipCount);

    allClients.add(ws);

    // AUD-M17: Terminate unauthenticated connections after 5 seconds.
    // SEC (WS4): We must clear this timer in EVERY exit path (auth success,
    // auth failure, invalid message, rate limit, socket close) so dangling
    // timers don't pile up and fire after the socket has already been cleaned
    // up. We do this by stashing the handle on the socket and calling a
    // shared `clearAuthTimeout` helper.
    let authTimeoutHandle: NodeJS.Timeout | null = setTimeout(() => {
      if (ws.userId === undefined) {
        log.info('closing unauthenticated ws after timeout', {
          ip: req.socket?.remoteAddress || 'unknown',
        });
        try {
          ws.terminate();
        } catch {
          /* already closed */
        }
      }
    }, 5000);

    const clearAuthTimeout = (): void => {
      if (authTimeoutHandle) {
        clearTimeout(authTimeoutHandle);
        authTimeoutHandle = null;
      }
    };

    ws.on('message', (data) => {
      // SEC (WS3): Drop oversized frames before JSON.parse touches them.
      // @audit-fixed: Previously compared `raw.length` (JS character count) to
      // MAX_INBOUND_BYTES (16384). For a unicode-heavy payload, UTF-8 bytes can
      // be 2-4x the character count, so a 4KB JS string could actually be a
      // 16KB wire payload and slip past the check. Compute byte length directly
      // via Buffer.byteLength when the underlying data is a string, or use the
      // Buffer's actual length when it's already a Buffer.
      const raw = typeof data === 'string' ? data : data.toString('utf8');
      const rawLength = typeof data === 'string' ? Buffer.byteLength(data, 'utf8') : (data as Buffer).length;
      if (rawLength > MAX_INBOUND_BYTES) {
        log.warn('ws message too large', {
          bytes: rawLength,
          userId: ws.userId ?? null,
          tenantSlug: ws.tenantSlug ?? null,
        });
        // SEC (WS4): Ensure timer is cleared before we drop the socket.
        clearAuthTimeout();
        try {
          ws.close(1009, 'message too large');
        } catch {
          /* already closed */
        }
        return;
      }

      // SEC (WS3): Per-socket rate limit. Any socket over 60 msgs/minute is
      // closed immediately — no warning, no retry window.
      if (!checkRateLimit(ws)) {
        log.warn('ws rate limit exceeded, closing socket', {
          userId: ws.userId ?? null,
          tenantSlug: ws.tenantSlug ?? null,
          ip: req.socket?.remoteAddress || 'unknown',
        });
        clearAuthTimeout();
        try {
          ws.close(1008, 'rate limit');
        } catch {
          /* already closed */
        }
        return;
      }

      // SEC (WS3): Validate message shape.
      const msg = parseInbound(raw);
      if (!msg) {
        log.warn('ws malformed inbound message', {
          userId: ws.userId ?? null,
          tenantSlug: ws.tenantSlug ?? null,
        });
        return;
      }

      if (msg.type === 'auth') {
        const payloadObj = msg.payload && typeof msg.payload === 'object' && msg.payload !== null
          ? (msg.payload as Record<string, unknown>)
          : undefined;
        // Backwards compat: the original wire format was `{ type: 'auth', token: '...' }`
        // with no nested payload. Accept either shape.
        const tokenCandidate = payloadObj?.token ?? msg.raw.token;
        if (typeof tokenCandidate !== 'string' || tokenCandidate.length === 0) {
          log.warn('ws auth missing token');
          // SEC (WS4): Clear the auth timer even on failure so it does not
          // accumulate across retries on the same socket.
          clearAuthTimeout();
          try {
            ws.send(JSON.stringify({ type: 'auth', success: false, error: 'token required' }));
          } catch {
            /* already closed */
          }
          return;
        }

        try {
          // SEC: Enforce the same algorithm + issuer + audience the HTTP auth
          // middleware uses so a token that passes HTTP auth also passes here
          // and vice versa (prevents alg-confusion / cross-issuer reuse).
          // SA1-1: rotation-aware verify so WS auth also accepts tokens signed
          // with JWT_SECRET_PREVIOUS during the rotation window.
          const payload = verifyJwtWithRotation(
            tokenCandidate,
            'access',
            JWT_VERIFY_OPTIONS,
          ) as { userId: number; tenantSlug?: string | null; role?: string };
          ws.userId = payload.userId;
          ws.tenantSlug = payload.tenantSlug || null;
          ws.role = typeof payload.role === 'string' ? payload.role : 'staff';
          // SEC (WS4): Auth succeeded — clear the timeout and register.
          clearAuthTimeout();

          // SEC-H86: Per-tenant concurrent connection cap. Uses the resolved
          // tenantSlug (null for single-tenant mode). We cap single-tenant mode
          // under the special key '__single__' so null slugs are treated uniformly.
          const tenantKey = ws.tenantSlug ?? '__single__';
          const tenantCount = (wsConnsByTenant.get(tenantKey) ?? 0) + 1;
          if (tenantCount > MAX_WS_CONNECTIONS_PER_TENANT) {
            log.warn('ws per-tenant connection cap exceeded, closing socket', {
              tenantSlug: ws.tenantSlug,
              count: tenantCount,
              cap: MAX_WS_CONNECTIONS_PER_TENANT,
            });
            try {
              ws.send(JSON.stringify({ type: 'auth', success: false, error: 'tenant connection limit reached' }));
              ws.close(1008, 'Too many tenant connections');
            } catch {
              /* already closed */
            }
            return;
          }
          wsConnsByTenant.set(tenantKey, tenantCount);
          // Mark the key on the socket so the close handler can decrement correctly.
          ws._tenantCapKey = tenantKey;

          // SEC (WS1 rerun §24): Now that we know the tenant, re-validate the
          // Origin header against the tenant's store_config allowlist. This
          // layers on TOP of the platform-level check in index.ts. Fire and
          // forget the async check because we don't want to stall the rest of
          // the handler — if it fails we terminate the socket afterwards.
          (async () => {
            const ok = await isTenantOriginAllowed(ws.tenantSlug ?? null, ws.origin ?? null);
            if (!ok) {
              log.warn('ws tenant origin rejected after auth', {
                tenantSlug: ws.tenantSlug,
                origin: ws.origin,
                userId: ws.userId,
              });
              try {
                ws.send(JSON.stringify({ type: 'auth', success: false, error: 'origin not allowed' }));
                ws.close(1008, 'origin not allowed');
              } catch {
                /* already closed */
              }
            }
          })();

          const key = clientKey(ws.tenantSlug, payload.userId);
          if (!clients.has(key)) {
            clients.set(key, new Set());
          }
          clients.get(key)!.add(ws);
          try {
            ws.send(JSON.stringify({ type: 'auth', success: true }));
          } catch {
            /* already closed */
          }
        } catch (err) {
          // SEC (WS4): Clear the timer on auth FAILURE as well. Without this,
          // the timer keeps running and calls ws.terminate() some time later
          // on a socket we might have already finished with.
          log.warn('ws auth failed', {
            error: err instanceof Error ? err.message : String(err),
          });
          clearAuthTimeout();
          try {
            ws.send(JSON.stringify({ type: 'auth', success: false, error: 'invalid token' }));
            ws.close(1008, 'invalid token');
          } catch {
            /* already closed */
          }
        }
        return;
      }

      // All other message types require a prior successful auth.
      // PROD37: An unauthenticated socket that sends anything other than
      // {type: 'auth', token: ...} is closed with 1008. Prior behavior
      // sent an error frame back and left the socket open — letting a
      // scanner hold sockets for the full 5s auth-timeout window and
      // burn server resources. Closing immediately tightens the window.
      if (ws.userId === undefined) {
        log.warn('ws non-auth message from unauthenticated socket, closing', {
          type: msg.type,
        });
        clearAuthTimeout();
        try {
          ws.send(JSON.stringify({ type: 'error', error: 'not authenticated' }));
          ws.close(1008, 'not authenticated');
        } catch {
          /* already closed */
        }
        return;
      }

      // No other inbound message types are currently handled. Log and drop so
      // unexpected client traffic is visible in ops dashboards.
      log.info('ws unhandled message type', {
        type: msg.type,
        userId: ws.userId,
        tenantSlug: ws.tenantSlug ?? null,
      });
    });

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('error', (err) => {
      // SEC (WS3): Surface socket errors to ops instead of silently swallowing.
      log.error('ws socket error', {
        error: err instanceof Error ? err.message : String(err),
        userId: ws.userId ?? null,
        tenantSlug: ws.tenantSlug ?? null,
      });
    });

    ws.on('close', () => {
      // SEC (WS4): Clear the auth timer in the close handler too — this is the
      // catch-all exit path for abandoned connections and peer-triggered closes.
      clearAuthTimeout();
      allClients.delete(ws);

      // SEC-H86: Decrement per-IP counter. Delete the entry if it reaches zero
      // to prevent unbounded Map growth over long-lived servers.
      const closingIp = req.socket?.remoteAddress ?? 'unknown';
      const newIpCount = (wsConnsByIp.get(closingIp) ?? 1) - 1;
      if (newIpCount <= 0) {
        wsConnsByIp.delete(closingIp);
      } else {
        wsConnsByIp.set(closingIp, newIpCount);
      }

      // SEC-H86: Decrement per-tenant counter (only set if auth succeeded).
      if (ws._tenantCapKey !== undefined) {
        const newTenantCount = (wsConnsByTenant.get(ws._tenantCapKey) ?? 1) - 1;
        if (newTenantCount <= 0) {
          wsConnsByTenant.delete(ws._tenantCapKey);
        } else {
          wsConnsByTenant.set(ws._tenantCapKey, newTenantCount);
        }
      }

      if (ws.userId !== undefined) {
        const key = clientKey(ws.tenantSlug, ws.userId);
        if (clients.has(key)) {
          clients.get(key)!.delete(ws);
          if (clients.get(key)!.size === 0) {
            clients.delete(key);
          }
        }
      }
    });
  });

  // @audit-fixed: Heartbeat every 30s — stored on a module-level handle so
  // stopWebSocketHeartbeat() can cancel it during graceful shutdown. Previously
  // this was a detached setInterval() that leaked across reloads and could fire
  // after DB / worker pool teardown, crashing the shutdown path.
  if (wsHeartbeatHandle) {
    clearInterval(wsHeartbeatHandle);
  }
  wsHeartbeatHandle = setInterval(() => {
    allClients.forEach((ws) => {
      if (!ws.isAlive) {
        allClients.delete(ws);
        try {
          ws.terminate();
        } catch {
          /* already closed */
        }
        return;
      }
      ws.isAlive = false;
      try {
        ws.ping();
      } catch (err) {
        log.warn('ws heartbeat ping failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    });
  }, 30000);
  // @audit-fixed: .unref() so the heartbeat does not hold the process open
  // during shutdown if stopWebSocketHeartbeat() is somehow skipped.
  if (typeof wsHeartbeatHandle.unref === 'function') {
    wsHeartbeatHandle.unref();
  }
}

// Broadcast to all authenticated clients, scoped to a tenant.
// In multi-tenant mode, tenantSlug MUST be provided or clients without a tenant match are skipped.
//
// SEC (WS2 rerun §24): The same `data` object is serialized TWICE —
// once with PII (for finance roles) and once scrubbed (for everyone else).
// We lazy-build each variant so the common case of a single-role audience
// only pays for one JSON.stringify call.
export function broadcast(event: string, data: unknown, tenantSlug: string | null = null): void {
  let fullMsg: string | null = null;
  let scrubbedMsg: string | null = null;

  const getMsg = (scrub: boolean): string => {
    if (scrub) {
      if (scrubbedMsg === null) {
        scrubbedMsg = JSON.stringify({ type: event, data: scrubSensitive(data) });
      }
      return scrubbedMsg;
    }
    if (fullMsg === null) {
      fullMsg = JSON.stringify({ type: event, data });
    }
    return fullMsg;
  };

  allClients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN && ws.userId) {
      // Always scope to tenant: if broadcast has a tenant, only send to that tenant's clients.
      // If broadcast has no tenant (platform-level), only send to clients with no tenant (super-admin/management).
      if (tenantSlug !== null) {
        if (ws.tenantSlug !== tenantSlug) return;
      } else {
        // Platform-level broadcast: only send to non-tenant clients
        if (ws.tenantSlug) return;
      }
      const needsScrub = !FINANCE_ROLES.has(ws.role ?? 'staff');
      try {
        ws.send(getMsg(needsScrub));
      } catch (err) {
        log.warn('ws broadcast send failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }
  });
}

// Send to specific user (scoped to tenant via composite key)
export function sendToUser(userId: number, event: string, data: unknown, tenantSlug: string | null = null): void {
  const key = clientKey(tenantSlug, userId);
  const userSockets = clients.get(key);
  if (!userSockets) return;
  let fullMsg: string | null = null;
  let scrubbedMsg: string | null = null;
  const getMsg = (scrub: boolean): string => {
    if (scrub) {
      if (scrubbedMsg === null) {
        scrubbedMsg = JSON.stringify({ type: event, data: scrubSensitive(data) });
      }
      return scrubbedMsg;
    }
    if (fullMsg === null) {
      fullMsg = JSON.stringify({ type: event, data });
    }
    return fullMsg;
  };
  userSockets.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      const needsScrub = !FINANCE_ROLES.has(ws.role ?? 'staff');
      try {
        ws.send(getMsg(needsScrub));
      } catch (err) {
        log.warn('ws sendToUser failed', {
          error: err instanceof Error ? err.message : String(err),
          userId,
          tenantSlug,
        });
      }
    }
  });
}

export { clients, allClients };
