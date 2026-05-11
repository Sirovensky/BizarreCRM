import { describe, expect, it } from 'vitest';
import { PERMISSIONS } from '@bizarre-crm/shared';
import {
  hasPermission,
  resolveEffectivePermission,
  type AuthUser,
} from './auth.js';

function makeUser(overrides: Partial<AuthUser> = {}): AuthUser {
  return {
    id: 1,
    username: 'user',
    email: 'user@example.com',
    first_name: 'Test',
    last_name: 'User',
    role: 'cashier',
    permissions: null,
    sessionId: 'session',
    customRolePermissions: null,
    permissionOverrides: null,
    ...overrides,
  };
}

describe('effective permission resolution', () => {
  it('keeps seeded cashier permissions broad enough for normal counter corrections without destructive grants', () => {
    const cashier = makeUser({ role: 'cashier' });

    for (const permission of [
      PERMISSIONS.TICKETS_CREATE,
      PERMISSIONS.TICKETS_EDIT,
      PERMISSIONS.TICKETS_CHANGE_STATUS,
      PERMISSIONS.TICKETS_ASSIGN,
      PERMISSIONS.CUSTOMERS_EDIT,
      PERMISSIONS.INVOICES_CREATE,
      PERMISSIONS.INVOICES_EDIT,
      PERMISSIONS.INVOICES_RECORD_PAYMENT,
      PERMISSIONS.DEPOSITS_CREATE,
      PERMISSIONS.GIFT_CARDS_REDEEM,
    ]) {
      expect(hasPermission(cashier, permission)).toBe(true);
    }

    for (const permission of [
      PERMISSIONS.TICKETS_DELETE,
      PERMISSIONS.CUSTOMERS_DELETE,
      PERMISSIONS.INVOICES_DELETE,
      PERMISSIONS.INVOICES_VOID,
      PERMISSIONS.REFUNDS_APPROVE,
      PERMISSIONS.USERS_MANAGE,
      PERMISSIONS.IMPORT_EXPORT,
    ]) {
      expect(hasPermission(cashier, permission)).toBe(false);
    }
  });

  it('lets seeded technicians create and edit estimates for repair quotes', () => {
    const technician = makeUser({ role: 'technician' });

    expect(hasPermission(technician, PERMISSIONS.ESTIMATES_VIEW)).toBe(true);
    expect(hasPermission(technician, PERMISSIONS.ESTIMATES_CREATE)).toBe(true);
    expect(hasPermission(technician, PERMISSIONS.ESTIMATES_EDIT)).toBe(true);
    expect(hasPermission(technician, PERMISSIONS.CUSTOMERS_BULK_TAG)).toBe(false);
    expect(hasPermission(technician, PERMISSIONS.INVOICES_EDIT)).toBe(false);
  });

  it('keeps seeded managers operational while reserving account-admin and GDPR powers', () => {
    const manager = makeUser({ role: 'manager' });

    expect(hasPermission(manager, PERMISSIONS.REFUNDS_APPROVE)).toBe(true);
    expect(hasPermission(manager, PERMISSIONS.CUSTOMERS_MERGE)).toBe(true);
    expect(hasPermission(manager, PERMISSIONS.CUSTOMERS_ARCHIVE)).toBe(true);
    expect(hasPermission(manager, PERMISSIONS.INVOICES_BULK_ACTION)).toBe(true);
    expect(hasPermission(manager, PERMISSIONS.TICKETS_BULK_UPDATE)).toBe(true);
    expect(hasPermission(manager, PERMISSIONS.USERS_MANAGE)).toBe(false);
    expect(hasPermission(manager, PERMISSIONS.IMPORT_EXPORT)).toBe(false);
    expect(hasPermission(manager, PERMISSIONS.CUSTOMERS_GDPR_ERASE)).toBe(false);
  });

  it('lets explicit user denies override admin and default role grants', () => {
    const admin = makeUser({
      role: 'admin',
      permissionOverrides: new Map([[PERMISSIONS.USERS_MANAGE, false]]),
    });
    const cashier = makeUser({
      role: 'cashier',
      permissionOverrides: new Map([[PERMISSIONS.POS_ACCESS, false]]),
    });

    expect(resolveEffectivePermission(admin, PERMISSIONS.USERS_MANAGE)).toEqual({
      allowed: false,
      source: 'user_deny',
    });
    expect(hasPermission(admin, PERMISSIONS.USERS_MANAGE)).toBe(false);
    expect(resolveEffectivePermission(cashier, PERMISSIONS.POS_ACCESS)).toEqual({
      allowed: false,
      source: 'user_deny',
    });
  });

  it('lets explicit user grants add permissions outside the base role', () => {
    const cashier = makeUser({
      role: 'cashier',
      permissionOverrides: new Map([[PERMISSIONS.INVOICES_VOID, true]]),
    });

    expect(resolveEffectivePermission(cashier, PERMISSIONS.INVOICES_VOID)).toEqual({
      allowed: true,
      source: 'user_grant',
    });
    expect(hasPermission(cashier, PERMISSIONS.INVOICES_VOID)).toBe(true);
  });

  it('uses active custom-role permissions instead of the raw users.role fallback', () => {
    const narrowedAdmin = makeUser({
      role: 'admin',
      customRolePermissions: new Set([PERMISSIONS.TICKETS_VIEW]),
    });

    expect(resolveEffectivePermission(narrowedAdmin, PERMISSIONS.TICKETS_VIEW)).toEqual({
      allowed: true,
      source: 'custom_role',
    });
    expect(resolveEffectivePermission(narrowedAdmin, PERMISSIONS.USERS_MANAGE)).toEqual({
      allowed: false,
      source: 'none',
    });
  });

  it('applies user overrides before custom roles', () => {
    const user = makeUser({
      role: 'manager',
      customRolePermissions: new Set([PERMISSIONS.TICKETS_VIEW]),
      permissionOverrides: new Map([
        [PERMISSIONS.TICKETS_VIEW, false],
        [PERMISSIONS.USERS_MANAGE, true],
      ]),
    });

    expect(resolveEffectivePermission(user, PERMISSIONS.TICKETS_VIEW)).toEqual({
      allowed: false,
      source: 'user_deny',
    });
    expect(resolveEffectivePermission(user, PERMISSIONS.USERS_MANAGE)).toEqual({
      allowed: true,
      source: 'user_grant',
    });
  });

  it('keeps legacy users.permissions as grant-only compatibility', () => {
    const user = makeUser({
      role: 'cashier',
      permissions: {
        [PERMISSIONS.REFUNDS_APPROVE]: true,
        [PERMISSIONS.POS_ACCESS]: false,
      },
    });

    expect(resolveEffectivePermission(user, PERMISSIONS.REFUNDS_APPROVE)).toEqual({
      allowed: true,
      source: 'legacy_user_grant',
    });
    expect(resolveEffectivePermission(user, PERMISSIONS.POS_ACCESS)).toEqual({
      allowed: true,
      source: 'default_role',
    });
  });
});
