import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  Loader2, User, Phone, Clock, ArrowRightLeft,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { leadApi } from '@/api/endpoints';
// @audit-fixed: use shared timeAgo helper instead of local duplicate
import { timeAgo } from '@/utils/format';

// ─── Pipeline stage config ─────────────────────────────────────
// FA-M25: "Lost" intentionally omitted from the kanban view. Marking a lead
// lost requires capturing a reason (via the LostReasonModal on the lead
// detail page), and a pipeline drop can't collect that second piece of
// information without derailing the drag/move workflow. Leads marked lost
// still appear under filtered views on the leads list. If you reintroduce
// Lost here, pair it with an inline reason-capture affordance in the
// pipeline move menu — do not fall back to navigating away.
const PIPELINE_STAGES = [
  { key: 'new', label: 'New', color: '#3b82f6' },
  { key: 'contacted', label: 'Contacted', color: '#8b5cf6' },
  { key: 'scheduled', label: 'Scheduled', color: '#f59e0b' },
  { key: 'qualified', label: 'Qualified', color: '#06b6d4' },
  { key: 'proposal', label: 'Proposal', color: '#ec4899' },
  { key: 'converted', label: 'Converted', color: '#22c55e' },
] as const;

function getScoreColor(score: number): string {
  if (score >= 70) return '#22c55e';
  if (score >= 40) return '#f59e0b';
  return '#ef4444';
}

function ScoreDot({ score }: { score: number }) {
  const color = getScoreColor(score);
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-semibold"
      style={{ backgroundColor: `${color}18`, color }}
    >
      {score}
    </span>
  );
}

// @audit-fixed: removed local timeAgo (was duplicate of utils/format.ts version)

// ─── Lead Card ─────────────────────────────────────────────────
function LeadCard({
  lead,
  onMove,
  onNavigate,
}: {
  lead: any;
  onMove: (leadId: number, newStatus: string) => void;
  onNavigate: (id: number) => void;
}) {
  const [showMoveMenu, setShowMoveMenu] = useState(false);

  return (
    <div
      className="group relative rounded-lg border border-surface-200 bg-white p-3 shadow-sm transition-shadow hover:shadow-md dark:border-surface-700 dark:bg-surface-800"
    >
      {/* Top row: name + score */}
      <div className="flex items-start justify-between gap-2 mb-1.5">
        <button
          onClick={() => onNavigate(lead.id)}
          className="text-left text-sm font-medium text-surface-900 hover:text-primary-600 dark:text-surface-100 dark:hover:text-primary-400"
        >
          {lead.first_name} {lead.last_name}
        </button>
        <ScoreDot score={lead.lead_score ?? 0} />
      </div>

      {/* Contact info */}
      <div className="space-y-0.5 mb-2">
        {lead.phone && (
          <div className="flex items-center gap-1 text-xs text-surface-500 dark:text-surface-400">
            <Phone className="h-3 w-3" />
            <span className="truncate">{lead.phone}</span>
          </div>
        )}
        {lead.assigned_first_name && (
          <div className="flex items-center gap-1 text-xs text-surface-500 dark:text-surface-400">
            <User className="h-3 w-3" />
            <span>{lead.assigned_first_name} {lead.assigned_last_name}</span>
          </div>
        )}
      </div>

      {/* Footer: time + actions */}
      <div className="flex items-center justify-between">
        <span className="text-[10px] text-surface-400 flex items-center gap-1">
          <Clock className="h-3 w-3" />
          {lead.created_at ? timeAgo(lead.created_at) : '--'}
        </span>
        <div className="relative">
          <button
            onClick={() => setShowMoveMenu(!showMoveMenu)}
            className="rounded p-1 text-surface-400 opacity-0 transition-opacity group-hover:opacity-100 hover:bg-surface-100 dark:hover:bg-surface-700"
            title="Move to stage"
          >
            <ArrowRightLeft className="h-3.5 w-3.5" />
          </button>
          {showMoveMenu && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setShowMoveMenu(false)} />
              <div className="absolute right-0 bottom-full z-20 mb-1 w-36 rounded-lg border border-surface-200 bg-white py-1 shadow-lg dark:border-surface-700 dark:bg-surface-800">
                {PIPELINE_STAGES.filter((s) => s.key !== lead.status).map((stage) => (
                  <button
                    key={stage.key}
                    onClick={() => {
                      onMove(lead.id, stage.key);
                      setShowMoveMenu(false);
                    }}
                    className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700"
                  >
                    <span className="h-2 w-2 rounded-full" style={{ backgroundColor: stage.color }} />
                    <span className="text-surface-700 dark:text-surface-300">{stage.label}</span>
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      </div>

      {/* Order ID badge */}
      {lead.order_id && (
        <div className="absolute -top-2 left-2 rounded bg-surface-100 px-1.5 py-0.5 text-[10px] font-medium text-surface-500 dark:bg-surface-700 dark:text-surface-400">
          {lead.order_id}
        </div>
      )}
    </div>
  );
}

// ─── Pipeline Column ───────────────────────────────────────────
function PipelineColumn({
  stage,
  leads,
  onMove,
  onNavigate,
}: {
  stage: (typeof PIPELINE_STAGES)[number];
  leads: any[];
  onMove: (leadId: number, newStatus: string) => void;
  onNavigate: (id: number) => void;
}) {
  return (
    <div className="flex w-[260px] shrink-0 flex-col rounded-xl bg-surface-50 dark:bg-surface-900/50">
      {/* Column header */}
      <div className="flex items-center justify-between px-3 py-3">
        <div className="flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: stage.color }} />
          <span className="text-sm font-semibold text-surface-700 dark:text-surface-300">{stage.label}</span>
        </div>
        <span
          className="rounded-full px-2 py-0.5 text-xs font-medium"
          style={{ backgroundColor: `${stage.color}18`, color: stage.color }}
        >
          {leads.length}
        </span>
      </div>

      {/* Cards */}
      <div className="flex-1 space-y-2 overflow-y-auto px-2 pb-3" style={{ maxHeight: 'calc(100vh - 240px)' }}>
        {leads.length === 0 ? (
          <div className="rounded-lg border border-dashed border-surface-300 py-8 text-center text-xs text-surface-400 dark:border-surface-600">
            No leads
          </div>
        ) : (
          leads.map((lead) => (
            <LeadCard
              key={lead.id}
              lead={lead}
              onMove={onMove}
              onNavigate={onNavigate}
            />
          ))
        )}
      </div>
    </div>
  );
}

// ─── Main Component ────────────────────────────────────────────
export function LeadPipelinePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ['leads', 'pipeline'],
    queryFn: () => leadApi.pipeline(),
  });

  const pipeline: Record<string, any[]> = data?.data?.data ?? {};

  const updateMut = useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) =>
      leadApi.update(id, { status }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['leads'] });
      toast.success('Lead moved');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to move lead'),
  });

  function handleMove(leadId: number, newStatus: string) {
    // FA-M25: Lost is no longer a pipeline stage (see PIPELINE_STAGES). The
    // move menu filters by stage key, so newStatus can never be 'lost' here —
    // keeping a defensive guard in case the column is reintroduced upstream.
    if (newStatus === 'lost') {
      navigate(`/leads/${leadId}`);
      toast('Mark lead as lost from the detail page to provide a reason');
      return;
    }
    updateMut.mutate({ id: leadId, status: newStatus });
  }

  function handleNavigate(id: number) {
    navigate(`/leads/${id}`);
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Pipeline</h1>
        <p className="text-surface-500 dark:text-surface-400">
          Drag-free kanban view of leads by stage.
          {' '}
          <span className="text-surface-400 dark:text-surface-500">
            Use the arrow icon on each card to move between stages.
          </span>
        </p>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-32">
          <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
        </div>
      ) : (
        <div className="flex gap-3 overflow-x-auto pb-4">
          {PIPELINE_STAGES.map((stage) => (
            <PipelineColumn
              key={stage.key}
              stage={stage}
              leads={pipeline[stage.key] ?? []}
              onMove={handleMove}
              onNavigate={handleNavigate}
            />
          ))}
        </div>
      )}
    </div>
  );
}
