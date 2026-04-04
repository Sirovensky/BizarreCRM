import { WebSocketServer, WebSocket } from 'ws';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

interface AuthenticatedSocket extends WebSocket {
  userId?: number;
  isAlive?: boolean;
}

const clients = new Map<number, Set<AuthenticatedSocket>>();
const allClients = new Set<AuthenticatedSocket>();

export function setupWebSocket(wss: WebSocketServer): void {
  wss.on('connection', (ws: AuthenticatedSocket) => {
    ws.isAlive = true;
    allClients.add(ws);

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        // First message should be auth
        if (msg.type === 'auth' && msg.token) {
          const payload = jwt.verify(msg.token, config.jwtSecret) as { userId: number };
          ws.userId = payload.userId;
          if (!clients.has(payload.userId)) {
            clients.set(payload.userId, new Set());
          }
          clients.get(payload.userId)!.add(ws);
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
      allClients.delete(ws);
      if (ws.userId && clients.has(ws.userId)) {
        clients.get(ws.userId)!.delete(ws);
        if (clients.get(ws.userId)!.size === 0) {
          clients.delete(ws.userId);
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

// Broadcast to all authenticated clients
export function broadcast(event: string, data: unknown): void {
  const msg = JSON.stringify({ type: event, data });
  allClients.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN && ws.userId) {
      ws.send(msg);
    }
  });
}

// Send to specific user
export function sendToUser(userId: number, event: string, data: unknown): void {
  const userSockets = clients.get(userId);
  if (!userSockets) return;
  const msg = JSON.stringify({ type: event, data });
  userSockets.forEach((ws) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(msg);
    }
  });
}

export { clients, allClients };
