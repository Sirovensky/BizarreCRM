import { useEffect, useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Trash2, Pencil, DollarSign, Search, Loader2, X, ChevronLeft, ChevronRight, Receipt, Paperclip, ExternalLink } from 'lucide-react';
import toast from 'react-hot-toast';
import { expenseApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';

// FF-012: previously the form pre-filled `new Date().toISOString().slice(0,10)`
// which returns the *UTC* day. After ~4-5pm local in any timezone west of UTC
// the picker showed tomorrow's date — staff entering an expense at 7pm PST
// would record it on the next day. Build a YYYY-MM-DD string in the user's
// local timezone instead so the picker always matches the wall clock.
function localToday(): string {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

const EXPENSE_CATEGORIES = [
  'Rent', 'Utilities', 'Parts & Supplies', 'Tools & Equipment', 'Marketing',
  'Insurance', 'Payroll', 'Software', 'Office Supplies', 'Shipping',
  'Travel', 'Maintenance', 'Taxes & Fees', 'Other',
] as const;

interface ExpenseFormPayload {
  category: string;
  amount: number;
  description?: string;
  date?: string;
  location_id?: number;
}

// Row returned by `GET /expenses`. Permissive on amount (server sends number
// but stored as string in some legacy rows) + optional joined first/last name.
interface ExpenseRow {
  id: number;
  category: string;
  amount: number | string;
  description?: string | null;
  date?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  location_id?: number | null;
  // WEB-FK-014: receipt path stored by expenseReceipts.routes.ts
  receipt_image_path?: string | null;
  [key: string]: unknown;
}

export function ExpensesPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [keyword, setKeyword] = useState('');
  const [catFilter, setCatFilter] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);

  const [form, setForm] = useState({ category: 'Other', amount: '', description: '', date: localToday() });
  // WEB-FK-014: pending receipt file selected in the edit form.
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const receiptInputRef = useRef<HTMLInputElement | null>(null);
  // WEB-FF-007 (Fixer-A2 2026-04-25): track field-level errors so screen
  // readers get aria-invalid + aria-describedby on bad inputs instead of a
  // toast.error that's invisible to AT.
  const [fieldErrors, setFieldErrors] = useState<{ amount?: string; category?: string; date?: string }>({});
  const [deleteTarget, setDeleteTarget] = useState<number | null>(null);

  const searchRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [searchInput, setSearchInput] = useState('');

  // WEB-FC-018 (FIXED-by-Fixer-A23 2026-04-25): the form now renders as a
  // dimmed-backdrop modal overlay instead of an inline panel above the
  // table. Editing a row on page 3 no longer scrolls the user to the top
  // and loses the row context; on mobile the dim overlay makes the form
  // a clear focused affordance instead of full-viewport with no chrome.
  // First field is autofocused on open for keyboard users + Esc closes.
  const firstFieldRef = useRef<HTMLSelectElement | null>(null);
  useEffect(() => {
    if (!showAdd) return;
    const t = setTimeout(() => {
      firstFieldRef.current?.focus({ preventScroll: true });
    }, 0);
    return () => clearTimeout(t);
  }, [showAdd, editingId]);
  // Esc closes the modal — matches CheckoutModal / ConfirmDialog pattern.
  useEffect(() => {
    if (!showAdd) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setShowAdd(false);
        setEditingId(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [showAdd]);

  const { data, isLoading } = useQuery({
    queryKey: ['expenses', page, keyword, catFilter],
    queryFn: () => expenseApi.list({ page, pagesize: 25, keyword: keyword || undefined, category: catFilter || undefined }),
    staleTime: 30_000,
  });

  const expenses: ExpenseRow[] = Array.isArray(data?.data?.data?.expenses)
    ? (data?.data?.data?.expenses as ExpenseRow[])
    : [];
  const pagination = data?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1 };
  const summary = data?.data?.data?.summary || { total_amount: 0, total_count: 0 };
  const categories = data?.data?.data?.categories || [];

  const createMut = useMutation({
    mutationFn: (d: ExpenseFormPayload) => editingId ? expenseApi.update(editingId, d) : expenseApi.create(d),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      toast.success(editingId ? 'Expense updated' : 'Expense added');
      // WEB-FK-014: upload receipt if a file was selected. For new expenses
      // the route needs the just-created expense id from the response.
      const savedId: number | undefined = editingId ?? (res?.data?.data as any)?.id;
      if (receiptFile && savedId) {
        receiptMut.mutate({ id: savedId, file: receiptFile });
      }
      setShowAdd(false);
      setEditingId(null);
      setForm({ category: 'Other', amount: '', description: '', date: localToday() });
      setReceiptFile(null);
      if (receiptInputRef.current) receiptInputRef.current.value = '';
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => expenseApi.delete(id),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['expenses'] }); toast.success('Expense deleted'); },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to delete expense'),
  });

  // WEB-FK-014: receipt upload mutation — runs after save when a file is selected.
  const receiptMut = useMutation({
    mutationFn: ({ id, file }: { id: number; file: File }) => expenseApi.uploadReceipt(id, file),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      toast.success('Receipt uploaded');
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Receipt upload failed'),
  });

  const handleSubmit = () => {
    const errs: { amount?: string; category?: string; date?: string } = {};
    if (!form.amount || parseFloat(form.amount) <= 0) errs.amount = 'Valid amount required';
    if (!form.category) errs.category = 'Category required';
    // WEB-FK-013: belt-and-suspenders date guard — `max=` HTML attr is only a
    // browser hint; reject future-dated and pre-1900 expenses server-side too.
    if (form.date) {
      const today = localToday();
      if (form.date > today) errs.date = 'Date cannot be in the future';
      else if (form.date < '1900-01-01') errs.date = 'Date must be on or after 1900-01-01';
    }
    if (errs.amount || errs.category || errs.date) {
      setFieldErrors(errs);
      // Toast preserved for sighted users; AT users now also get the inline message.
      toast.error(errs.amount || errs.category || errs.date || 'Validation failed');
      return;
    }
    setFieldErrors({});
    createMut.mutate({ ...form, amount: parseFloat(form.amount) });
  };

  const handleEdit = (exp: ExpenseRow) => {
    setEditingId(exp.id);
    setForm({ category: exp.category, amount: String(exp.amount), description: exp.description || '', date: exp.date || '' });
    setReceiptFile(null);
    if (receiptInputRef.current) receiptInputRef.current.value = '';
    setShowAdd(true);
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Expenses</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Track business expenses</p>
        </div>
        <button
          onClick={() => { setEditingId(null); setForm({ category: 'Other', amount: '', description: '', date: localToday() }); setReceiptFile(null); if (receiptInputRef.current) receiptInputRef.current.value = ''; setShowAdd(true); }}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-primary-950 hover:bg-primary-700 transition-colors"
        >
          <Plus className="h-4 w-4" /> Add Expense
        </button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
        <div className="card p-4">
          <p className="text-xs font-medium text-surface-600 dark:text-surface-400">Total Expenses</p>
          <p className="text-lg font-bold text-surface-900 dark:text-surface-100">{formatCurrency(summary.total_amount)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs font-medium text-surface-600 dark:text-surface-400">Count</p>
          <p className="text-lg font-bold text-surface-900 dark:text-surface-100">{summary.total_count}</p>
        </div>
        {categories.slice(0, 2).map((c: any) => (
          <div key={c.category} className="card p-4">
            <p className="text-xs font-medium text-surface-600 dark:text-surface-400">{c.category}</p>
            <p className="text-lg font-bold text-surface-900 dark:text-surface-100">{formatCurrency(c.total)}</p>
          </div>
        ))}
      </div>

      {/* Filters */}
      <div className="card mb-4">
        <div className="p-3 flex flex-wrap gap-3 items-center">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
            <input
              value={searchInput}
              onChange={(e) => {
                setSearchInput(e.target.value);
                clearTimeout(searchRef.current);
                searchRef.current = setTimeout(() => { setKeyword(e.target.value); setPage(1); }, 400);
              }}
              placeholder="Search expenses..."
              className="w-full pl-9 pr-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
            />
          </div>
          <select
            value={catFilter}
            onChange={(e) => { setCatFilter(e.target.value); setPage(1); }}
            className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
          >
            <option value="">All Categories</option>
            {EXPENSE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </div>
      </div>

      {/* Add/Edit form — modal overlay (WEB-FC-018) */}
      {showAdd && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm"
          role="dialog"
          aria-modal="true"
          aria-label={editingId ? 'Edit expense form' : 'New expense form'}
          onMouseDown={(e) => {
            // Click-outside (on backdrop only) closes — do not fire when
            // dragging/clicking inside the form.
            if (e.target === e.currentTarget) {
              setShowAdd(false);
              setEditingId(null);
              setReceiptFile(null);
              if (receiptInputRef.current) receiptInputRef.current.value = '';
            }
          }}
        >
          <div className="w-full max-w-2xl rounded-xl bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-700 shadow-2xl p-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">
              {editingId ? 'Edit Expense' : 'New Expense'}
            </h3>
            <button
              type="button"
              onClick={() => { setShowAdd(false); setEditingId(null); setReceiptFile(null); if (receiptInputRef.current) receiptInputRef.current.value = ''; }}
              aria-label="Close"
              className="p-1 rounded-md text-surface-400 hover:text-surface-700 hover:bg-surface-100 dark:hover:bg-surface-800 dark:hover:text-surface-200"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <select ref={firstFieldRef} value={form.category} onChange={(e) => { setForm({ ...form, category: e.target.value }); if (fieldErrors.category) setFieldErrors((p) => ({ ...p, category: undefined })); }}
                aria-invalid={fieldErrors.category ? true : undefined}
                aria-describedby={fieldErrors.category ? 'expense-category-error' : undefined}
                className={`w-full px-3 py-2 text-sm border rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 ${fieldErrors.category ? 'border-red-400 dark:border-red-500' : 'border-surface-200 dark:border-surface-700'}`}>
                {EXPENSE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
              {fieldErrors.category && <p id="expense-category-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{fieldErrors.category}</p>}
            </div>
            <div>
              <input type="number" step="0.01" min="0" placeholder="Amount" value={form.amount}
                onChange={(e) => { setForm({ ...form, amount: e.target.value }); if (fieldErrors.amount) setFieldErrors((p) => ({ ...p, amount: undefined })); }}
                aria-invalid={fieldErrors.amount ? true : undefined}
                aria-describedby={fieldErrors.amount ? 'expense-amount-error' : undefined}
                className={`w-full px-3 py-2 text-sm border rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 ${fieldErrors.amount ? 'border-red-400 dark:border-red-500' : 'border-surface-200 dark:border-surface-700'}`} />
              {fieldErrors.amount && <p id="expense-amount-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{fieldErrors.amount}</p>}
            </div>
            {/* WEB-FK-013 (Fixer-B5 2026-04-25): clamp date input to [1900-01-01, today]
                so a stray keystroke can't record an expense dated 2099 (polluting next-
                year drill-downs forever) or 1700 (slipping past audit windows). */}
            <div>
              <input type="date" value={form.date} min="1900-01-01" max={localToday()}
                onChange={(e) => { setForm({ ...form, date: e.target.value }); if (fieldErrors.date) setFieldErrors((p) => ({ ...p, date: undefined })); }}
                aria-invalid={fieldErrors.date ? true : undefined}
                aria-describedby={fieldErrors.date ? 'expense-date-error' : undefined}
                className={`w-full px-3 py-2 text-sm border rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 ${fieldErrors.date ? 'border-red-400 dark:border-red-500' : 'border-surface-200 dark:border-surface-700'}`} />
              {fieldErrors.date && <p id="expense-date-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{fieldErrors.date}</p>}
            </div>
            <input type="text" placeholder="Description" value={form.description}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            {/* WEB-FK-014: receipt upload — attaches after save, uses expenseReceipts route */}
            <div className="sm:col-span-2">
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Receipt (image or PDF)
              </label>
              <input
                ref={receiptInputRef}
                type="file"
                accept="image/*,application/pdf"
                onChange={(e) => setReceiptFile(e.target.files?.[0] ?? null)}
                className="w-full text-sm text-surface-700 dark:text-surface-300 file:mr-3 file:py-1.5 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-medium file:bg-surface-100 file:text-surface-700 dark:file:bg-surface-700 dark:file:text-surface-300 hover:file:bg-surface-200 dark:hover:file:bg-surface-600"
              />
              {receiptFile && (
                <p className="mt-1 text-xs text-surface-500 flex items-center gap-1">
                  <Paperclip className="h-3 w-3" /> {receiptFile.name}
                </p>
              )}
            </div>
          </div>
          <div className="flex gap-2 mt-4 justify-end">
            <button type="button" onClick={() => { setShowAdd(false); setEditingId(null); setReceiptFile(null); if (receiptInputRef.current) receiptInputRef.current.value = ''; }} className="px-4 py-2 text-sm text-surface-500 hover:text-surface-700">Cancel</button>
            <button type="button" onClick={handleSubmit} disabled={createMut.isPending}
              className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-primary-600 text-primary-950 rounded-lg hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none">
              {createMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <DollarSign className="h-4 w-4" />}
              {editingId ? 'Update' : 'Add Expense'}
            </button>
          </div>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="card overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead className="bg-surface-50 dark:bg-surface-800/50">
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 font-medium text-surface-500">Date</th>
              <th className="px-4 py-3 font-medium text-surface-500">Category</th>
              <th className="px-4 py-3 font-medium text-surface-500">Description</th>
              <th className="px-4 py-3 font-medium text-surface-500">By</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Amount</th>
              <th className="px-4 py-3 font-medium text-surface-500">Receipt</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
            {isLoading ? (
              <tr><td colSpan={7} className="text-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400 mx-auto" /></td></tr>
            ) : expenses.length === 0 ? (
              <tr><td colSpan={7} className="text-center py-12">
                <Receipt className="h-12 w-12 text-surface-300 dark:text-surface-600 mx-auto mb-3" />
                <p className="text-sm font-medium text-surface-500 dark:text-surface-400">
                  {keyword || catFilter ? 'No expenses match your filters' : 'No expenses recorded yet'}
                </p>
                <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
                  {keyword || catFilter ? 'Try adjusting your search or category filter.' : 'Click "+ Add Expense" to track your first business expense.'}
                </p>
              </td></tr>
            ) : (
              expenses.map((exp) => (
                <tr key={exp.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                  <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{exp.date ? formatDate(exp.date) : '—'}</td>
                  <td className="px-4 py-3">
                    <span className="inline-flex items-center rounded-full bg-surface-100 dark:bg-surface-700 px-2 py-0.5 text-xs font-medium text-surface-700 dark:text-surface-300">
                      {exp.category}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-surface-600 dark:text-surface-400 max-w-xs truncate">{exp.description || '—'}</td>
                  <td className="px-4 py-3 text-surface-500 text-xs">{exp.first_name} {exp.last_name}</td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(Number(exp.amount) || 0)}</td>
                  <td className="px-4 py-3">
                    {exp.receipt_image_path ? (
                      <a
                        href={exp.receipt_image_path}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400"
                        title="View receipt"
                      >
                        <ExternalLink className="h-3 w-3" /> View
                      </a>
                    ) : (
                      <span className="text-xs text-surface-300 dark:text-surface-600">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex items-center justify-end gap-1">
                      <button aria-label="Edit" onClick={() => handleEdit(exp)} className="p-1.5 rounded-md text-surface-400 hover:text-amber-600 hover:bg-amber-50 dark:hover:text-amber-400 dark:hover:bg-amber-900/20">
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button aria-label="Delete" onClick={() => setDeleteTarget(exp.id)}
                        className="p-1.5 rounded-md text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-900/20">
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        {/* Pagination */}
        {pagination.total_pages > 1 && (
          <div className="flex items-center justify-between border-t border-surface-200 dark:border-surface-700 px-4 py-3">
            <p className="text-sm text-surface-500">Page {page} of {pagination.total_pages}</p>
            <div className="flex gap-1">
              <button aria-label="Previous page" disabled={page <= 1} onClick={() => setPage(page - 1)} className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5">
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button aria-label="Next page" disabled={page >= pagination.total_pages} onClick={() => setPage(page + 1)} className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5">
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}
      </div>

      <ConfirmDialog
        open={deleteTarget !== null}
        title="Delete Expense"
        message="Are you sure you want to delete this expense? This action cannot be undone."
        confirmLabel="Delete"
        danger
        onConfirm={() => { if (deleteTarget !== null) deleteMut.mutate(deleteTarget); setDeleteTarget(null); }}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  );
}
