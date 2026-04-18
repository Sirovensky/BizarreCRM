import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
} from '@tanstack/react-table';
import {
  Users,
  Plus,
  Search,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  Eye,
  Pencil,
  Trash2,
  ChevronLeft,
  ChevronRight,
  Loader2,
  Wrench,
  Download,
  Upload,
  X,
  Check,
  Filter,
  Phone,
  MessageSquare,
  AlertTriangle,
  MoreHorizontal,
  Mail,
  UserPlus,
  Tag,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi, settingsApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { useUndoableAction } from '@/hooks/useUndoableAction';
import { cn } from '@/utils/cn';
import { formatCurrency, formatPhone, formatDate } from '@/utils/format';
import type { Customer } from '@bizarre-crm/shared';

const DEVICE_NAME_REGEX = /\b(laptop|phone|iphone|ipad|samsung|dell|hp|macbook|lenovo|asus|acer|surface|pixel|galaxy|chromebook|thinkpad|tablet|kindle|airpod|watch|drone|xbox|playstation|nintendo|switch|console)\b/i;

function looksLikeDeviceName(name: string): boolean {
  return DEVICE_NAME_REGEX.test(name);
}

function formatPhoneDisplay(phone: string): string {
  if (!phone) return '';
  return formatPhone(phone);
}

export function CustomerListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Number(searchParams.get('page') || '1');
  const pageSize = Number(searchParams.get('pagesize') || localStorage.getItem('customers_pagesize') || '25');
  const keyword = searchParams.get('keyword') || '';

  const [searchInput, setSearchInput] = useState(keyword);
  const [sorting, setSorting] = useState<SortingState>([]);
  const [deleteConfirm, setDeleteConfirm] = useState<{ open: boolean; id?: number; name?: string }>({ open: false });

  // Advanced filters
  const [showFilters, setShowFilters] = useState(false);
  const [groupId, setGroupId] = useState(searchParams.get('group_id') || '');
  const [fromDate, setFromDate] = useState(searchParams.get('from_date') || '');
  const [toDate, setToDate] = useState(searchParams.get('to_date') || '');
  const [hasOpenTickets, setHasOpenTickets] = useState(searchParams.get('has_open_tickets') || '');

  // Import modal
  const [showImportModal, setShowImportModal] = useState(false);
  const [importText, setImportText] = useState('');
  const [importPreview, setImportPreview] = useState<any[]>([]);

  // Bulk selection & tagging
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [showTagInput, setShowTagInput] = useState(false);
  const [tagValue, setTagValue] = useState('');

  // Debounced search (skip on mount to avoid resetting page to 1)
  const prevKeywordRef = useRef(searchInput);
  useEffect(() => {
    if (searchInput === prevKeywordRef.current) return;
    prevKeywordRef.current = searchInput;
    const timer = setTimeout(() => {
      const params = new URLSearchParams(searchParams);
      if (searchInput) {
        params.set('keyword', searchInput);
      } else {
        params.delete('keyword');
      }
      params.set('page', '1');
      setSearchParams(params, { replace: true });
    }, 300);
    return () => clearTimeout(timer);
  }, [searchInput]);

  const applyFilters = () => {
    const p = new URLSearchParams(searchParams);
    if (groupId) p.set('group_id', groupId); else p.delete('group_id');
    if (fromDate) p.set('from_date', fromDate); else p.delete('from_date');
    if (toDate) p.set('to_date', toDate); else p.delete('to_date');
    if (hasOpenTickets) p.set('has_open_tickets', hasOpenTickets); else p.delete('has_open_tickets');
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const clearFilters = () => {
    setGroupId('');
    setFromDate('');
    setToDate('');
    setHasOpenTickets('');
    const p = new URLSearchParams(searchParams);
    ['group_id', 'from_date', 'to_date', 'has_open_tickets'].forEach(k => p.delete(k));
    p.set('page', '1');
    setSearchParams(p, { replace: true });
  };

  const activeFilterCount = [
    searchParams.get('group_id'),
    searchParams.get('from_date'),
    searchParams.get('to_date'),
    searchParams.get('has_open_tickets'),
  ].filter(Boolean).length;

  // Map table sorting state to API params
  const sortBy = sorting.length > 0 ? sorting[0].id : 'first_name';
  const sortOrder = sorting.length > 0 ? (sorting[0].desc ? 'DESC' : 'ASC') : 'ASC';

  const sortColumnMap: Record<string, string> = {
    name: 'first_name',
    organization: 'organization',
    phone: 'mobile',
    email: 'email',
    city: 'city',
    ticket_count: 'ticket_count',
    total_spent: 'total_spent',
  };
  const serverSortBy = sortColumnMap[sortBy] || 'first_name';

  // Fetch customers with stats
  const { data, isLoading, isError } = useQuery({
    queryKey: ['customers', {
      page, pageSize, keyword,
      sort_by: serverSortBy, sort_order: sortOrder,
      include_stats: '1',
      group_id: searchParams.get('group_id') || undefined,
      from_date: searchParams.get('from_date') || undefined,
      to_date: searchParams.get('to_date') || undefined,
      has_open_tickets: searchParams.get('has_open_tickets') || undefined,
    }],
    queryFn: () =>
      customerApi.list({
        page, pagesize: pageSize,
        keyword: keyword || undefined,
        sort_by: serverSortBy, sort_order: sortOrder,
        include_stats: '1',
        group_id: searchParams.get('group_id') ? parseInt(searchParams.get('group_id')!) : undefined,
        from_date: searchParams.get('from_date') || undefined,
        to_date: searchParams.get('to_date') || undefined,
        has_open_tickets: searchParams.get('has_open_tickets') || undefined,
      } as any),
  });

  const { data: groupsData } = useQuery({
    queryKey: ['customer-groups'],
    queryFn: () => settingsApi.getCustomerGroups(),
  });

  const customers: Customer[] = data?.data?.data?.customers || [];
  const pagination = data?.data?.data?.pagination;
  const groups: any[] = groupsData?.data?.data || [];

  // Delete mutation — wrapped in a 5s undo window (D4-5).
  // Strategy: optimistically hide the row from the React Query cache, then
  // fire the server call only after the undo window elapses. If Undo is
  // clicked we restore the cached row and never hit the server.
  const deleteUndo = useUndoableAction<{ id: number; name: string }>(
    async ({ id }) => {
      await customerApi.delete(id);
      queryClient.invalidateQueries({ queryKey: ['customers'] });
    },
    {
      timeoutMs: 5000,
      pendingMessage: ({ name }) => `Deleting "${name}"…`,
      successMessage: 'Customer deleted',
      errorMessage: 'Failed to delete customer',
      onUndo: () => {
        // Revert the optimistic removal by refetching the list.
        queryClient.invalidateQueries({ queryKey: ['customers'] });
      },
    },
  );

  const scheduleCustomerDelete = useCallback(
    (id: number, name: string) => {
      // Optimistic hide: drop the row from every cached customer list page.
      queryClient.setQueriesData({ queryKey: ['customers'] }, (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.customers;
        if (Array.isArray(list)) {
          clone.data.data.customers = list.filter((c: any) => c.id !== id);
        }
        return clone;
      });
      deleteUndo.trigger({ id, name });
    },
    [queryClient, deleteUndo],
  );

  const importMutation = useMutation({
    mutationFn: (items: any[]) => customerApi.importCsv(items),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      const d = res?.data?.data;
      toast.success(`Imported ${d?.created || 0} customers${d?.errors?.length ? `, ${d.errors.length} errors` : ''}`);
      setShowImportModal(false);
      setImportText('');
      setImportPreview([]);
    },
    onError: () => toast.error('Import failed'),
  });

  const bulkTagMut = useMutation({
    mutationFn: ({ tag }: { tag: string }) =>
      customerApi.bulkTag(Array.from(selected), tag),
    onSuccess: () => {
      toast.success('Tag applied successfully');
      setSelected(new Set());
      setShowTagInput(false);
      setTagValue('');
      queryClient.invalidateQueries({ queryKey: ['customers'] });
    },
    onError: () => toast.error('Failed to apply tag'),
  });

  function toggleSelectAll() {
    if (selected.size === customers.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(customers.map((c) => c.id)));
    }
  }

  function toggleSelect(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const handleDelete = useCallback(
    (e: React.MouseEvent, id: number, name: string) => {
      e.stopPropagation();
      setDeleteConfirm({ open: true, id, name });
    },
    [],
  );

  const setPage = useCallback(
    (newPage: number) => {
      const params = new URLSearchParams(searchParams);
      params.set('page', String(newPage));
      setSearchParams(params, { replace: true });
    },
    [searchParams, setSearchParams],
  );

  // CSV Export
  // @audit-fixed: was exporting only current page (LIMIT bug). Now fetches all matching customers
  // by paging through the API at 250/req until exhausted, so the CSV is the FULL filtered set.
  const [exporting, setExporting] = useState(false);
  const handleExport = async () => {
    if (exporting) return;
    setExporting(true);
    try {
      const headers = ['id', 'first_name', 'last_name', 'email', 'phone', 'mobile', 'organization', 'city', 'state'];
      const all: any[] = [];
      const exportPageSize = 250;
      let exportPage = 1;
      let totalPages = 1;
      do {
        const res = await customerApi.list({
          page: exportPage,
          pagesize: exportPageSize,
          keyword: keyword || undefined,
          sort_by: serverSortBy,
          sort_order: sortOrder,
          group_id: searchParams.get('group_id') ? parseInt(searchParams.get('group_id')!) : undefined,
          from_date: searchParams.get('from_date') || undefined,
          to_date: searchParams.get('to_date') || undefined,
          has_open_tickets: searchParams.get('has_open_tickets') || undefined,
        } as any);
        const batch = res.data?.data?.customers || [];
        all.push(...batch);
        totalPages = res.data?.data?.pagination?.total_pages || 1;
        exportPage += 1;
        if (batch.length === 0) break;
      } while (exportPage <= totalPages);

      const rows = all.map((c: any) => headers.map(h => String(c[h] ?? '')));
      const csv = [headers.join(','), ...rows.map(r => r.map(v => `"${v.replace(/"/g, '""')}"`).join(','))].join('\n');
      const blob = new Blob([csv], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `customers-export-${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success(`Exported ${all.length} customers`);
    } catch (err) {
      toast.error('Export failed');
    } finally {
      setExporting(false);
    }
  };

  const parseImportCsv = (text: string) => {
    const lines = text.trim().split('\n');
    if (lines.length < 2) return;
    const headers = lines[0].split(',').map(h => h.trim().replace(/^"|"$/g, '').toLowerCase());
    const rows = lines.slice(1).map(line => {
      const vals = line.split(',').map(v => v.trim().replace(/^"|"$/g, ''));
      const obj: Record<string, string> = {};
      headers.forEach((h, i) => { obj[h] = vals[i] || ''; });
      return obj;
    });
    setImportPreview(rows);
  };

  // Table columns
  const columns = useMemo<ColumnDef<Customer>[]>(
    () => [
      {
        id: 'select',
        header: () => (
          <input
            type="checkbox"
            checked={customers.length > 0 && selected.size === customers.length}
            onChange={toggleSelectAll}
            className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
          />
        ),
        size: 40,
        enableSorting: false,
        cell: ({ row }) => (
          <div onClick={(e) => e.stopPropagation()}>
            <input
              type="checkbox"
              checked={selected.has(row.original.id)}
              onChange={() => toggleSelect(row.original.id)}
              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
          </div>
        ),
      },
      {
        id: 'name',
        header: 'Name',
        accessorFn: (row) => `${row.first_name} ${row.last_name}`.trim(),
        size: 180,
        cell: ({ row }) => {
          const firstName = row.original.first_name || '';
          const lastName = row.original.last_name || '';
          const name = `${firstName} ${lastName}`.trim();
          const fallback = (row.original as any).mobile || (row.original as any).phone || (row.original as any).email || 'Unknown';
          const isDeviceName = name ? looksLikeDeviceName(name) : false;
          const missingLastName = !!firstName && !lastName;
          const looksLikePhone = /^\+?\d[\d\s\-().]{6,}$/.test(firstName);
          const needsName = !name || looksLikePhone;
          return (
            <div className="flex items-center gap-1.5 font-medium text-surface-900 dark:text-surface-100">
              <span>{name || <span className="text-surface-400 italic">{fallback}</span>}</span>
              {needsName && (
                <Link to={`/customers/${row.original.id}?edit=true`} onClick={(e) => e.stopPropagation()}
                  className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-medium rounded bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/30 transition-colors shrink-0"
                  title="Add a name for this customer">
                  <UserPlus className="h-3 w-3" /> Add Name
                </Link>
              )}
              {isDeviceName && !needsName && (
                <span title="Name looks like a device — may need correction" className="text-amber-500 dark:text-amber-400 shrink-0">
                  <AlertTriangle className="h-3.5 w-3.5" />
                </span>
              )}
              {missingLastName && !isDeviceName && !needsName && (
                <span title="No last name" className="shrink-0 w-1.5 h-1.5 rounded-full bg-amber-400 dark:bg-amber-500" />
              )}
            </div>
          );
        },
      },
      {
        accessorKey: 'organization',
        header: 'Organization',
        size: 160,
        cell: ({ getValue }) => (
          <span className="text-surface-600 dark:text-surface-400">
            {(getValue() as string) || '\u2014'}
          </span>
        ),
      },
      {
        id: 'phone',
        header: 'Phone',
        accessorFn: (row) => (row as any).mobile || (row as any).phone || '',
        size: 130,
        cell: ({ getValue }) => {
          const phone = getValue() as string;
          return phone ? (
            <a href={`tel:${phone}`} onClick={(e) => e.stopPropagation()} className="text-surface-600 hover:text-primary-600 dark:text-surface-400 dark:hover:text-primary-400">
              {formatPhoneDisplay(phone)}
            </a>
          ) : <span className="text-surface-400">{'\u2014'}</span>;
        },
      },
      {
        accessorKey: 'email',
        header: 'Email',
        size: 180,
        cell: ({ getValue }) => (
          <span className="text-surface-600 dark:text-surface-400 truncate block max-w-[180px]">
            {(getValue() as string) || '\u2014'}
          </span>
        ),
      },
      {
        accessorKey: 'ticket_count',
        header: 'Tickets',
        size: 70,
        cell: ({ getValue }) => {
          const count = (getValue() as number) || 0;
          return (
            <span className={cn(
              'inline-flex items-center justify-center px-2 py-0.5 rounded-full text-xs font-medium',
              count > 0
                ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400'
                : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
            )}>
              {count}
            </span>
          );
        },
      },
      {
        id: 'total_spent',
        header: 'Total Spent',
        accessorFn: (row) => (row as any).total_spent || 0,
        size: 100,
        cell: ({ getValue }) => {
          const val = Number(getValue()) || 0;
          return (
            <span className={cn('text-sm', val > 0 ? 'text-green-600 dark:text-green-400 font-medium' : 'text-surface-400')}>
              {val > 0 ? formatCurrency(val) : '\u2014'}
            </span>
          );
        },
      },
      {
        id: 'outstanding_balance',
        header: 'Outstanding',
        accessorFn: (row) => (row as any).outstanding_balance || 0,
        size: 100,
        enableSorting: false,
        cell: ({ getValue }) => {
          const val = Number(getValue()) || 0;
          return (
            <span className={cn('text-sm', val > 0 ? 'text-red-600 dark:text-red-400 font-medium' : 'text-surface-400')}>
              {val > 0 ? formatCurrency(val) : '\u2014'}
            </span>
          );
        },
      },
      {
        id: 'last_visit',
        header: 'Last Visit',
        accessorFn: (row) => (row as any).last_ticket_date || '',
        size: 100,
        enableSorting: false,
        cell: ({ getValue }) => {
          const dateStr = getValue() as string;
          if (!dateStr) return <span className="text-surface-400">{'\u2014'}</span>;
          const date = new Date(dateStr);
          const now = new Date();
          const diffMs = now.getTime() - date.getTime();
          const diffDays = Math.floor(diffMs / 86400000);
          let relative: string;
          if (diffDays === 0) relative = 'Today';
          else if (diffDays === 1) relative = '1d ago';
          else if (diffDays < 30) relative = `${diffDays}d ago`;
          else if (diffDays < 365) relative = `${Math.floor(diffDays / 30)}mo ago`;
          else relative = `${Math.floor(diffDays / 365)}y ago`;
          return (
            <span className={cn('text-sm', diffDays > 180 ? 'text-surface-400' : 'text-surface-600 dark:text-surface-300')}
              title={/* @audit-fixed: use formatDate helper */ formatDate(dateStr)}>
              {relative}
            </span>
          );
        },
      },
      {
        id: 'actions',
        header: '',
        size: 80,
        enableSorting: false,
        cell: ({ row }) => {
          const customer = row.original;
          const fullName = `${customer.first_name} ${customer.last_name}`.trim();
          const customerPhone = (customer as any).mobile || (customer as any).phone || '';
          return <CustomerActionsMenu customer={customer} fullName={fullName} phone={customerPhone} onDelete={handleDelete} />;
        },
      },
    ],
    [handleDelete, selected, customers.length],
  );

  const table = useReactTable({
    data: customers,
    columns,
    state: { sorting },
    onSortingChange: (updater) => {
      setSorting(updater);
      const params = new URLSearchParams(searchParams);
      params.set('page', '1');
      setSearchParams(params, { replace: true });
    },
    getCoreRowModel: getCoreRowModel(),
    manualSorting: true,
    manualPagination: true,
  });

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="mb-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Customers</h1>
          <p className="text-surface-500 dark:text-surface-400">Manage your customer database</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={handleExport} disabled={exporting} className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors disabled:opacity-50">
            {exporting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            {exporting ? 'Exporting...' : 'Export'}
          </button>
          <button onClick={() => setShowImportModal(true)} className="inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
            <Upload className="h-4 w-4" /> Import
          </button>
          <Link to="/customers/new" className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium text-sm transition-colors shadow-sm">
            <Plus className="h-4 w-4" /> New Customer
          </Link>
        </div>
      </div>

      {/* Search + Filters */}
      <div className="mb-3 shrink-0 flex items-center gap-2">
        <div className="relative max-w-md flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input type="text" placeholder="Search customers..." value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            className="w-full pl-10 pr-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500 transition-colors" />
        </div>
        <button onClick={() => setShowFilters(!showFilters)}
          className={cn(
            'inline-flex items-center gap-1.5 px-3 py-2 text-sm font-medium rounded-lg border transition-colors',
            activeFilterCount > 0
              ? 'border-primary-300 bg-primary-50 text-primary-700 dark:border-primary-700 dark:bg-primary-900/20 dark:text-primary-400'
              : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800'
          )}>
          <Filter className="h-4 w-4" />
          Filters{activeFilterCount > 0 && ` (${activeFilterCount})`}
        </button>
      </div>

      {/* Advanced Filters Panel */}
      {showFilters && (
        <div className="mb-3 p-4 rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Customer Group</label>
            <select value={groupId} onChange={e => setGroupId(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5">
              <option value="">All Groups</option>
              {groups.map((g: any) => <option key={g.id} value={g.id}>{g.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Created From</label>
            <input type="date" value={fromDate} onChange={e => setFromDate(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5" />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Created To</label>
            <input type="date" value={toDate} onChange={e => setToDate(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5" />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Open Tickets</label>
            <select value={hasOpenTickets} onChange={e => setHasOpenTickets(e.target.value)}
              className="w-full text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5">
              <option value="">All</option>
              <option value="1">Has Open Tickets</option>
              <option value="0">No Open Tickets</option>
            </select>
          </div>
          <div className="col-span-full flex gap-2 mt-1">
            <button onClick={applyFilters} className="px-3 py-1.5 text-sm font-medium rounded-md bg-primary-600 text-white hover:bg-primary-700 transition-colors">Apply</button>
            <button onClick={clearFilters} className="px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 transition-colors">Clear</button>
          </div>
        </div>
      )}

      {/* Table */}
      <div className="card overflow-hidden flex-1 flex flex-col min-h-0">
        {/* Bulk action bar */}
        {selected.size > 0 && (
          <div className="flex items-center gap-3 border-b border-surface-200 bg-primary-50 px-4 py-2.5 dark:border-surface-700 dark:bg-primary-950/30 shrink-0">
            <span className="text-sm font-medium text-primary-700 dark:text-primary-300">
              {selected.size} selected
            </span>
            {showTagInput ? (
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={tagValue}
                  onChange={(e) => setTagValue(e.target.value)}
                  placeholder="Enter tag name..."
                  autoFocus
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && tagValue.trim()) {
                      bulkTagMut.mutate({ tag: tagValue.trim() });
                    } else if (e.key === 'Escape') {
                      setShowTagInput(false);
                      setTagValue('');
                    }
                  }}
                  className="w-40 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
                />
                <button
                  onClick={() => { if (tagValue.trim()) bulkTagMut.mutate({ tag: tagValue.trim() }); }}
                  disabled={!tagValue.trim() || bulkTagMut.isPending}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
                >
                  {bulkTagMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                  Apply
                </button>
                <button
                  onClick={() => { setShowTagInput(false); setTagValue(''); }}
                  className="text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
                >
                  Cancel
                </button>
              </div>
            ) : (
              <button
                onClick={() => setShowTagInput(true)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
              >
                <Tag className="h-3.5 w-3.5" /> Tag Selected
              </button>
            )}
            <button
              onClick={() => { setSelected(new Set()); setShowTagInput(false); setTagValue(''); }}
              className="ml-auto text-sm text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Clear
            </button>
          </div>
        )}

        {isError ? (
          <div className="flex flex-col items-center justify-center py-12 text-surface-500">
            <p className="text-sm font-medium text-red-500 mb-1">Failed to load customers</p>
            <p className="text-xs">Check your connection and try refreshing.</p>
          </div>
        ) : isLoading ? (
          <LoadingSkeleton />
        ) : customers.length === 0 ? (
          <EmptyState keyword={keyword} />
        ) : (
          <>
            <div className="overflow-auto flex-1 min-h-0">
              <table className="w-full">
                <thead className="sticky top-0 z-10 bg-white dark:bg-surface-900">
                  {table.getHeaderGroups().map((headerGroup) => (
                    <tr key={headerGroup.id} className="border-b border-surface-200 dark:border-surface-700">
                      {headerGroup.headers.map((header) => (
                        <th key={header.id}
                          className={cn(
                            'px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50',
                            header.column.getCanSort() && 'cursor-pointer select-none hover:text-surface-700 dark:hover:text-surface-200',
                          )}
                          style={{ width: header.getSize() }}
                          onClick={header.column.getToggleSortingHandler()}>
                          <div className="flex items-center gap-1.5">
                            {flexRender(header.column.columnDef.header, header.getContext())}
                            {header.column.getCanSort() && (
                              <span className="text-surface-300 dark:text-surface-600">
                                {header.column.getIsSorted() === 'asc' ? <ArrowUp className="h-3.5 w-3.5" /> :
                                 header.column.getIsSorted() === 'desc' ? <ArrowDown className="h-3.5 w-3.5" /> :
                                 <ArrowUpDown className="h-3.5 w-3.5" />}
                              </span>
                            )}
                          </div>
                        </th>
                      ))}
                    </tr>
                  ))}
                </thead>
                <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                  {table.getRowModel().rows.map((row) => (
                    <tr key={row.id} onClick={() => navigate(`/customers/${row.original.id}`)}
                      className={cn(
                        'hover:bg-surface-50 dark:hover:bg-surface-800/50 cursor-pointer transition-colors',
                        selected.has(row.original.id) && 'bg-primary-50/50 dark:bg-primary-950/20',
                      )}>
                      {row.getVisibleCells().map((cell) => (
                        <td key={cell.id} className="px-4 py-3 text-sm">
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {pagination && (
              <div className="flex items-center justify-between px-4 py-3 border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/30">
                <div className="flex items-center gap-4">
                  <div className="flex items-center gap-1.5">
                    <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                    <select
                      value={pageSize}
                      onChange={(e) => {
                        const v = e.target.value;
                        localStorage.setItem('customers_pagesize', v);
                        const p = new URLSearchParams(searchParams);
                        p.set('pagesize', v);
                        p.set('page', '1');
                        setSearchParams(p, { replace: true });
                      }}
                      className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus:outline-none focus:ring-1 focus:ring-primary-500"
                    >
                      {[10, 25, 50, 100, 250].map((n) => (
                        <option key={n} value={n}>{n}</option>
                      ))}
                    </select>
                    <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
                  </div>
                  <p className="text-sm text-surface-500 dark:text-surface-400">
                    Page {pagination.page} of {pagination.total_pages}
                    <span className="ml-2 text-surface-400 dark:text-surface-500">({pagination.total} total)</span>
                  </p>
                </div>
                {pagination.total_pages > 1 && (
                  <div className="flex items-center gap-2">
                    <button onClick={() => setPage(page - 1)} disabled={page <= 1}
                      className="inline-flex items-center justify-center gap-1 px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      <ChevronLeft className="h-4 w-4" /> Previous
                    </button>
                    <button onClick={() => setPage(page + 1)} disabled={page >= pagination.total_pages}
                      className="inline-flex items-center justify-center gap-1 px-4 py-2.5 min-h-[44px] md:min-h-0 md:px-3 md:py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
                      Next <ChevronRight className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {/* Import CSV Modal */}
      {showImportModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-2xl max-h-[80vh] flex flex-col">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Import Customers CSV</h3>
              <button aria-label="Close" onClick={() => { setShowImportModal(false); setImportText(''); setImportPreview([]); }} className="text-surface-400 hover:text-surface-600"><X className="h-5 w-5" /></button>
            </div>
            <p className="text-sm text-surface-500 mb-2">
              Paste CSV with headers: first_name, last_name, email, phone, mobile, organization, city, state, postcode, address1
            </p>
            <textarea value={importText}
              onChange={e => { setImportText(e.target.value); if (e.target.value) parseImportCsv(e.target.value); else setImportPreview([]); }}
              placeholder={'first_name,last_name,email,phone,mobile\nJohn,Doe,john@example.com,,555-0100'}
              rows={6} className="w-full text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 font-mono mb-3" />
            <div className="mb-2">
              <label className="px-3 py-1.5 text-sm font-medium rounded-md border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 cursor-pointer">
                <Upload className="h-4 w-4 inline mr-1" /> Upload File
                <input type="file" accept=".csv" className="hidden" onChange={e => {
                  const file = e.target.files?.[0]; if (!file) return;
                  const reader = new FileReader();
                  reader.onload = ev => { const text = ev.target?.result as string; setImportText(text); parseImportCsv(text); };
                  reader.readAsText(file);
                }} />
              </label>
            </div>
            {importPreview.length > 0 && (
              <div className="flex-1 overflow-auto mb-3 max-h-48 border border-surface-200 dark:border-surface-700 rounded-lg">
                <table className="w-full text-xs">
                  <thead><tr className="bg-surface-50 dark:bg-surface-800">
                    {Object.keys(importPreview[0]).slice(0, 6).map(h => <th key={h} className="px-2 py-1.5 text-left font-medium text-surface-500">{h}</th>)}
                  </tr></thead>
                  <tbody>
                    {importPreview.slice(0, 10).map((row, i) => (
                      <tr key={i} className="border-t border-surface-100 dark:border-surface-700/50">
                        {Object.values(row).slice(0, 6).map((v, j) => <td key={j} className="px-2 py-1 text-surface-700 dark:text-surface-300 truncate max-w-[120px]">{String(v)}</td>)}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {importPreview.length > 10 && <p className="text-xs text-surface-400 p-2">...and {importPreview.length - 10} more rows</p>}
              </div>
            )}
            <div className="flex justify-end gap-2">
              <button onClick={() => { setShowImportModal(false); setImportText(''); setImportPreview([]); }}
                className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300">Cancel</button>
              <button onClick={() => importMutation.mutate(importPreview)} disabled={importPreview.length === 0 || importMutation.isPending}
                className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50 inline-flex items-center gap-1.5">
                {importMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Import {importPreview.length} customers
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={deleteConfirm.open}
        title={`Delete Customer`}
        message={`Are you sure you want to delete "${deleteConfirm.name}"? This action cannot be undone.`}
        confirmLabel="Delete"
        danger
        requireTyping
        confirmText={deleteConfirm.name || ''}
        onConfirm={() => {
          if (deleteConfirm.id) scheduleCustomerDelete(deleteConfirm.id, deleteConfirm.name || '');
          setDeleteConfirm({ open: false });
        }}
        onCancel={() => setDeleteConfirm({ open: false })}
      />
    </div>
  );
}

function LoadingSkeleton() {
  return (
    <div className="animate-pulse">
      <div className="border-b border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 px-4 py-3">
        <div className="flex gap-4">
          {[180, 160, 130, 180, 70, 100, 100].map((w, i) => (
            <div key={i} className="h-3 rounded bg-surface-200 dark:bg-surface-700" style={{ width: w }} />
          ))}
        </div>
      </div>
      {Array.from({ length: 8 }).map((_, i) => (
        <div key={i} className="flex gap-4 px-4 py-4 border-b border-surface-100 dark:border-surface-700/50">
          {[40, 36, 28, 40, 12, 16, 16].map((w, j) => (
            <div key={j} className="h-4 rounded bg-surface-100 dark:bg-surface-700/50" style={{ width: `${w * 4}px` }} />
          ))}
        </div>
      ))}
    </div>
  );
}

function CustomerActionsMenu({ customer, fullName, phone, onDelete }: {
  customer: Customer;
  fullName: string;
  phone: string;
  onDelete: (e: React.MouseEvent, id: number, name: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div className="flex items-center justify-end gap-1" ref={ref}>
      <Link to={`/customers/${customer.id}`} onClick={(e) => e.stopPropagation()}
        className="p-1.5 rounded-md text-surface-400 hover:text-primary-600 hover:bg-primary-50 dark:hover:text-primary-400 dark:hover:bg-primary-900/20 transition-colors" title="View">
        <Eye className="h-4 w-4" />
      </Link>
      <div className="relative">
        <button onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }}
          className="p-1.5 rounded-md text-surface-400 hover:text-surface-600 hover:bg-surface-100 dark:hover:text-surface-300 dark:hover:bg-surface-700 transition-colors" title="More actions">
          <MoreHorizontal className="h-4 w-4" />
        </button>
        {open && (
          <div className="absolute right-0 top-full z-50 mt-1 w-44 rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
            <div className="py-1">
              {phone && (
                <>
                  <a href={`tel:${phone}`}
                    className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700">
                    <Phone className="h-3.5 w-3.5 text-blue-500" /> Call
                  </a>
                  <Link to={`/communications?phone=${encodeURIComponent(phone)}`}
                    className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700">
                    <MessageSquare className="h-3.5 w-3.5 text-emerald-500" /> SMS
                  </Link>
                </>
              )}
              {customer.email && (
                <a href={`mailto:${customer.email}`}
                  className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700">
                  <Mail className="h-3.5 w-3.5 text-amber-500" /> Email
                </a>
              )}
              <Link to={`/pos?customer=${customer.id}`}
                className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700">
                <Wrench className="h-3.5 w-3.5 text-green-500" /> New Ticket
              </Link>
              <Link to={`/customers/${customer.id}?edit=true`}
                className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700">
                <Pencil className="h-3.5 w-3.5 text-amber-500" /> Edit
              </Link>
              <div className="my-1 border-t border-surface-200 dark:border-surface-700" />
              <button onClick={(e) => { setOpen(false); onDelete(e, customer.id, fullName); }}
                className="flex w-full items-center gap-2 px-3 py-2 text-sm text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/20">
                <Trash2 className="h-3.5 w-3.5" /> Delete
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function EmptyState({ keyword }: { keyword: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <Users className="h-16 w-16 text-surface-300 dark:text-surface-600 mb-4" />
      <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
        {keyword ? 'No customers found' : 'No customers yet'}
      </h2>
      <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
        {keyword ? `No results matching "${keyword}"` : 'Add your first customer to get started'}
      </p>
      {!keyword && (
        <Link to="/customers/new" className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium text-sm transition-colors">
          <Plus className="h-4 w-4" /> New Customer
        </Link>
      )}
    </div>
  );
}
