import type Database from 'better-sqlite3';

declare global {
  namespace Express {
    interface Request {
      /** The active database connection — global db in single-tenant, tenant db in multi-tenant */
      db: Database.Database;
      /** Tenant slug from subdomain (multi-tenant mode only) */
      tenantSlug?: string;
      /** Tenant ID from master db (multi-tenant mode only) */
      tenantId?: number;
      /** Super admin payload from master auth middleware (multi-tenant mode only) */
      superAdmin?: { superAdminId: number; username: string; role: 'super_admin' };
    }
  }
}

export {};
