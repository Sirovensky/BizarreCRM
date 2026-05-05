import { useState } from 'react';
import { Database, ChevronDown, ShieldCheck } from 'lucide-react';
import { cn } from '@/utils/cn';
import { DataRetentionTab } from './DataRetentionTab';

// DataImportTab is defined inline in SettingsPage.tsx and rendered here via
// the children prop pattern — but since it's a local function we can't import
// it. Instead SettingsPage passes the rendered <DataImportTab /> as children,
// or we accept the two sub-components independently.
//
// Simpler: DataTab renders DataRetentionTab directly (it's an exported
// component), and accepts the import content as a child slot so SettingsPage
// can pass <DataImportTab /> without moving that large function.

interface DataTabProps {
  importContent: React.ReactNode;
}

interface SectionProps {
  title: string;
  icon: React.ReactNode;
  defaultOpen?: boolean;
  children: React.ReactNode;
}

function AccordionSection({ title, icon, defaultOpen = false, children }: SectionProps) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="mb-3 rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 shadow-sm overflow-hidden">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center justify-between px-4 py-3 text-left hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
        aria-expanded={open}
      >
        <div className="flex items-center gap-2">
          <span className="text-primary-900 dark:text-primary-400">{icon}</span>
          <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">{title}</span>
        </div>
        <ChevronDown
          className={cn(
            'h-4 w-4 text-surface-400 transition-transform duration-200 shrink-0',
            open && 'rotate-180',
          )}
        />
      </button>

      {open && (
        <div className="border-t border-surface-200 dark:border-surface-700 px-0 py-0">
          {children}
        </div>
      )}
    </div>
  );
}

// ─── DataTab ──────────────────────────────────────────────────────────────────
// Combined "Data" settings tab. Three sub-sections:
//   A. Import   — RepairDesk / RepairShopr / MyRepairApp + CSV migration tools
//   B. Export   — GDPR/CCPA "Download all my data" (lives inside importContent)
//   C. Retention & Privacy — PII sweeper retention durations (DataRetentionTab)
//
// Import is open by default; Retention is closed (most users don't visit it).

export function DataTab({ importContent }: DataTabProps) {
  return (
    <div>
      <AccordionSection
        title="Import & Export"
        icon={<Database className="h-4 w-4" />}
        defaultOpen={true}
      >
        <div className="p-0">
          {importContent}
        </div>
      </AccordionSection>

      <AccordionSection
        title="Retention & Privacy"
        icon={<ShieldCheck className="h-4 w-4" />}
        defaultOpen={false}
      >
        <div className="p-4">
          <DataRetentionTab />
        </div>
      </AccordionSection>
    </div>
  );
}
