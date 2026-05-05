import type Database from 'better-sqlite3';
import type { AsyncDb } from '../db/async-db.js';

declare global {
  namespace Express {
    interface Request {
      /** The active database connection — global db in single-tenant, tenant db in multi-tenant */
      db: Database.Database;
      /** Async DB — worker-thread based, non-blocking version of db */
      asyncDb: AsyncDb;
      /** Tenant slug from subdomain (multi-tenant mode only) */
      tenantSlug?: string;
      /** Tenant ID from master db (multi-tenant mode only) */
      tenantId?: number;
      /** Super admin payload from master auth middleware (multi-tenant mode only) */
      superAdmin?: { superAdminId: number; username: string; role: 'super_admin' };
      /** Effective tenant plan after trial resolution */
      tenantPlan?: 'free' | 'pro';
      /** Tenant limits for the effective plan */
      tenantLimits?: { maxTicketsMonth: number | null; maxUsers: number | null; storageLimitMb: number | null };
      /** Whether the tenant is currently on a Pro trial */
      tenantTrialActive?: boolean;
      /** When the trial ends (ISO string) */
      tenantTrialEndsAt?: string | null;
    }
  }
}

export {};
