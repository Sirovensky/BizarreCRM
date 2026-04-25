// WEB-FK-001: Ticket-status state-machine guard.
//
// Server-side allows arbitrary status flips (operator decides), so the client
// is the only place to give a foot-gun warning when an operator is about to
// undo a closed/cancelled ticket. The guard is intentionally lenient:
// open->open transitions are always fine; only the dangerous "reopen" or
// "uncancel" path requires a confirmation, and we block flipping directly
// between closed and cancelled (those are mutually exclusive end states).
//
// Status objects come from `TicketStatus` in @bizarre-crm/shared.

interface MinimalStatus {
  id: number;
  name: string;
  is_closed: boolean;
  is_cancelled: boolean;
}

export type TransitionVerdict =
  | { kind: 'allowed' }
  | { kind: 'confirm'; reason: string }
  | { kind: 'forbidden'; reason: string };

export function evaluateTicketTransition(
  from: MinimalStatus | undefined,
  to: MinimalStatus | undefined,
): TransitionVerdict {
  if (!from || !to) return { kind: 'allowed' };
  if (from.id === to.id) return { kind: 'allowed' };

  const fromClosed = from.is_closed;
  const fromCancelled = from.is_cancelled;
  const toClosed = to.is_closed;
  const toCancelled = to.is_cancelled;

  // Closed <-> cancelled is meaningless — both are terminal end-states.
  if ((fromClosed && toCancelled) || (fromCancelled && toClosed)) {
    return {
      kind: 'forbidden',
      reason: `Cannot flip directly between Closed and Cancelled — restore to an active status first.`,
    };
  }

  // Reopening a closed ticket: confirm.
  if (fromClosed && !toClosed && !toCancelled) {
    return {
      kind: 'confirm',
      reason: `Reopen ticket from "${from.name}" to "${to.name}"? Inventory and invoice commitments will be re-evaluated.`,
    };
  }

  // Uncancelling a cancelled ticket: confirm.
  if (fromCancelled && !toClosed && !toCancelled) {
    return {
      kind: 'confirm',
      reason: `Restore cancelled ticket to "${to.name}"?`,
    };
  }

  return { kind: 'allowed' };
}
