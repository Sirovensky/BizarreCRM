import { useAuthStore } from '@/stores/authStore';

// ─── Types ───────────────────────────────────────────────────────────

interface PermissionBoundaryProps {
  roles: string[];
  children: React.ReactNode;
  fallback?: React.ReactNode;
}

// ─── Component ───────────────────────────────────────────────────────

export function PermissionBoundary({
  roles,
  children,
  fallback = null,
}: PermissionBoundaryProps) {
  const user = useAuthStore((s) => s.user);

  if (!user || !roles.includes(user.role)) {
    return <>{fallback}</>;
  }

  return <>{children}</>;
}
