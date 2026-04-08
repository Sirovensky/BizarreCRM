import { WebSocketServer, WebSocket } from 'ws';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

interface AuthenticatedSocket extends WebSocket {
  userId?: number;
  tenantSlug?: string | null;
  isAlive?: boolean;
}

// SECURITY: Use composite key "tenantSlug:userId" to prevent cross-tenant userId collision.
// In single-tenant mode, key is "null:userId".
const clients = new Map<string, Set<AuthenticatedSocket>>();
const allClients = new Set<AuthenticatedSocket>();

function clientKey(tenantSlug: string | null | undefined, userId: number): string {
  return `${tenantSlug || 'null'}:${userId}`;
}

export function setupWebSocket(wss: WebSocketServer): void {
  wss.on('connection', (ws: AuthenticatedSocket) => {
    ws.isAlive = true;
    allClients.add(ws);

    // AUD-M17: Terminate unauthenticated connections after 5 seconds
    const authTimeout = setTimeout(() => {
      if (ws.userId === undefined) {
        ws.terminate();
      }
    }, 5000);

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        // First message should be auth
        if (msg.type === 'auth' && msg.token) {
          const payload = jwt.verify(msg.token, config.jwtSecret) as { userId: number; tenantSlug?: string | null };
          ws.userId = payload.userId;
          ws.tenantSlug = payload.tenantSlug || null;
          clearTimeout(authTimeout);
          const key = clientKey(ws.tenantSlug, payload.userId);
          if (!clients.has(key)) {
            clients.set(key, new Set());
          }
          clients.get(key)!.add(ws);
          ws.send(JSON.stringify({ type: 'auth', success: true }));
        }
      } catch {
        // Ignore invalid messages
      }
    });

    ws.on('pong', () => {
      ws.isAlive = true;
    });

    ws.on('close', () => {
      clearTimeout(authTimeout);
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
        ws.terminate();
        return;
      }
      ws.isAlive = false;
      ws.ping();
    });
  }, 30000);
}

// Broadcast to all authenticated clients (optionally scoped to a tenant)
export function broadcast(event: string, data: unknown, tenantSlug: string | null = null): void {
  const msg = JSON.stringify({ type: event, data });
  allClients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN && ws.userId) {
      // In multi-tenant mode, only send to clients on the same tenant
      if (tenantSlug !== null && ws.tenantSlug !== tenantSlug) return;
      ws.send(msg);
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
      ws.send(msg);
    }
  });
}

export { clients, allClients };
