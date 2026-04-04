import { Link } from 'react-router-dom';
import { ChevronRight } from 'lucide-react';

interface BreadcrumbItem {
  label: string;
  href?: string;
}

interface BreadcrumbProps {
  items: BreadcrumbItem[];
}

export function Breadcrumb({ items }: BreadcrumbProps) {
  const allItems: BreadcrumbItem[] = [{ label: 'Home', href: '/' }, ...items];

  return (
    <nav className="mb-2 flex items-center gap-1.5 text-sm text-surface-500">
      {allItems.map((item, i) => {
        const isLast = i === allItems.length - 1;
        return (
          <span key={i} className="flex items-center gap-1.5">
            {i > 0 && <ChevronRight className="h-3.5 w-3.5 text-surface-400" />}
            {isLast || !item.href ? (
              <span className="font-medium text-surface-600 dark:text-surface-300">
                {item.label}
              </span>
            ) : (
              <Link
                to={item.href}
                className="text-teal-500 dark:text-teal-400 hover:underline cursor-pointer transition-colors"
              >
                {item.label}
              </Link>
            )}
          </span>
        );
      })}
    </nav>
  );
}
