/**
 * Mass barcode label print — select items, pick format/copies, download ZPL.
 *
 * Cross-ref: criticalaudit.md §48 idea #12.
 */
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation } from '@tanstack/react-query';
import { ChevronLeft, Printer, Loader2, Download } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

interface PrintResponse {
  format: 'zpl' | 'pdf';
  body: string;
  total_labels: number;
  item_count?: number;
}

export function MassLabelPrintPage() {
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [search, setSearch] = useState('');
  const [copies, setCopies] = useState(1);
  const [format, setFormat] = useState<'zpl' | 'pdf'>('zpl');
  const [preview, setPreview] = useState<string | null>(null);

  const { data } = useQuery({
    queryKey: ['inventory-labels', search],
    queryFn: async () => {
      const res = await inventoryApi.list({ keyword: search, pagesize: 100, page: 1 });
      return res.data.data;
    },
  });
  const items = data?.items || [];

  const printMut = useMutation({
    mutationFn: async () => {
      const res = await api.post<{ success: boolean; data: PrintResponse }>(
        '/inventory-enrich/labels/print',
        {
          item_ids: Array.from(selected),
          copies_per_item: copies,
          format,
        },
      );
      return res.data.data;
    },
    onSuccess: (data) => {
      toast.success(`Generated ${data.total_labels} labels`);
      setPreview(data.body);
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Print failed'),
  });

  const downloadFile = () => {
    if (!preview) return;
    const ext = format === 'zpl' ? 'zpl' : 'txt';
    const mime = format === 'zpl' ? 'application/octet-stream' : 'text/plain';
    const blob = new Blob([preview], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `labels-${Date.now()}.${ext}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const toggle = (id: number) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };

  const toggleAll = () => {
    if (selected.size === items.length) {
      setSelected(new Set());
    } else {
      setSelected(new Set(items.map((i: any) => i.id)));
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
          <ChevronLeft className="h-4 w-4" /> Back to Inventory
        </Link>
        <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
          <Printer className="h-6 w-6" /> Mass Label Print
        </h1>
        <p className="text-sm text-surface-500">Select items, print barcode labels in one job</p>
      </div>

      <div className="flex items-center gap-3">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search inventory..."
          className="flex-1 rounded-md border border-surface-300 px-3 py-2 text-sm"
        />
        <select
          value={format}
          onChange={(e) => setFormat(e.target.value as 'zpl' | 'pdf')}
          className="rounded-md border border-surface-300 px-3 py-2 text-sm"
        >
          <option value="zpl">ZPL (Zebra printers)</option>
          <option value="pdf">Plain text (any printer)</option>
        </select>
        <input
          value={copies}
          onChange={(e) => setCopies(Math.max(1, parseInt(e.target.value, 10) || 1))}
          type="number"
          min="1"
          max="10"
          className="w-20 rounded-md border border-surface-300 px-3 py-2 text-sm"
          placeholder="Copies"
        />
      </div>

      <div className="flex items-center justify-between">
        <div className="text-sm text-surface-600">
          Selected: <span className="font-semibold">{selected.size}</span> ·
          {' '}Will print: <span className="font-semibold">{selected.size * copies}</span> labels
        </div>
        <div className="flex gap-2">
          <button
            onClick={toggleAll}
            className="rounded-md border border-surface-300 px-3 py-1 text-sm"
          >
            {selected.size === items.length ? 'Clear' : 'Select all on page'}
          </button>
          <button
            onClick={() => printMut.mutate()}
            disabled={selected.size === 0 || printMut.isPending}
            className="inline-flex items-center gap-2 rounded-md bg-primary-600 px-4 py-1 text-sm font-semibold text-white disabled:opacity-50"
          >
            {printMut.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Printer className="h-4 w-4" />
            )}
            Generate
          </button>
        </div>
      </div>

      <div className="rounded-lg border border-surface-200 bg-white overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200">
            <tr>
              <th className="w-10 px-3 py-2">
                <input
                  type="checkbox"
                  checked={selected.size > 0 && selected.size === items.length}
                  onChange={toggleAll}
                />
              </th>
              <th className="text-left px-3 py-2">SKU</th>
              <th className="text-left px-3 py-2">Name</th>
              <th className="text-right px-3 py-2">Price</th>
            </tr>
          </thead>
          <tbody>
            {items.map((i: any) => (
              <tr
                key={i.id}
                onClick={() => toggle(i.id)}
                className={cn(
                  'border-b border-surface-100 last:border-0 cursor-pointer hover:bg-surface-50',
                  selected.has(i.id) && 'bg-primary-50',
                )}
              >
                <td className="px-3 py-2">
                  <input
                    type="checkbox"
                    checked={selected.has(i.id)}
                    onChange={() => toggle(i.id)}
                    onClick={(e) => e.stopPropagation()}
                  />
                </td>
                <td className="px-3 py-2 font-mono text-xs">{i.sku || `ID${i.id}`}</td>
                <td className="px-3 py-2">{i.name}</td>
                <td className="text-right px-3 py-2">{formatCurrency(i.retail_price || 0)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {preview && (
        <div className="rounded-lg border border-surface-200 bg-white p-4">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-semibold">Preview ({format.toUpperCase()})</h3>
            <button
              onClick={downloadFile}
              className="inline-flex items-center gap-1 rounded-md bg-green-600 px-3 py-1 text-sm font-semibold text-white"
            >
              <Download className="h-4 w-4" /> Download
            </button>
          </div>
          <pre className="text-xs bg-surface-50 p-3 rounded max-h-96 overflow-auto font-mono whitespace-pre-wrap">
            {preview.slice(0, 2000)}
            {preview.length > 2000 && '\n... (truncated)'}
          </pre>
        </div>
      )}
    </div>
  );
}
