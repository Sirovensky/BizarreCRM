/**
 * Slug validation regression suite — covers the public contract of
 * provisionTenant() before any DB or DNS side-effect runs.
 *
 * PROD111's full operator smoke (signup → tenant DB → cross-tenant isolation)
 * still needs MULTI_TENANT=true + real DNS, but the slug-acceptance gate that
 * sits in front of every signup is now exercised programmatically so a regex
 * regression or a missing RESERVED_SLUGS entry shows up in CI.
 */
import { describe, expect, it } from 'vitest';
import { validateSlug } from '../tenant-provisioning.js';

describe('validateSlug — signup pre-flight (PROD111)', () => {
  it('accepts simple lowercase slugs', () => {
    expect(validateSlug('acme')).toEqual({ valid: true });
    expect(validateSlug('phone-repair-1')).toEqual({ valid: true });
  });

  it('rejects missing slug', () => {
    expect(validateSlug('')).toEqual({ valid: false, error: 'Slug is required' });
  });

  it('rejects too-short slug', () => {
    expect(validateSlug('ab').valid).toBe(false);
    expect(validateSlug('a').valid).toBe(false);
  });

  it('rejects too-long slug (>30)', () => {
    expect(validateSlug('a'.repeat(31)).valid).toBe(false);
    expect(validateSlug('a'.repeat(30)).valid).toBe(true);
  });

  it('rejects uppercase, underscores, dots, spaces, leading/trailing hyphens', () => {
    expect(validateSlug('Acme').valid).toBe(false);
    expect(validateSlug('my_shop').valid).toBe(false);
    expect(validateSlug('my.shop').valid).toBe(false);
    expect(validateSlug('my shop').valid).toBe(false);
    expect(validateSlug('-acme').valid).toBe(false);
    expect(validateSlug('acme-').valid).toBe(false);
  });

  it('rejects reserved slugs (subdomain-takeover defence)', () => {
    for (const reserved of ['www', 'api', 'admin', 'master', 'app', 'mail', 'billing', 'signup', 'login']) {
      const res = validateSlug(reserved);
      expect(res.valid, `expected "${reserved}" to be reserved`).toBe(false);
      expect(res.error).toBe('This name is reserved');
    }
  });

  it('accepts the single-char trailing pattern allowed by the regex (3-char minimum still enforced)', () => {
    expect(validateSlug('a1b').valid).toBe(true);
    expect(validateSlug('aa').valid).toBe(false);
  });
});
