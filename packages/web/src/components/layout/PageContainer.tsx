import { cn } from '@/utils/cn';

interface PageContainerProps {
  children: React.ReactNode;
  /** Override max-width. Defaults to max-w-7xl (canonical app width). */
  maxWidth?: 'sm' | 'md' | 'lg' | 'xl' | '2xl' | '3xl' | '4xl' | '5xl' | '6xl' | '7xl' | 'full';
  className?: string;
}

const MAX_WIDTH_MAP: Record<NonNullable<PageContainerProps['maxWidth']>, string> = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-xl',
  '2xl': 'max-w-2xl',
  '3xl': 'max-w-3xl',
  '4xl': 'max-w-4xl',
  '5xl': 'max-w-5xl',
  '6xl': 'max-w-6xl',
  '7xl': 'max-w-7xl',
  full: 'max-w-full',
};

/**
 * PageContainer — canonical page-level layout wrapper.
 *
 * Usage:
 *   <PageContainer>…page content…</PageContainer>
 *
 * Provides:
 *   - max-w-7xl centered container (override via `maxWidth` prop)
 *   - mx-auto centering
 *   - w-full so narrower viewports fill available space
 *
 * NOTE: AppShell already adds p-6 around the <main> area, so pages should
 * NOT add their own p-6 when using PageContainer.
 *
 * WEB-UIUX-194: replaces ad-hoc max-w-6xl / max-w-3xl / full-bleed / no-wrapper
 * patterns that made the app feel like 4 different products.
 */
export function PageContainer({ children, maxWidth = '7xl', className }: PageContainerProps) {
  return (
    <div className={cn('mx-auto w-full', MAX_WIDTH_MAP[maxWidth], className)}>
      {children}
    </div>
  );
}
