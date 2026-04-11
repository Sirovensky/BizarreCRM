import { WebSocketServer, WebSocket } from 'ws';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { JWT_VERIFY_OPTIONS } from '../middleware/auth.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('ws');

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
  isAlive?: boolean;
  // SEC (WS3): Sliding-window counter for rate limiting.
  msgWindowStart?: number;
  msgWindowCount?: number;
}

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

export function setupWebSocket(wss: WebSocketServer): void {
  wss.on('connection', (ws: AuthenticatedSocket, req) => {
    ws.isAlive = true;
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
      const raw = typeof data === 'string' ? data : data.toString('utf8');
      if (raw.length > MAX_INBOUND_BYTES) {
        log.warn('ws message too large', {
          bytes: raw.length,
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
          const payload = jwt.verify(
            tokenCandidate,
            config.jwtSecret,
            JWT_VERIFY_OPTIONS,
          ) as { userId: number; tenantSlug?: string | null };
          ws.userId = payload.userId;
          ws.tenantSlug = payload.tenantSlug || null;
          // SEC (WS4): Auth succeeded — clear the timeout and register.
          clearAuthTimeout();
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
      if (ws.userId === undefined) {
        log.warn('ws non-auth message from unauthenticated socket', {
          type: msg.type,
        });
        try {
          ws.send(JSON.stringify({ type: 'error', error: 'not authenticated' }));
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

  // Heartbeat every 30 seconds
  setInterval(() => {
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
}

// Broadcast to all authenticated clients, scoped to a tenant.
// In multi-tenant mode, tenantSlug MUST be provided or clients without a tenant match are skipped.
export function broadcast(event: string, data: unknown, tenantSlug: string | null = null): void {
  const msg = JSON.stringify({ type: event, data });
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
      try {
        ws.send(msg);
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
  const msg = JSON.stringify({ type: event, data });
  userSockets.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(msg);
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
