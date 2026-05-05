/**
 * Unit tests for the long-task registry.
 *
 * Coverage targets:
 *   - start/end/snapshot happy path
 *   - double-start logs warning and overwrites
 *   - end-without-start is a no-op (does not throw)
 *   - snapshot returns the same object instance until end() is called
 *   - startedAt is populated by start(), not the caller
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  start,
  end,
  snapshot,
  _resetForTests,
  type LongTask,
} from '../longTaskRegistry.js';

describe('longTaskRegistry', () => {
  beforeEach(() => {
    _resetForTests();
  });

  it('snapshot() returns null when no task is active', () => {
    expect(snapshot()).toBeNull();
  });

  it('start() registers a task with caller-supplied kind and expectedDurationMs', () => {
    start({ kind: 'tenant-migration', expectedDurationMs: 600_000 });
    const snap = snapshot();
    expect(snap).not.toBeNull();
    expect(snap!.kind).toBe('tenant-migration');
    expect(snap!.expectedDurationMs).toBe(600_000);
  });

  it('start() populates startedAt from Date.now(), not from caller', () => {
    const before = Date.now();
    start({ kind: 'bulk-import', expectedDurationMs: 30_000 });
    const after = Date.now();
    const snap = snapshot()!;
    expect(snap.startedAt).toBeGreaterThanOrEqual(before);
    expect(snap.startedAt).toBeLessThanOrEqual(after);
  });

  it('start() preserves optional details payload', () => {
    start({
      kind: 'tenant-migration',
      expectedDurationMs: 60_000,
      details: { tenant: 'acme', migrationVersion: 42 },
    });
    expect(snapshot()!.details).toEqual({ tenant: 'acme', migrationVersion: 42 });
  });

  it('end() clears the current task', () => {
    start({ kind: 'av-scan', expectedDurationMs: 15_000 });
    expect(snapshot()).not.toBeNull();
    end();
    expect(snapshot()).toBeNull();
  });

  it('end() called without an active task is a no-op (does not throw)', () => {
    expect(() => end()).not.toThrow();
    expect(snapshot()).toBeNull();
  });

  it('start() while another task is active overwrites and warns', () => {
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    start({ kind: 'first', expectedDurationMs: 10_000 });
    start({ kind: 'second', expectedDurationMs: 20_000 });

    const snap = snapshot()!;
    expect(snap.kind).toBe('second');
    expect(snap.expectedDurationMs).toBe(20_000);
    expect(warnSpy).toHaveBeenCalled();

    warnSpy.mockRestore();
  });

  it('snapshot() returns a LongTask shape with all fields', () => {
    start({ kind: 'report-build', expectedDurationMs: 45_000, details: { reportId: 'r1' } });
    const snap = snapshot();
    expect(snap).toMatchObject<LongTask>({
      kind: 'report-build',
      startedAt: expect.any(Number),
      expectedDurationMs: 45_000,
      details: { reportId: 'r1' },
    });
  });
});
