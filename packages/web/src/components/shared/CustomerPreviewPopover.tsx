import { useState, useRef, useEffect, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Phone, Mail, Ticket, DollarSign } from 'lucide-react';
import { customerApi } from '@/api/endpoints';
import { formatCurrency } from '@/utils/format';

interface CustomerPreviewPopoverProps {
  customerId: number;
  children: React.ReactNode;
}

export function CustomerPreviewPopover({ customerId, children }: CustomerPreviewPopoverProps) {
  const [visible, setVisible] = useState(false);
  const [position, setPosition] = useState<'below' | 'above'>('below');
  const enterTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const leaveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const wrapperRef = useRef<HTMLSpanElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);

  const { data: customerRes } = useQuery({
    queryKey: ['customer-preview', customerId],
    queryFn: () => customerApi.get(customerId),
    enabled: visible,
    staleTime: 60_000,
  });

  const { data: analyticsRes } = useQuery({
    queryKey: ['customer-analytics', customerId],
    queryFn: () => customerApi.analytics(customerId),
    enabled: visible,
    staleTime: 60_000,
  });

  const customer = customerRes?.data?.data;
  const analytics = analyticsRes?.data?.data;

  const updatePosition = useCallback(() => {
    if (!wrapperRef.current) return;
    const rect = wrapperRef.current.getBoundingClientRect();
    const spaceBelow = window.innerHeight - rect.bottom;
    setPosition(spaceBelow < 200 ? 'above' : 'below');
  }, []);

  const handleMouseEnter = useCallback(() => {
    if (leaveTimer.current) {
      clearTimeout(leaveTimer.current);
      leaveTimer.current = null;
    }
    enterTimer.current = setTimeout(() => {
      updatePosition();
      setVisible(true);
    }, 300);
  }, [updatePosition]);

  const handleMouseLeave = useCallback(() => {
    if (enterTimer.current) {
      clearTimeout(enterTimer.current);
      enterTimer.current = null;
    }
    leaveTimer.current = setTimeout(() => {
      setVisible(false);
    }, 200);
  }, []);

  useEffect(() => {
    return () => {
      if (enterTimer.current) clearTimeout(enterTimer.current);
      if (leaveTimer.current) clearTimeout(leaveTimer.current);
    };
  }, []);

  return (
    <span
      ref={wrapperRef}
      className="relative inline-block"
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {children}
      {visible && (
        <div
          ref={popoverRef}
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
          className={`absolute z-50 left-0 w-64 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg shadow-lg p-3 ${
            position === 'below' ? 'top-full mt-1' : 'bottom-full mb-1'
          }`}
          onClick={(e) => e.stopPropagation()}
        >
          {!customer ? (
            <div className="flex items-center justify-center py-3">
              <div className="h-4 w-4 border-2 border-primary-500 border-t-transparent rounded-full animate-spin" />
            </div>
          ) : (
            <div className="space-y-2">
              <Link
                to={`/customers/${customerId}`}
                className="block text-sm font-semibold text-surface-900 dark:text-surface-100 hover:text-primary-600 dark:hover:text-primary-400"
              >
                {customer.first_name} {customer.last_name}
              </Link>

              {customer.organization && (
                <p className="text-xs text-surface-500 dark:text-surface-400">{customer.organization}</p>
              )}

              <div className="space-y-1.5">
                {(customer.mobile || customer.phone) && (
                  <a
                    href={`tel:${customer.mobile || customer.phone}`}
                    className="flex items-center gap-2 text-xs text-surface-600 dark:text-surface-400 hover:text-primary-600 dark:hover:text-primary-400"
                  >
                    <Phone className="h-3 w-3 flex-shrink-0" />
                    {customer.mobile || customer.phone}
                  </a>
                )}
                {customer.email && (
                  <div className="flex items-center gap-2 text-xs text-surface-600 dark:text-surface-400">
                    <Mail className="h-3 w-3 flex-shrink-0" />
                    <span className="truncate">{customer.email}</span>
                  </div>
                )}
              </div>

              <div className="border-t border-surface-100 dark:border-surface-700 pt-2 flex items-center gap-4">
                <div className="flex items-center gap-1 text-xs text-surface-500 dark:text-surface-400">
                  <Ticket className="h-3 w-3" />
                  <span>{analytics?.total_tickets ?? '...'} tickets</span>
                </div>
                <div className="flex items-center gap-1 text-xs text-surface-500 dark:text-surface-400">
                  <DollarSign className="h-3 w-3" />
                  <span>{formatCurrency(Number(analytics?.lifetime_value ?? 0))} LTV</span>
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </span>
  );
}
