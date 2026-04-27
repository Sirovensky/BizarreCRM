import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Users, Plus, RefreshCw, Trash2, Eye } from 'lucide-react';
import toast from 'react-hot-toast';
import { crmApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { formatCents } from '@/utils/format';

/**
 * SegmentsPage — list + manage customer_segments.
 *
 * Auto segments (is_auto=1) are seed-rule-driven — owners can refresh to
 * re-evaluate, but they can't edit seeded rules without dropping into the
 * raw JSON. Custom segments are created via a tiny rule builder (field +
 * op + value) so non-devs can still spin them up.
 */

interface Segment {
  id: number;
  name: string;
  description: string | null;
  rule_json: string;
  is_auto: number;
  last_refreshed_at: string | null;
  member_count: number;
}

interface Member {
  id: number;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  health_tier: string | null;
  ltv_tier: string | null;
  lifetime_value_cents: number;
}

const RULE_FIELDS = [
  { value: 'lifetime_value_cents', label: 'Lifetime value (cents)', type: 'number' },
  { value: 'health_score', label: 'Health score (0-100)', type: 'number' },
  { value: 'health_tier', label: 'Health tier', type: 'enum' },
  { value: 'ltv_tier', label: 'LTV tier', type: 'enum' },
  { value: 'tickets_12mo', label: 'Tickets in last 12mo', type: 'number' },
  { value: 'last_interaction_days', label: 'Days since last interaction', type: 'number' },
  { value: 'birthday_window_days', label: 'Days until birthday', type: 'number' },
] as const;

const RULE_OPS: ReadonlyArray<{ value: '>' | '>=' | '<' | '<=' | '=' | '!='; label: string }> = [
  { value: '>', label: '> (greater than)' },
  { value: '>=', label: '>= (at least)' },
  { value: '<', label: '< (less than)' },
  { value: '<=', label: '<= (at most)' },
  { value: '=', label: '= (equals)' },
  { value: '!=', label: '!= (not equals)' },
];

export function SegmentsPage() {
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [viewingSegment, setViewingSegment] = useState<Segment | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['crm', 'segments'],
    queryFn: async () => {
      const res = await crmApi.listSegments();
      return res.data;
    },
    staleTime: 30_000,
  });

  const segments: Segment[] = (data as any)?.data ?? [];

  const refresh = useMutation({
    mutationFn: async (id: number) => {
      const res = await crmApi.refreshSegment(id);
      return res.data;
    },
    onSuccess: (data) => {
      const d: any = (data as any)?.data ?? {};
      toast.success(`Refreshed: ${d.member_count} members`);
      queryClient.invalidateQueries({ queryKey: ['crm', 'segments'] });
    },
    onError: () => toast.error('Failed to refresh'),
  });

  const remove = useMutation({
    mutationFn: async (id: number) => {
      await crmApi.deleteSegment(id);
    },
    onSuccess: () => {
      toast.success('Segment deleted');
      queryClient.invalidateQueries({ queryKey: ['crm', 'segments'] });
    },
    onError: () => toast.error('Failed to delete'),
  });

  return (
    <div className="max-w-6xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Users className="h-6 w-6 text-primary-600 dark:text-primary-400" />
          <div>
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Segments</h1>
            <p className="text-sm text-surface-500">Smart customer groupings for bulk campaigns.</p>
          </div>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg font-medium"
        >
          <Plus className="h-4 w-4" /> New segment
        </button>
      </header>

      {isLoading ? (
        <div className="text-center py-12 text-surface-500">Loading segments...</div>
      ) : (
        <div className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 overflow-x-auto">
          <table className="w-full">
            <thead className="bg-surface-50 dark:bg-surface-800 text-xs uppercase text-surface-500">
              <tr>
                <th className="text-left p-3">Name</th>
                <th className="text-left p-3">Rule</th>
                <th className="text-right p-3">Members</th>
                <th className="text-left p-3">Last refresh</th>
                <th className="text-right p-3">Actions</th>
              </tr>
            </thead>
            <tbody>
              {segments.map((s) => (
                <tr key={s.id} className="border-t border-surface-200 dark:border-surface-700 text-sm">
                  <td className="p-3">
                    <div className="font-medium text-surface-900 dark:text-surface-100">{s.name}</div>
                    {s.description && (
                      <div className="text-xs text-surface-500">{s.description}</div>
                    )}
                    {s.is_auto === 1 && (
                      <span className="inline-block mt-1 px-1.5 py-0.5 rounded text-[9px] uppercase bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-300">Auto</span>
                    )}
                  </td>
                  <td className="p-3 max-w-sm">
                    <code className="text-[10px] font-mono text-surface-500 break-all">{s.rule_json}</code>
                  </td>
                  <td className="p-3 text-right font-semibold tabular-nums">{s.member_count}</td>
                  <td className="p-3 text-xs text-surface-500">
                    {s.last_refreshed_at ? new Date(s.last_refreshed_at).toLocaleString() : 'never'}
                  </td>
                  <td className="p-3 text-right">
                    <div className="inline-flex gap-1">
                      <button
                        type="button"
                        onClick={() => setViewingSegment(s)}
                        aria-label={`View members of segment ${s.name}`}
                        className="p-1.5 rounded hover:bg-surface-100 dark:hover:bg-surface-800"
                        title="View members"
                      >
                        <Eye aria-hidden="true" className="h-4 w-4" />
                      </button>
                      <button
                        type="button"
                        onClick={() => refresh.mutate(s.id)}
                        disabled={refresh.isPending}
                        aria-label={`Re-evaluate segment ${s.name}`}
                        className="p-1.5 rounded hover:bg-surface-100 dark:hover:bg-surface-800"
                        title="Re-evaluate rule"
                      >
                        <RefreshCw aria-hidden="true" className={refresh.isPending ? 'h-4 w-4 animate-spin' : 'h-4 w-4'} />
                      </button>
                      {s.is_auto === 0 && (
                        <button
                          onClick={async () => {
                            // FC-007: themed confirm prevents single-click destruction of a hand-built
                            // segment that may be referenced by running campaigns. Auto segments are
                            // protected by the is_auto guard above.
                            const ok = await confirm(
                              `Delete segment "${s.name}"? Campaigns referencing it will fail to send to its members.`,
                              { title: 'Delete segment', confirmLabel: 'Delete', danger: true },
                            );
                            if (ok) remove.mutate(s.id);
                          }}
                          disabled={remove.isPending && remove.variables === s.id}
                          className="p-1.5 rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-red-600 disabled:opacity-40"
                          title="Delete"
                          aria-label={`Delete segment ${s.name}`}
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showCreate && (
        <CreateSegmentModal
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false);
            queryClient.invalidateQueries({ queryKey: ['crm', 'segments'] });
          }}
        />
      )}

      {viewingSegment && (
        <MembersModal segment={viewingSegment} onClose={() => setViewingSegment(null)} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// WEB-S6-022: Multi-condition rule builder
// ---------------------------------------------------------------------------

/** A single condition row in the multi-condition builder. */
interface ConditionRow {
  id: number; // stable key for React list
  field: typeof RULE_FIELDS[number]['value'];
  op: typeof RULE_OPS[number]['value'];
  value: string;
}

let _conditionRowSeq = 1;
function makeConditionRow(
  field: typeof RULE_FIELDS[number]['value'] = 'lifetime_value_cents',
  op: typeof RULE_OPS[number]['value'] = '>',
  value = '',
): ConditionRow {
  return { id: _conditionRowSeq++, field, op, value };
}

/**
 * Serialize conditions + combinator into the rule object sent to the server.
 *
 * One condition → flat legacy form: { field: { op: value } }
 *   Server's parseSegmentRule accepts flat multi-field objects where every key
 *   is joined with AND. For a single condition this is unambiguous and stays
 *   compatible with seeded auto-segment rules that pre-date this builder.
 *
 * Two or more conditions → compound form: { op: 'and'|'or', conditions: [...] }
 *   Each element is a flat single-field leaf: { field: { op: value } }
 */
function serializeConditions(
  conditions: ConditionRow[],
  combinator: 'and' | 'or',
): Record<string, unknown> {
  const toLeaf = (c: ConditionRow): Record<string, unknown> => {
    const ruleValue: string | number = isNaN(Number(c.value)) ? c.value : Number(c.value);
    return { [c.field]: { [c.op]: ruleValue } };
  };

  if (conditions.length === 1) {
    return toLeaf(conditions[0]);
  }
  return {
    op: combinator,
    conditions: conditions.map(toLeaf),
  };
}

interface CreateProps {
  onClose: () => void;
  onCreated: () => void;
}

function CreateSegmentModal({ onClose, onCreated }: CreateProps) {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  // WEB-S6-022: multiple conditions with AND/OR combinator
  const [conditions, setConditions] = useState<ConditionRow[]>(() => [makeConditionRow()]);
  const [combinator, setCombinator] = useState<'and' | 'or'>('and');

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  const addCondition = () => {
    if (conditions.length >= 10) return; // mirror server limit
    setConditions((prev) => [...prev, makeConditionRow()]);
  };

  const removeCondition = (id: number) => {
    setConditions((prev) => prev.filter((c) => c.id !== id));
  };

  const updateCondition = (id: number, patch: Partial<Omit<ConditionRow, 'id'>>) => {
    setConditions((prev) =>
      prev.map((c) => (c.id === id ? { ...c, ...patch } : c)),
    );
  };

  const allConditionsFilled = conditions.every((c) => c.value.trim() !== '');

  const create = useMutation({
    mutationFn: async () => {
      const rule = serializeConditions(conditions, combinator);
      const res = await crmApi.createSegment({ name, description, rule, is_auto: false });
      return res.data;
    },
    onSuccess: () => {
      toast.success('Segment created');
      onCreated();
    },
    onError: (err: any) => {
      // WEB-FC-019 (Fixer-KKK 2026-04-25): prefer .message (canonical); .error kept as fallback.
      toast.error(err?.response?.data?.message ?? err?.response?.data?.error ?? 'Failed to create segment');
    },
  });

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-segment-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-xl max-w-lg w-full p-6 space-y-4 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <h2 id="new-segment-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">New segment</h2>

        <div>
          <label className="block text-xs font-medium text-surface-600 mb-1">Name</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-surface-600 mb-1">Description</label>
          <input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
          />
        </div>

        {/* WEB-S6-022: multi-condition builder */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold text-surface-700 dark:text-surface-300 uppercase tracking-wide">
              Conditions
            </p>
            {conditions.length > 1 && (
              <div className="flex items-center gap-1 text-xs">
                <span className="text-surface-500">Match</span>
                <button
                  type="button"
                  onClick={() => setCombinator('and')}
                  className={`px-2 py-0.5 rounded ${combinator === 'and' ? 'bg-primary-600 text-primary-950' : 'border border-surface-300 dark:border-surface-600 text-surface-600 dark:text-surface-300'}`}
                >
                  ALL (AND)
                </button>
                <button
                  type="button"
                  onClick={() => setCombinator('or')}
                  className={`px-2 py-0.5 rounded ${combinator === 'or' ? 'bg-primary-600 text-primary-950' : 'border border-surface-300 dark:border-surface-600 text-surface-600 dark:text-surface-300'}`}
                >
                  ANY (OR)
                </button>
              </div>
            )}
          </div>

          {conditions.map((cond, idx) => (
            <div key={cond.id} className="flex items-center gap-1.5">
              {conditions.length > 1 && (
                <span className="text-[10px] text-surface-400 w-6 shrink-0 text-right">
                  {idx === 0 ? '' : combinator.toUpperCase()}
                </span>
              )}
              {/* Field */}
              <select
                value={cond.field}
                onChange={(e) => updateCondition(cond.id, { field: e.target.value as any })}
                className="flex-1 min-w-0 px-2 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-xs"
              >
                {RULE_FIELDS.map((f) => (
                  <option key={f.value} value={f.value}>{f.label}</option>
                ))}
              </select>
              {/* Op */}
              <select
                value={cond.op}
                onChange={(e) => updateCondition(cond.id, { op: e.target.value as any })}
                className="w-14 px-1 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-xs"
              >
                {RULE_OPS.map((o) => (
                  <option key={o.value} value={o.value}>{o.value}</option>
                ))}
              </select>
              {/* Value */}
              <input
                type="text"
                value={cond.value}
                onChange={(e) => updateCondition(cond.id, { value: e.target.value })}
                placeholder="value"
                className="w-24 px-2 py-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-xs"
              />
              {/* Remove — only when more than one condition */}
              {conditions.length > 1 && (
                <button
                  type="button"
                  onClick={() => removeCondition(cond.id)}
                  className="text-red-500 hover:text-red-700 px-1"
                  aria-label="Remove condition"
                  title="Remove condition"
                >
                  ×
                </button>
              )}
            </div>
          ))}

          {conditions.length < 10 && (
            <button
              type="button"
              onClick={addCondition}
              className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
            >
              + Add condition
            </button>
          )}
          <p className="text-[10px] text-surface-500">
            Cents-based fields expect integer cents ($50 = 5000). Enum fields use exact text (e.g. "at_risk").
          </p>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700"
          >
            Cancel
          </button>
          <button
            onClick={() => create.mutate()}
            disabled={create.isPending || !name.trim() || !allConditionsFilled}
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-primary-950 font-medium disabled:opacity-50"
          >
            {create.isPending ? 'Creating…' : 'Create'}
          </button>
        </div>
      </div>
    </div>
  );
}

function MembersModal({ segment, onClose }: { segment: Segment; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['crm', 'segment-members', segment.id],
    queryFn: async () => {
      const res = await crmApi.segmentMembers(segment.id, { pagesize: 100 });
      return res.data;
    },
    staleTime: 30_000,
  });

  const members: Member[] = (data as any)?.data?.members ?? [];

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="segment-members-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-xl max-w-2xl w-full max-h-[80vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <header className="p-4 border-b border-surface-200 dark:border-surface-700">
          <h2 id="segment-members-title" className="font-bold text-surface-900 dark:text-surface-100">{segment.name}</h2>
          <p className="text-xs text-surface-500">{segment.member_count} members</p>
        </header>
        <div className="flex-1 overflow-auto p-4">
          {isLoading ? (
            <div className="text-center text-surface-500">Loading...</div>
          ) : (
            <ul className="divide-y divide-surface-200 dark:divide-surface-700">
              {members.map((m) => (
                <li key={m.id} className="py-2 flex justify-between text-sm">
                  <div>
                    <div className="font-medium">{m.first_name} {m.last_name}</div>
                    <div className="text-xs text-surface-500">{m.email ?? m.phone ?? '—'}</div>
                  </div>
                  <div className="text-xs tabular-nums text-surface-600">
                    {formatCents(m.lifetime_value_cents)}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
        <footer className="p-4 border-t border-surface-200 dark:border-surface-700 flex justify-end">
          <button onClick={onClose} className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-primary-950">Close</button>
        </footer>
      </div>
    </div>
  );
}
