import { useState, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Trash2, Pencil, DollarSign, Search, Loader2, X, ChevronLeft, ChevronRight, Receipt } from 'lucide-react';
import toast from 'react-hot-toast';
import { expenseApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';

const EXPENSE_CATEGORIES = [
  'Rent', 'Utilities', 'Parts & Supplies', 'Tools & Equipment', 'Marketing',
  'Insurance', 'Payroll', 'Software', 'Office Supplies', 'Shipping',
  'Travel', 'Maintenance', 'Taxes & Fees', 'Other',
] as const;

export function ExpensesPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [keyword, setKeyword] = useState('');
  const [catFilter, setCatFilter] = useState('');
  const [showAdd, setShowAdd] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);

  const [form, setForm] = useState({ category: 'Other', amount: '', description: '', date: new Date().toISOString().slice(0, 10) });
  const [deleteTarget, setDeleteTarget] = useState<number | null>(null);

  const searchRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [searchInput, setSearchInput] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['expenses', page, keyword, catFilter],
    queryFn: () => expenseApi.list({ page, pagesize: 25, keyword: keyword || undefined, category: catFilter || undefined }),
  });

  const expenses = data?.data?.data?.expenses || [];
  const pagination = data?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1 };
  const summary = data?.data?.data?.summary || { total_amount: 0, total_count: 0 };
  const categories = data?.data?.data?.categories || [];

  const createMut = useMutation({
    mutationFn: (d: any) => editingId ? expenseApi.update(editingId, d) : expenseApi.create(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] });
      toast.success(editingId ? 'Expense updated' : 'Expense added');
      setShowAdd(false);
      setEditingId(null);
      setForm({ category: 'Other', amount: '', description: '', date: new Date().toISOString().slice(0, 10) });
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => expenseApi.delete(id),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['expenses'] }); toast.success('Expense deleted'); },
  });

  const handleSubmit = () => {
    if (!form.amount || parseFloat(form.amount) <= 0) return toast.error('Valid amount required');
    if (!form.category) return toast.error('Category required');
    createMut.mutate({ ...form, amount: parseFloat(form.amount) });
  };

  const handleEdit = (exp: any) => {
    setEditingId(exp.id);
    setForm({ category: exp.category, amount: String(exp.amount), description: exp.description || '', date: exp.date || '' });
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
          onClick={() => { setEditingId(null); setForm({ category: 'Other', amount: '', description: '', date: new Date().toISOString().slice(0, 10) }); setShowAdd(true); }}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 transition-colors"
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
              className="w-full pl-9 pr-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500"
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

      {/* Add/Edit form */}
      {showAdd && (
        <div className="card mb-4 p-5">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">
            {editingId ? 'Edit Expense' : 'New Expense'}
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
            <select value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100">
              {EXPENSE_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
            <input type="number" step="0.01" min="0" placeholder="Amount" value={form.amount}
              onChange={(e) => setForm({ ...form, amount: e.target.value })}
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <input type="date" value={form.date} onChange={(e) => setForm({ ...form, date: e.target.value })}
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <input type="text" placeholder="Description" value={form.description}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
          </div>
          <div className="flex gap-2 mt-3">
            <button onClick={handleSubmit} disabled={createMut.isPending}
              className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-primary-600 text-white rounded-lg hover:bg-primary-700 disabled:opacity-50">
              {createMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <DollarSign className="h-4 w-4" />}
              {editingId ? 'Update' : 'Add Expense'}
            </button>
            <button onClick={() => { setShowAdd(false); setEditingId(null); }} className="px-4 py-2 text-sm text-surface-500 hover:text-surface-700">Cancel</button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="card overflow-hidden">
        <table className="w-full text-sm text-left">
          <thead className="bg-surface-50 dark:bg-surface-800/50">
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 font-medium text-surface-500">Date</th>
              <th className="px-4 py-3 font-medium text-surface-500">Category</th>
              <th className="px-4 py-3 font-medium text-surface-500">Description</th>
              <th className="px-4 py-3 font-medium text-surface-500">By</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Amount</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
            {isLoading ? (
              <tr><td colSpan={6} className="text-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400 mx-auto" /></td></tr>
            ) : expenses.length === 0 ? (
              <tr><td colSpan={6} className="text-center py-12">
                <Receipt className="h-12 w-12 text-surface-300 dark:text-surface-600 mx-auto mb-3" />
                <p className="text-sm font-medium text-surface-500 dark:text-surface-400">
                  {keyword || catFilter ? 'No expenses match your filters' : 'No expenses recorded yet'}
                </p>
                <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
                  {keyword || catFilter ? 'Try adjusting your search or category filter.' : 'Click "+ Add Expense" to track your first business expense.'}
                </p>
              </td></tr>
            ) : (
              expenses.map((exp: any) => (
                <tr key={exp.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                  <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{exp.date ? formatDate(exp.date) : '—'}</td>
                  <td className="px-4 py-3">
                    <span className="inline-flex items-center rounded-full bg-surface-100 dark:bg-surface-700 px-2 py-0.5 text-xs font-medium text-surface-700 dark:text-surface-300">
                      {exp.category}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-surface-600 dark:text-surface-400 max-w-xs truncate">{exp.description || '—'}</td>
                  <td className="px-4 py-3 text-surface-500 text-xs">{exp.first_name} {exp.last_name}</td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(exp.amount)}</td>
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
              <button aria-label="Previous page" disabled={page <= 1} onClick={() => setPage(page - 1)} className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-50">
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button aria-label="Next page" disabled={page >= pagination.total_pages} onClick={() => setPage(page + 1)} className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-50">
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
