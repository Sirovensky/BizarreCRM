/**
 * Type-safe wrapper around window.electronAPI exposed by the preload script.
 * All renderer-side API calls go through this module.
 */

// ── Response types ────────────────────────────────────────────────

export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  message?: string;
  offline?: boolean;
}

// ── Server stats ──────────────────────────────────────────────────

export interface ServerStats {
  uptime: number;
  memory: { rss: number; heapUsed: number; heapTotal: number };
  cpu: { user: number; system: number };
  dbSizeBytes: number;
  dbSizeMB: number;
  uploadsSizeBytes: number;
  uploadsSizeMB: number;
  activeConnections: number;
  requestsPerSecond: number;
  requestsPerSecondAvg: number;
  requestsPerSecondPeak: number;
  requestsPerMinute: number;
  avgResponseMs: number;
  p95ResponseMs: number;
  nodeVersion: string;
  platform: string;
  hostname: string;
  pm2Managed: boolean;
  multiTenant?: boolean;
  nodeEnv?: string;
}

// ── Crash types ───────────────────────────────────────────────────

export interface CrashEntry {
  id: string;
  timestamp: string;
  route: string;
  errorMessage: string;
  errorStack: string;
  type: 'uncaughtException' | 'unhandledRejection';
  recovered: boolean;
}

export interface CrashStats {
  totalCrashes: number;
  disabledCount: number;
  recentCrashes: CrashEntry[];
}

export interface DisabledRoute {
  route: string;
  disabledAt: string;
  crashCount: number;
  lastError: string;
}

// ── Service types ─────────────────────────────────────────────────

export interface ServiceStatus {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'none';
}

// ── Tenant types ──────────────────────────────────────────────────

export interface Tenant {
  id: number;
  slug: string;
  name: string;
  status: 'active' | 'suspended';
  plan: string;
  db_size_bytes?: number;
  created_at: string;
}

// ── System types ──────────────────────────────────────────────────

export interface DiskDrive {
  mount: string;
  total: number;
  free: number;
  used: number;
}

export interface SystemInfo {
  platform: string;
  arch: string;
  hostname: string;
  totalMemory: number;
  freeMemory: number;
  cpus: number;
  nodeVersion: string;
  electronVersion: string;
  appVersion: string;
  isPackaged: boolean;
}

// ── Bridge accessor ───────────────────────────────────────────────

export interface SetupStatus {
  needsSetup: boolean;
  managementApiEnabled: boolean;
  multiTenant: boolean;
}

interface ElectronAPI {
  management: {
    setupStatus(): Promise<ApiResponse<SetupStatus>>;
    logout(): Promise<ApiResponse>;
    getStats(): Promise<ApiResponse<ServerStats>>;
    getCrashes(): Promise<ApiResponse<CrashEntry[]>>;
    getCrashStats(): Promise<ApiResponse<CrashStats>>;
    getDisabledRoutes(): Promise<ApiResponse<DisabledRoute[]>>;
    reenableRoute(route: string): Promise<ApiResponse>;
    clearCrashes(): Promise<ApiResponse>;
    getUpdateStatus(): Promise<ApiResponse>;
    checkUpdates(): Promise<ApiResponse>;
    performUpdate(): Promise<ApiResponse>;
    restartServer(): Promise<ApiResponse>;
    stopServer(): Promise<ApiResponse>;
  };
  superAdmin: {
    login(username: string, password: string): Promise<ApiResponse>;
    verify2fa(challengeToken: string, code: string): Promise<ApiResponse<{ token: string }>>;
    setup2fa(challengeToken: string): Promise<ApiResponse>;
    setPassword(challengeToken: string, password: string): Promise<ApiResponse>;
    getDashboard(): Promise<ApiResponse>;
    listTenants(): Promise<ApiResponse<{ tenants: Tenant[] }>>;
    createTenant(data: unknown): Promise<ApiResponse<Tenant>>;
    getTenant(slug: string): Promise<ApiResponse<Tenant>>;
    suspendTenant(slug: string): Promise<ApiResponse>;
    activateTenant(slug: string): Promise<ApiResponse>;
    deleteTenant(slug: string): Promise<ApiResponse>;
    getAuditLog(params?: string): Promise<ApiResponse>;
    getSessions(): Promise<ApiResponse>;
    revokeSession(id: string): Promise<ApiResponse>;
    getConfig(): Promise<ApiResponse<Record<string, string>>>;
    updateConfig(updates: Record<string, string>): Promise<ApiResponse>;
  };
  admin: {
    getStatus(): Promise<ApiResponse>;
    listDrives(): Promise<ApiResponse>;
    browseDrive(path: string): Promise<ApiResponse>;
    createFolder(parentPath: string, name: string): Promise<ApiResponse>;
    listBackups(): Promise<ApiResponse>;
    runBackup(): Promise<ApiResponse>;
    updateBackupSettings(settings: unknown): Promise<ApiResponse>;
    deleteBackup(filename: string): Promise<ApiResponse>;
  };
  service: {
    getStatus(): Promise<ServiceStatus>;
    start(): Promise<ApiResponse>;
    stop(): Promise<ApiResponse>;
    restart(): Promise<ApiResponse>;
    emergencyStop(): Promise<ApiResponse>;
    killAll(): Promise<ApiResponse>;
    setAutoStart(enabled: boolean): Promise<ApiResponse>;
    disable(): Promise<ApiResponse>;
  };
  system: {
    getDiskSpace(): Promise<ApiResponse<DiskDrive[]>>;
    getInfo(): Promise<ApiResponse<SystemInfo>>;
    openBrowser(): Promise<void>;
    openExternal(url: string): Promise<void>;
    openLogFile(): Promise<void>;
    closeDashboard(): Promise<void>;
    minimize(): Promise<void>;
    maximize(): Promise<void>;
  };
}

declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}

/**
 * Get the electron API bridge. Throws in non-Electron environments.
 */
export function getAPI(): ElectronAPI {
  if (!window.electronAPI) {
    throw new Error('electronAPI not available — not running in Electron');
  }
  return window.electronAPI;
}
