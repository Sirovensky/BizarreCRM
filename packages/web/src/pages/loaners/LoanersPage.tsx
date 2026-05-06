import { useEffect, useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, Package, CheckCircle2, AlertCircle, X, Plus, Search, ChevronLeft, ChevronRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { loanerApi, type LoanerDevice } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDate } from '@/utils/format';

// ─── Return Dialog ─────────────────────────────────────────────────────────

interface ReturnDialogProps {
  device: LoanerDevice;
  onClose: () => void;
}

function ReturnDialog({ device, onClose }: ReturnDialogProps) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [conditionIn, setConditionIn] = useState('good');
  const [damageNotes, setDamageNotes] = useState('');
  const [chargeAmount, setChargeAmount] = useState('');
  const [chargePaymentState, setChargePaymentState] = useState<'due' | 'paid'>('due');
  const [paymentMethod, setPaymentMethod] = useState('cash');
  const [paymentReference, setPaymentReference] = useState('');

  const requiresCharge = conditionIn === 'damaged' || conditionIn === 'missing';
  const chargeInput = chargeAmount.trim();
  const parsedCharge = chargeInput ? Number.parseFloat(chargeInput) : 0;
  const chargeInvalid = chargeInput.length > 0 && (!Number.isFinite(parsedCharge) || parsedCharge < 0);
  const normalizedCharge = !chargeInvalid ? Math.round(parsedCharge * 100) / 100 : 0;
  const hasCharge = normalizedCharge > 0;
  const referenceMissing = hasCharge && chargePaymentState === 'paid' && paymentMethod === 'external_terminal' && !paymentReference.trim();

  const returnMutation = useMutation({
    mutationFn: () => {
      return loanerApi.returnDevice(device.id, {
        condition_in: conditionIn,
        notes: damageNotes.trim() || undefined,
        return_charge_amount: hasCharge ? normalizedCharge : undefined,
        return_charge_paid: hasCharge && chargePaymentState === 'paid',
        return_charge_payment_method: hasCharge && chargePaymentState === 'paid' ? paymentMethod : undefined,
        return_charge_payment_reference: hasCharge && chargePaymentState === 'paid' && paymentReference.trim()
          ? paymentReference.trim()
          : undefined,
      });
    },
    onSuccess: (response) => {
      queryClient.invalidateQueries({ queryKey: ['loaners'] });
      const charge = response.data?.data?.return_charge;
      if (charge) {
        const message = charge.status === 'paid'
          ? `${device.name} returned. Payment recorded on invoice ${charge.invoice_order_id}.`
          : `${device.name} returned. Invoice ${charge.invoice_order_id} created for return fee.`;
        toast.success(message, { duration: 7000 });
        navigate(`/invoices/${charge.invoice_id}`);
      } else {
        toast.success(`${device.name} marked as returned`);
      }
      onClose();
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to mark device as returned');
    },
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  const submitDisabled = returnMutation.isPending || chargeInvalid || referenceMissing;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="loaner-return-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 id="loaner-return-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Mark Returned</h2>
          <button aria-label="Close" onClick={onClose} className="rounded p-1 text-surface-400 hover:text-surface-600">
            <X className="h-4 w-4" />
          </button>
        </div>
        <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
          Returning <span className="font-semibold text-surface-900 dark:text-surface-100">{device.name}</span>
          {device.loaned_to ? ` from ${device.loaned_to}` : ''}.
        </p>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Return Condition
            </label>
            <select
              value={conditionIn}
              onChange={(e) => setConditionIn(e.target.value)}
              className="input w-full"
            >
              <option value="good">Good</option>
              <option value="fair">Fair</option>
              <option value="damaged">Damaged</option>
              <option value="missing">Missing parts</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Damage Notes <span className="text-surface-400 font-normal">(optional)</span>
            </label>
            <textarea
              value={damageNotes}
              onChange={(e) => setDamageNotes(e.target.value)}
              rows={3}
              className="input w-full resize-none"
              placeholder="Describe any damage or missing items..."
            />
          </div>
          <div
            className={cn(
              'rounded-md border p-3 text-xs space-y-3',
              requiresCharge
                ? 'border-amber-300 bg-amber-50 text-amber-800 dark:bg-amber-900/20 dark:border-amber-700 dark:text-amber-200'
                : 'border-surface-200 bg-surface-50 text-surface-700 dark:border-surface-700 dark:bg-surface-800/60 dark:text-surface-300',
            )}
          >
            <div className="flex items-center justify-between gap-3">
              <p className="font-semibold">Return fee</p>
              {requiresCharge && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-700 dark:bg-amber-900/40 dark:text-amber-200">Review needed</span>}
            </div>
            <label className="block" htmlFor="loaner-return-charge-amount">
              <span className="block text-[11px] font-medium mb-1">Amount (USD)</span>
              <input
                id="loaner-return-charge-amount"
                type="number"
                inputMode="decimal"
                min="0"
                step="0.01"
                value={chargeAmount}
                onChange={(e) => setChargeAmount(e.target.value)}
                placeholder="0.00"
                aria-invalid={chargeInvalid}
                aria-describedby={chargeInvalid ? 'loaner-return-charge-error' : undefined}
                className={cn('input w-full', chargeInvalid && 'border-red-500 dark:border-red-500')}
              />
            </label>
            {chargeInvalid && <p id="loaner-return-charge-error" className="text-xs text-red-600 dark:text-red-300">Enter a non-negative amount.</p>}
            {hasCharge && (
              <>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    type="button"
                    onClick={() => setChargePaymentState('due')}
                    className={cn(
                      'rounded-md border px-3 py-2 text-xs font-medium transition-colors',
                      chargePaymentState === 'due'
                        ? 'border-primary-500 bg-primary-50 text-primary-700 dark:bg-primary-900/20 dark:text-primary-200'
                        : 'border-surface-200 bg-white text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300',
                    )}
                  >
                    Invoice due
                  </button>
                  <button
                    type="button"
                    onClick={() => setChargePaymentState('paid')}
                    className={cn(
                      'rounded-md border px-3 py-2 text-xs font-medium transition-colors',
                      chargePaymentState === 'paid'
                        ? 'border-primary-500 bg-primary-50 text-primary-700 dark:bg-primary-900/20 dark:text-primary-200'
                        : 'border-surface-200 bg-white text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300',
                    )}
                  >
                    Payment collected
                  </button>
                </div>
                {chargePaymentState === 'paid' && (
                  <div className="grid gap-3 sm:grid-cols-2">
                    <label className="block" htmlFor="loaner-return-payment-method">
                      <span className="block text-[11px] font-medium mb-1">Method</span>
                      <select
                        id="loaner-return-payment-method"
                        value={paymentMethod}
                        onChange={(e) => setPaymentMethod(e.target.value)}
                        className="input w-full"
                      >
                        <option value="cash">Cash</option>
                        <option value="check">Check</option>
                        <option value="external_terminal">External terminal</option>
                        <option value="other">Other</option>
                      </select>
                    </label>
                    <label className="block" htmlFor="loaner-return-payment-reference">
                      <span className="block text-[11px] font-medium mb-1">Reference</span>
                      <input
                        id="loaner-return-payment-reference"
                        value={paymentReference}
                        onChange={(e) => setPaymentReference(e.target.value)}
                        placeholder={paymentMethod === 'external_terminal' ? 'Required' : 'Optional'}
                        aria-invalid={referenceMissing}
                        aria-describedby={referenceMissing ? 'loaner-return-reference-error' : undefined}
                        className={cn('input w-full', referenceMissing && 'border-red-500 dark:border-red-500')}
                      />
                    </label>
                    {referenceMissing && (
                      <p id="loaner-return-reference-error" className="sm:col-span-2 text-xs text-red-600 dark:text-red-300">
                        Enter the terminal receipt or authorization reference.
                      </p>
                    )}
                  </div>
                )}
              </>
            )}
          </div>
        </div>
        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={() => returnMutation.mutate()}
            disabled={submitDisabled}
            className="flex-1 px-4 py-2.5 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {returnMutation.isPending ? 'Returning...' : 'Confirm Return'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Add Loaner Dialog ─────────────────────────────────────────────────────

function AddLoanerDialog({ onClose }: { onClose: () => void }) {
  const queryClient = useQueryClient();
  const [name, setName] = useState('');
  const [serial, setSerial] = useState('');
  const [imei, setImei] = useState('');
  const [condition, setCondition] = useState('good');
  const [notes, setNotes] = useState('');
  const [nameError, setNameError] = useState('');

  const createMutation = useMutation({
    mutationFn: () => loanerApi.create({
      name: name.trim(),
      serial: serial.trim() || undefined,
      imei: imei.trim() || undefined,
      condition,
      notes: notes.trim() || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['loaners'] });
      toast.success('Loaner device added');
      onClose();
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to add loaner device');
    },
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) {
      setNameError('Name is required');
      return;
    }
    setNameError('');
    createMutation.mutate();
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-loaner-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-sm p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 id="add-loaner-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Add Loaner Device</h2>
          <button aria-label="Close" onClick={onClose} className="rounded p-1 text-surface-400 hover:text-surface-600">
            <X className="h-4 w-4" />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="loaner-name" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Device Name <span className="text-red-500">*</span>
            </label>
            <input
              id="loaner-name"
              value={name}
              onChange={(e) => { setName(e.target.value); if (nameError) setNameError(''); }}
              placeholder="e.g. iPhone 11 Loaner"
              aria-invalid={!!nameError}
              aria-describedby={nameError ? 'loaner-name-error' : undefined}
              className={cn('input w-full', nameError && 'border-red-500 dark:border-red-500')}
              autoFocus
            />
            {nameError && <p id="loaner-name-error" className="mt-1 text-xs text-red-500">{nameError}</p>}
          </div>
          <div>
            <label htmlFor="loaner-condition" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Condition
            </label>
            <select
              id="loaner-condition"
              value={condition}
              onChange={(e) => setCondition(e.target.value)}
              className="input w-full"
            >
              <option value="good">Good</option>
              <option value="fair">Fair</option>
              <option value="poor">Poor</option>
            </select>
          </div>
          <div>
            <label htmlFor="loaner-serial" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Serial <span className="text-surface-400 font-normal">(optional)</span>
            </label>
            <input
              id="loaner-serial"
              value={serial}
              onChange={(e) => setSerial(e.target.value)}
              placeholder="Serial number"
              className="input w-full"
            />
          </div>
          <div>
            <label htmlFor="loaner-imei" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              IMEI <span className="text-surface-400 font-normal">(optional)</span>
            </label>
            <input
              id="loaner-imei"
              value={imei}
              onChange={(e) => setImei(e.target.value)}
              placeholder="IMEI"
              className="input w-full"
            />
          </div>
          <div>
            <label htmlFor="loaner-notes" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Notes <span className="text-surface-400 font-normal">(optional)</span>
            </label>
            <textarea
              id="loaner-notes"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={2}
              className="input w-full resize-none"
              placeholder="Any notes about this device..."
            />
          </div>
          <div className="flex gap-3 mt-6">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={createMutation.isPending}
              className="flex-1 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-primary-950 rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {createMutation.isPending ? 'Adding...' : 'Add Device'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Page ─────────────────────────────────────────────────────────────

const LOANER_FETCH_PAGE_SIZE = 100;
const LOANER_GRID_PAGE_SIZE = 24;

type LoanerStatusFilter = 'all' | 'available' | 'loaned';

function isLoanedOut(device: LoanerDevice) {
  return device.status === 'loaned' || !!device.is_loaned_out;
}

export function LoanersPage() {
  const [returningDevice, setReturningDevice] = useState<LoanerDevice | null>(null);
  const [showAddDialog, setShowAddDialog] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<LoanerStatusFilter>('all');
  const [page, setPage] = useState(1);

  const { data, isLoading } = useQuery({
    queryKey: ['loaners'],
    queryFn: async () => {
      const firstPage = await loanerApi.list({ page: 1, per_page: LOANER_FETCH_PAGE_SIZE });
      const totalPages = firstPage.data.pagination.total_pages;

      if (totalPages <= 1) {
        return firstPage;
      }

      const remainingPages = await Promise.all(
        Array.from({ length: totalPages - 1 }, (_, index) => (
          loanerApi.list({ page: index + 2, per_page: LOANER_FETCH_PAGE_SIZE })
        )),
      );

      return {
        ...firstPage,
        data: {
          ...firstPage.data,
          data: [
            ...firstPage.data.data,
            ...remainingPages.flatMap((response) => response.data.data),
          ],
        },
      };
    },
    staleTime: 30_000,
  });

  const devices: LoanerDevice[] = data?.data?.data ?? [];
  const totalDevices = data?.data?.pagination.total ?? devices.length;
  const statusCounts = useMemo(() => {
    return devices.reduce(
      (counts, device) => {
        if (isLoanedOut(device)) {
          counts.loaned += 1;
        } else {
          counts.available += 1;
        }
        return counts;
      },
      { available: 0, loaned: 0 },
    );
  }, [devices]);

  const filteredDevices = useMemo(() => {
    const query = searchTerm.trim().toLowerCase();

    return devices.filter((device) => {
      const out = isLoanedOut(device);
      if (statusFilter === 'available' && out) return false;
      if (statusFilter === 'loaned' && !out) return false;
      if (!query) return true;

      return [
        device.name,
        device.serial,
        device.imei,
        device.condition,
        device.loaned_to,
        device.notes,
      ].some((value) => value?.toLowerCase().includes(query));
    });
  }, [devices, searchTerm, statusFilter]);

  const totalFilteredPages = Math.max(1, Math.ceil(filteredDevices.length / LOANER_GRID_PAGE_SIZE));
  const currentPage = Math.min(page, totalFilteredPages);
  const firstResult = filteredDevices.length > 0 ? (currentPage - 1) * LOANER_GRID_PAGE_SIZE + 1 : 0;
  const lastResult = Math.min(currentPage * LOANER_GRID_PAGE_SIZE, filteredDevices.length);
  const visibleDevices = filteredDevices.slice(firstResult > 0 ? firstResult - 1 : 0, lastResult);

  useEffect(() => {
    setPage(1);
  }, [searchTerm, statusFilter]);

  useEffect(() => {
    setPage((current) => Math.min(current, totalFilteredPages));
  }, [totalFilteredPages]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Loaner Devices</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
            Track devices loaned to customers during repairs.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setShowAddDialog(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700 shrink-0"
        >
          <Plus className="h-4 w-4" /> Add Loaner
        </button>
      </div>

      {devices.length > 0 && (
        <div className="mb-5 flex flex-col gap-3 rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-700 dark:bg-surface-900 lg:flex-row lg:items-center lg:justify-between">
          <label htmlFor="loaner-search" className="relative block flex-1">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              id="loaner-search"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search name, serial, IMEI, customer, notes..."
              aria-label="Search loaner devices"
              className="input w-full pl-9"
            />
          </label>
          <div className="flex flex-wrap gap-2" role="group" aria-label="Loaner status filter">
            {([
              ['all', `All ${totalDevices}`],
              ['available', `Available ${statusCounts.available}`],
              ['loaned', `Loaned ${statusCounts.loaned}`],
            ] as const).map(([value, label]) => (
              <button
                key={value}
                type="button"
                onClick={() => setStatusFilter(value)}
                aria-pressed={statusFilter === value}
                className={cn(
                  'rounded-md border px-3 py-2 text-sm font-medium transition-colors',
                  statusFilter === value
                    ? 'border-primary-500 bg-primary-50 text-primary-700 dark:bg-primary-900/20 dark:text-primary-200'
                    : 'border-surface-200 bg-white text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300 dark:hover:bg-surface-800',
                )}
              >
                {label}
              </button>
            ))}
          </div>
        </div>
      )}

      {devices.length === 0 ? (
        <div className="text-center py-20 text-surface-400">
          <Package className="h-12 w-12 mx-auto mb-3 opacity-30" />
          <p className="text-sm">No loaner devices configured.</p>
        </div>
      ) : filteredDevices.length === 0 ? (
        <div className="text-center py-20 text-surface-400">
          <Search className="h-12 w-12 mx-auto mb-3 opacity-30" />
          <p className="text-sm">No loaner devices match those filters.</p>
        </div>
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {visibleDevices.map((device) => {
              const isOut = isLoanedOut(device);
              return (
                <div
                  key={device.id}
                  className="card p-5 flex flex-col gap-3"
                >
                  {/* Header */}
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <Package className="h-5 w-5 flex-shrink-0 text-surface-400" />
                      <span className="font-semibold text-surface-900 dark:text-surface-100 truncate">
                        {device.name}
                      </span>
                    </div>
                    <span
                      className={cn(
                        'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium flex-shrink-0',
                        isOut
                          ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                          : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
                      )}
                    >
                      {isOut ? (
                        <><AlertCircle className="h-3 w-3" /> Loaned out</>
                      ) : (
                        <><CheckCircle2 className="h-3 w-3" /> Available</>
                      )}
                    </span>
                  </div>

                  {/* Details */}
                  <div className="text-xs text-surface-500 dark:text-surface-400 space-y-0.5">
                    <p>Condition: <span className="capitalize">{device.condition}</span></p>
                    {device.loaned_to && (
                      <p>Loaned to: <span className="font-medium text-surface-700 dark:text-surface-300">{device.loaned_to}</span></p>
                    )}
                    {device.notes && <p className="truncate" title={device.notes}>Note: {device.notes}</p>}
                    <p>Updated: {formatDate(device.updated_at)}</p>
                  </div>

                  {/* Action */}
                  {isOut && (
                    <button
                      type="button"
                      onClick={() => setReturningDevice(device)}
                      className="mt-auto inline-flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium rounded-lg bg-green-600 hover:bg-green-700 text-white transition-colors"
                    >
                      <CheckCircle2 aria-hidden="true" className="h-4 w-4" /> Mark Returned
                    </button>
                  )}
                </div>
              );
            })}
          </div>
          <div className="mt-5 flex flex-col gap-3 rounded-lg border border-surface-200 bg-white px-4 py-3 dark:border-surface-700 dark:bg-surface-900 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-surface-500 dark:text-surface-400">
              Showing {firstResult}-{lastResult} of {filteredDevices.length}
              {filteredDevices.length !== totalDevices && ` filtered from ${totalDevices}`}
            </p>
            {totalFilteredPages > 1 && (
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setPage((value) => Math.max(1, value - 1))}
                  disabled={currentPage <= 1}
                  className="inline-flex items-center gap-1 rounded-md border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
                >
                  <ChevronLeft className="h-4 w-4" />
                  Previous
                </button>
                <span className="text-sm text-surface-500 dark:text-surface-400">
                  Page {currentPage} of {totalFilteredPages}
                </span>
                <button
                  type="button"
                  onClick={() => setPage((value) => Math.min(totalFilteredPages, value + 1))}
                  disabled={currentPage >= totalFilteredPages}
                  className="inline-flex items-center gap-1 rounded-md border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
                >
                  Next
                  <ChevronRight className="h-4 w-4" />
                </button>
              </div>
            )}
          </div>
        </>
      )}

      {returningDevice && (
        <ReturnDialog device={returningDevice} onClose={() => setReturningDevice(null)} />
      )}
      {showAddDialog && (
        <AddLoanerDialog onClose={() => setShowAddDialog(false)} />
      )}
    </div>
  );
}
