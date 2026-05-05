// WEB-FW-003 (Fixer-A5 2026-04-25): isolated module so recharts (~500kB)
// lands in its OWN chunk that InvoiceListPage `lazy()`-imports only after
// the page is already interactive. Previously recharts was a top-level
// import on InvoiceListPage and rode along in the page chunk, blocking
// first paint of the invoice list while a chart that's only rendered
// when there are 1+ invoices loaded.
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';

interface PieDatum {
  name: string;
  value: number;
}

export function InvoicePieChart({
  data,
  colorFor,
}: {
  data: PieDatum[];
  colorFor: (entry: PieDatum, index: number) => string;
}) {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <PieChart>
        <Pie data={data} dataKey="value" nameKey="name" cx="50%" cy="50%" innerRadius={25} outerRadius={50} paddingAngle={2}>
          {/* WEB-FF-021: key by entry.name so React reconciles cell→color
              pairings stably across poll-driven refreshes. */}
          {data.map((entry, i) => (
            <Cell key={entry.name} fill={colorFor(entry, i)} />
          ))}
        </Pie>
        <Tooltip formatter={(value: number) => [value, 'Count']} />
      </PieChart>
    </ResponsiveContainer>
  );
}
