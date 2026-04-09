/**
 * Placeholder page used for routes not yet implemented.
 * Shows the page name and a "coming soon" message.
 */
import { Construction } from 'lucide-react';

interface PlaceholderPageProps {
  title: string;
}

export function PlaceholderPage({ title }: PlaceholderPageProps) {
  return (
    <div className="flex flex-col items-center justify-center py-20 animate-fade-in">
      <Construction className="w-12 h-12 text-surface-600 mb-4" />
      <h1 className="text-lg font-bold text-surface-300 mb-1">{title}</h1>
      <p className="text-sm text-surface-500">This section is coming soon.</p>
    </div>
  );
}
