import { useState, useMemo, useEffect, useRef } from 'react';
import { X, Pen, Loader2, CheckCheck, AlertCircle, ShieldOff, LockOpen } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, blockchypApi, settingsApi } from '@/api/endpoints';
import { api } from '@/api/client';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { useUnifiedPosStore } from './store';
import { useSettings } from '@/hooks/useSettings';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { PinModal } from '@/components/shared/PinModal';
import { CashDrawerWidget } from './CashDrawerWidget';
import type { RepairCartItem } from './types';
import { submitTrainingTransaction, useIsTraining } from './TrainingModeBanner';

// ─── Cash In/Out Modal ──────────────────────────────────────────────

interface CashModalProps {
  type: 'in' | 'out';
  onClose: () => void;
}

function CashModal({ type, onClose }: CashModalProps) {
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);

  // WEB-FX-003: Esc dismisses unless we're mid-submit.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose, submitting]);

  const handleSubmit = async () => {
    const num = parseFloat(amount);
    if (!num || num <= 0) {
      toast.error('Enter a valid amount');
      return;
    }
    setSubmitting(true);
    try {
      const fn = type === 'in' ? posApi.cashIn : posApi.cashOut;
      await fn({ amount: num, reason: reason.trim() || undefined });
      // @audit-fixed (WEB-FF-003 / Fixer-PP 2026-04-25): hardcoded `$` + `toFixed(2)`
      // → tenant-aware currency formatter.
      toast.success(`Cash ${type === 'in' ? 'in' : 'out'}: ${formatCurrency(num)}`);
      onClose();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : `Cash ${type} failed`);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      onClick={(e) => {
        if (e.target === e.currentTarget && !submitting) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="cash-modal-title"
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 id="cash-modal-title" className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Cash {type === 'in' ? 'In' : 'Out'}
          </h3>
          <button aria-label="Close" onClick={onClose} className="btn-icon btn-xs">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-3 p-5">
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Amount ($)</label>
            <input
              type="text" inputMode="decimal" pattern="[0-9.]*"
              step="0.01"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="0.00"
              autoFocus
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Reason (optional)</label>
            <input
              type="text"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="e.g. Change for customer"
            />
          </div>
          <button
            onClick={handleSubmit}
            disabled={submitting}
            className="btn btn-md w-full bg-teal-600 text-white hover:bg-teal-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {submitting ? 'Processing...' : `Confirm Cash ${type === 'in' ? 'In' : 'Out'}`}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── BottomActions ──────────────────────────────────────────────────

// ─── Signature Gate Modal ───────────────────────────────────────────

type SigModalState = 'pending' | 'done' | 'error';

interface SignatureGateModalProps {
  state: SigModalState;
  error: string;
  signatureFile: string | null;
  onRetry: () => void;
  onBypass: () => void;
  onCancel: () => void;
  onProceed: () => void;
}

function SignatureGateModal({ state, error, signatureFile, onRetry, onBypass, onCancel, onProceed }: SignatureGateModalProps) {
  // WEB-FX-003: Esc cancels (but only when not actively waiting on hardware).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && state !== 'pending') onCancel();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onCancel, state]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      onClick={(e) => {
        if (e.target === e.currentTarget && state !== 'pending') onCancel();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="signature-gate-title"
        className="w-full max-w-md rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 id="signature-gate-title" className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Customer Signature Required
          </h3>
          <button aria-label="Close" onClick={onCancel} className="btn-icon btn-xs">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="flex flex-col items-center gap-4 p-6">
          {state === 'pending' && (
            <>
              <div className="flex h-16 w-16 items-center justify-center rounded-full bg-primary-100 dark:bg-primary-500/10">
                <Loader2 className="h-8 w-8 animate-spin text-primary-600 dark:text-primary-400" />
              </div>
              <p className="text-center text-sm text-surface-700 dark:text-surface-300">
                Waiting for customer to sign on the terminal...
              </p>
              <button
                onClick={onBypass}
                className="btn btn-sm mt-2 border border-amber-300 text-amber-700 hover:bg-amber-50 dark:border-amber-500/30 dark:text-amber-400 dark:hover:bg-amber-500/10"
              >
                <ShieldOff className="h-4 w-4" />
                Skip Signature
              </button>
            </>
          )}
          {state === 'done' && (
            <>
              <div className="flex h-16 w-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-500/10">
                <CheckCheck className="h-8 w-8 text-green-600 dark:text-green-400" />
              </div>
              <p className="text-center text-sm font-medium text-green-700 dark:text-green-300">
                Signature captured successfully
              </p>
              <button
                onClick={onProceed}
                className="btn btn-md mt-2 bg-teal-600 !px-6 !font-semibold text-white hover:bg-teal-700"
              >
                Create Ticket
              </button>
            </>
          )}
          {state === 'error' && (
            <>
              <div className="flex h-16 w-16 items-center justify-center rounded-full bg-red-100 dark:bg-red-500/10">
                <AlertCircle className="h-8 w-8 text-red-600 dark:text-red-400" />
              </div>
              <p className="text-center text-sm text-red-700 dark:text-red-300">
                {error || 'Signature capture failed'}
              </p>
              <div className="flex gap-3">
                <button
                  onClick={onRetry}
                  className="btn btn-sm border border-surface-300 text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
                >
                  <Pen className="h-4 w-4" />
                  Retry
                </button>
                <button
                  onClick={onBypass}
                  className="btn btn-sm border border-amber-300 text-amber-700 hover:bg-amber-50 dark:border-amber-500/30 dark:text-amber-400 dark:hover:bg-amber-500/10"
                >
                  <ShieldOff className="h-4 w-4" />
                  Skip Signature
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── BottomActions ──────────────────────────────────────────────────

export function BottomActions() {
  const { cartItems, resetAll, setShowCheckout, setShowSuccess, customer, discount, discountReason, meta, setMeta, sourceTicketId, setPosPinVerified } = useUnifiedPosStore();
  const queryClient = useQueryClient();
  const isTraining = useIsTraining();
  const [cashModal, setCashModal] = useState<'in' | 'out' | null>(null);
  const [creatingTicket, setCreatingTicket] = useState(false);
  const [pinAction, setPinAction] = useState<'ticket' | 'checkout' | 'manager' | null>(null);
  const [managerVerified, setManagerVerified] = useState(false);
  // Tracks the cart total (cents) at the moment manager approval was granted.
  // If the cart grows past this amount, re-approval is required.
  const approvedAtCentsRef = useRef<number>(0);
  const { getSetting } = useSettings();

  // Audit §43.12: manager PIN on high-value sales. Threshold is cents,
  // stored in store_config.pos_manager_pin_threshold. 0 / null disables.
  const managerThresholdCents = Number(getSetting('pos_manager_pin_threshold') ?? '50000');
  const cartTotalCents = useMemo(() => {
    let cents = 0;
    for (const item of cartItems) {
      if (item.type === 'repair') {
        cents += Math.round(((item.laborPrice || 0) - (item.lineDiscount || 0)) * 100);
        for (const p of item.parts) cents += Math.round((p.price || 0) * (p.quantity || 1) * 100);
      } else if (item.type === 'product') {
        cents += Math.round((item.unitPrice || 0) * (item.quantity || 1) * 100);
      } else if (item.type === 'misc') {
        cents += Math.round((item.unitPrice || 0) * (item.quantity || 1) * 100);
      }
    }
    return cents;
  }, [cartItems]);
  // Reset manager approval when the cart grows beyond the amount that was approved.
  useEffect(() => {
    if (managerVerified && cartTotalCents > approvedAtCentsRef.current) {
      setManagerVerified(false);
      approvedAtCentsRef.current = 0;
    }
  }, [cartTotalCents, managerVerified]);

  const needsManagerPin =
    managerThresholdCents > 0 && cartTotalCents >= managerThresholdCents && !managerVerified;

  // BlockChyp status
  const { data: bcStatus } = useQuery({
    queryKey: ['blockchyp-status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 30_000,
  });
  const bcEnabled = bcStatus?.data?.data?.enabled ?? false;
  const bcTcEnabled = bcStatus?.data?.data?.tcEnabled ?? false;
  const requireSignature = bcEnabled && bcTcEnabled;

  // Signature gate state
  const [sigModal, setSigModal] = useState(false);
  const [sigState, setSigState] = useState<SigModalState>('pending');
  const [sigError, setSigError] = useState('');
  const [sigFile, setSigFile] = useState<string | null>(null);

  const hasItems = cartItems.length > 0;
  const hasRepair = cartItems.some((i) => i.type === 'repair');

  const requirePinSale = getSetting('pos_require_pin_sale') === '1';
  const requirePinTicket = getSetting('pos_require_pin_ticket') === '1';
  const requireReferral = getSetting('pos_require_referral') === '1' || getSetting('pos_require_referral') === 'true';

  const { data: referralSourcesData } = useQuery({
    queryKey: ['settings', 'referral-sources'],
    queryFn: () => settingsApi.getReferralSources(),
    enabled: requireReferral && hasRepair,
    staleTime: 60_000,
  });
  const referralSources: Array<{ id: number; name: string }> =
    referralSourcesData?.data?.data?.referral_sources || referralSourcesData?.data?.data || [];

  // pinVerifiedRef is kept for the create-ticket path (no store read needed);
  // checkout path uses store.posPinVerified so CheckoutModal can read it.
  const pinVerifiedRef = useRef(false);

  const handleCancel = async () => {
    if (hasItems || customer) {
      if (!await confirm('Clear the cart and selected customer, and start over?')) return;
    }
    resetAll();
  };

  const buildTicketPayload = (signatureFile?: string | null) => {
    const repairs = cartItems.filter((i): i is RepairCartItem => i.type === 'repair');
    const devices = repairs.map((r) => ({
      device_type: r.device.device_type,
      device_name: r.device.device_name,
      device_model_id: r.device.device_model_id,
      imei: r.device.imei,
      serial: r.device.serial,
      security_code: r.device.security_code,
      color: r.device.color,
      network: r.device.network,
      pre_conditions: r.device.pre_conditions,
      additional_notes: r.device.additional_notes,
      device_location: r.device.device_location,
      warranty: r.device.warranty,
      warranty_days: r.device.warranty_days,
      service_name: r.serviceName,
      repair_service_id: r.repairServiceId,
      selected_grade_id: r.selectedGradeId,
      labor_price: r.laborPrice,
      line_discount: r.lineDiscount,
      parts: r.parts,
      taxable: r.taxable,
      due_on: r.device.due_date ?? null,
    }));

    return {
      mode: 'create_ticket' as const,
      customer_id: customer !== null ? customer.id : null,
      signature_file: signatureFile ?? undefined,
      ticket: {
        devices,
        source: meta.source,
        referral_source: meta.referralSource || undefined,
        assigned_to: meta.assignedTo,
        discount,
        discount_reason: discountReason,
        internal_notes: meta.internalNotes,
        labels: meta.labels,
        due_date: meta.dueDate,
      },
      product_items: [],
      misc_items: [],
      payment_method: null,
      payment_amount: 0,
    };
  };

  const doCreateTicket = async (signatureFile?: string | null) => {
    const repairs = cartItems.filter((i): i is RepairCartItem => i.type === 'repair');
    if (repairs.length === 0) return;
    // Allow walk-in (id === 0) and any real customer id. Only block when customer is null.
    if (customer === null) {
      toast.error('Please select or create a customer first');
      return;
    }
    if (requireReferral && !meta.referralSource) {
      toast.error('Select a referral source');
      return;
    }

    setCreatingTicket(true);
    try {
      const payload = buildTicketPayload(signatureFile);
      if (isTraining) {
        await submitTrainingTransaction({
          cart: payload,
          total_cents: cartTotalCents,
          kind: 'create_ticket',
        });
        await queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
        await queryClient.invalidateQueries({ queryKey: ['onboarding', 'state'] });
        setShowSuccess({
          mode: 'create_ticket',
          ticket: {
            id: 0,
            order_id: 'TRAINING',
            c_first_name: 'Training',
            c_last_name: 'Session',
            devices: payload.ticket.devices.map((device, index) => ({
              id: index + 1,
              device_name: device.device_name,
              device_type: device.device_type,
              service_name: device.service_name,
            })),
          },
          total: cartTotalCents / 100,
          customer_name: 'Training session',
        });
        window.dispatchEvent(new CustomEvent('pos:ticket-saved'));
        return;
      }
      // WEB-FH-001 / WEB-FH-002: same stable cart-session idempotency key
      // as the checkout path — covers the create-ticket-without-payment
      // double-submit case (button click + keyboard Enter race).
      const idempotencyKey = useUnifiedPosStore.getState().ensureIdempotencyKey();
      const pv = pinVerifiedRef.current;
      pinVerifiedRef.current = false; // consume once
      const res = await posApi.checkoutWithTicket(payload, idempotencyKey, pv);
      setShowSuccess({ ...res.data.data, mode: 'create_ticket' });
      // Advance the ticket tutorial when a ticket is successfully saved.
      window.dispatchEvent(new CustomEvent('pos:ticket-saved'));
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : 'Failed to create ticket');
    } finally {
      setCreatingTicket(false);
    }
  };

  const fireSignatureCapture = () => {
    setSigModal(true);
    setSigState('pending');
    setSigError('');
    setSigFile(null);
    blockchypApi.captureCheckinSignature()
      .then((res) => {
        const result = res.data?.data;
        if (result?.success) {
          setSigState('done');
          setSigFile(result.signatureFile ?? null);
        } else {
          setSigState('error');
          setSigError(result?.error ?? 'Customer declined or terminal error');
        }
      })
      .catch((err: unknown) => {
        setSigState('error');
        setSigError(err instanceof Error ? err.message : 'Signature capture failed');
      });
  };

  const handleCreateTicketFlow = () => {
    const repairs = cartItems.filter((i): i is RepairCartItem => i.type === 'repair');
    if (repairs.length === 0) return;
    // Allow walk-in (id === 0) and any real customer id. Only block when customer is null.
    if (customer === null) {
      toast.error('Please select or create a customer first');
      return;
    }

    if (requireSignature) {
      fireSignatureCapture();
    } else {
      doCreateTicket();
    }
  };

  return (
    <>
      <div className="flex items-center justify-end gap-4 border-t border-surface-200 bg-white px-5 py-4 dark:border-surface-700 dark:bg-surface-900">
        {/* Left utility buttons */}
        <div className="flex items-center gap-3">
          <button
            onClick={handleCancel}
            className="btn btn-lg border border-red-300 !px-5 text-red-600 hover:bg-red-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-red-500 dark:border-red-500/30 dark:text-red-400 dark:hover:bg-red-500/10"
          >
            Cancel
          </button>
          <button
            onClick={async () => {
              try {
                await posApi.openDrawer();
                toast.success('Drawer command sent — verify the drawer opened');
              } catch {
                toast.error('Failed to open drawer');
              }
            }}
            className="btn btn-lg border border-surface-300 text-surface-600 hover:bg-surface-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-surface-400 dark:border-surface-600 dark:text-surface-400 dark:hover:bg-surface-800"
            title="Open cash drawer"
          >
            <LockOpen className="h-4 w-4" />
            Open Drawer
          </button>
          {/* Audit §43.4/§43.8: cash drawer shift controls + Z-report */}
          <CashDrawerWidget />
        </div>
        <div className="flex items-center gap-4">
          {requireReferral && hasRepair && !sourceTicketId && (
            <select
              value={meta.referralSource}
              onChange={(e) => setMeta({ referralSource: e.target.value })}
              aria-label="Referral source"
              className="h-10 w-44 rounded-lg border border-surface-300 bg-white px-3 text-sm text-surface-800 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
            >
              <option value="">Referral source...</option>
              {referralSources.map((src) => (
                <option key={src.id} value={src.name}>{src.name}</option>
              ))}
            </select>
          )}
          <button
            data-tutorial-target="ticket:save-ticket-button"
            onClick={() => {
              if (requirePinTicket) { setPinAction('ticket'); return; }
              handleCreateTicketFlow();
            }}
            disabled={!hasRepair || creatingTicket || !!sourceTicketId}
            title={sourceTicketId ? 'Checking out existing ticket — use Checkout' : !hasRepair ? 'Add a repair to create ticket' : ''}
            className={cn(
              'btn btn-lg border !px-8 !font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-surface-400 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
              hasRepair && !sourceTicketId
                ? 'border-surface-300 text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800'
                : 'border-surface-200 text-surface-400 dark:border-surface-700 dark:text-surface-500',
            )}
          >
            {creatingTicket ? 'Creating...' : 'Create Ticket'}
          </button>
          <button
            data-tutorial-target="checkout:checkout-button"
            onClick={() => {
              if (customer === null && cartItems.some(i => i.type === 'repair')) {
                toast.error('Please select or create a customer first');
                return;
              }
              if (requireReferral && cartItems.some(i => i.type === 'repair') && !meta.referralSource) {
                toast.error('Select a referral source');
                return;
              }
              // Audit §43.12 — manager PIN on high-value sales, threshold in
              // store_config.pos_manager_pin_threshold. Checked first so it
              // nests with the existing cashier-PIN and signature gates.
              if (needsManagerPin) { setPinAction('manager'); return; }
              if (requirePinSale) { setPinAction('checkout'); return; }
              setShowCheckout(true);
            }}
            disabled={!hasItems}
            title={needsManagerPin ? `Manager PIN required (>${(managerThresholdCents / 100).toFixed(0)})` : !hasItems ? 'Add items to cart first' : ''}
            className={cn(
              'btn btn-lg !px-6 !font-semibold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-teal-500 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
              hasItems
                ? 'bg-teal-600 text-white hover:bg-teal-700'
                : 'bg-surface-200 text-surface-400 dark:bg-surface-700 dark:text-surface-500',
            )}
          >
            Checkout
          </button>
        </div>
      </div>

      {cashModal && <CashModal type={cashModal} onClose={() => setCashModal(null)} />}
      {pinAction && pinAction !== 'manager' && (
        <PinModal
          title={pinAction === 'ticket' ? 'PIN required to create ticket' : 'PIN required for checkout'}
          onSuccess={() => {
            const action = pinAction;
            pinVerifiedRef.current = true; // for create-ticket path
            setPosPinVerified(true);       // for checkout path (CheckoutModal reads store)
            setPinAction(null);
            if (action === 'ticket') handleCreateTicketFlow();
            else setShowCheckout(true);
          }}
          onCancel={() => setPinAction(null)}
        />
      )}
      {pinAction === 'manager' && (
        <ManagerPinModal
          saleCents={cartTotalCents}
          thresholdCents={managerThresholdCents}
          onSuccess={() => {
            approvedAtCentsRef.current = cartTotalCents;
            setPinAction(null);
            setManagerVerified(true);
            if (requirePinSale) { setPinAction('checkout'); return; }
            setShowCheckout(true);
          }}
          onCancel={() => setPinAction(null)}
        />
      )}
      {sigModal && (
        <SignatureGateModal
          state={sigState}
          error={sigError}
          signatureFile={sigFile}
          onRetry={fireSignatureCapture}
          onBypass={() => {
            setSigModal(false);
            doCreateTicket();
          }}
          onCancel={() => setSigModal(false)}
          onProceed={() => {
            setSigModal(false);
            doCreateTicket(sigFile);
          }}
        />
      )}
    </>
  );
}

// ─── ManagerPinModal ────────────────────────────────────────────────────────
// Audit §43.12 — inline manager-PIN gate for high-value sales. Posts to
// /pos-enrich/manager-verify-pin which only accepts PINs of active users
// whose role is admin/manager/owner (server-side enforcement, bcrypt-checked).

interface ManagerPinModalProps {
  saleCents: number;
  thresholdCents: number;
  onSuccess: () => void;
  onCancel: () => void;
}

function ManagerPinModal({ saleCents, thresholdCents, onSuccess, onCancel }: ManagerPinModalProps) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [verifying, setVerifying] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pin.trim() || verifying) return;
    setVerifying(true);
    setError('');
    try {
      await api.post('/pos-enrich/manager-verify-pin', { pin, sale_cents: saleCents });
      onSuccess();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Invalid manager PIN');
      setPin('');
    } finally {
      setVerifying(false);
    }
  };

  // WEB-FX-003: Esc cancels unless mid-verify.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !verifying) onCancel();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onCancel, verifying]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      onClick={(e) => {
        if (e.target === e.currentTarget && !verifying) onCancel();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="manager-pin-title"
        className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 id="manager-pin-title" className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Manager PIN required
          </h3>
          <button aria-label="Close" onClick={onCancel} className="btn-icon btn-xs">
            <X className="h-4 w-4" />
          </button>
        </div>
        <form onSubmit={submit} className="space-y-3 p-5">
          <p className="text-xs text-surface-600 dark:text-surface-400">
            Sale total ${(saleCents / 100).toFixed(2)} exceeds the high-value threshold
            of ${(thresholdCents / 100).toFixed(2)}. A manager must approve this transaction.
          </p>
          <input
            type="password"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={10}
            value={pin}
            autoFocus
            onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); setError(''); }}
            placeholder="Manager PIN"
            className="w-full rounded-lg border border-surface-300 px-3 py-2 text-center text-xl tracking-[0.4em] focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
          />
          {error && <p role="alert" aria-live="polite" className="text-center text-xs text-red-500">{error}</p>}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onCancel}
              className="btn btn-sm flex-1 border border-surface-300 text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!pin.trim() || verifying}
              className="btn btn-sm flex-1 bg-teal-600 text-white hover:bg-teal-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {verifying ? 'Verifying…' : 'Approve'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
