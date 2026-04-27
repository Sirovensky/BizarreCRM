/**
 * Performance reviews — criticalaudit.md §53 idea #8.
 *
 * Admin-only. Pick an employee on the left, see their review history on the
 * right; "New review" form below. Ratings are 1-5 stars. Notes are required.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Star, Trash2, Loader2, ShieldOff } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { useAuthStore } from '@/stores/authStore';

interface Employee {
  id: number;
  first_name: string;
  last_name: string;
  role: string;
}

interface Review {
  id: number;
  user_id: number;
  reviewer_user_id: number;
  reviewer_first: string | null;
  reviewer_last: string | null;
  period_start: string | null;
  period_end: string | null;
  notes: string;
  rating: number | null;
  created_at: string;
}

export function PerformanceReviewsPage() {
  const queryClient = useQueryClient();
  // WEB-FG-008 (Fixer-B15 2026-04-25): page is admin-only by header comment
  // but had no client-side guard, so a logged-in technician hitting
  // /team/performance-reviews would render the form, fetch arbitrary
  // ?user_id= reviews, and trigger 403 toasts on every selectedUserId
  // flip. Server still enforces; this short-circuits the IDOR-shaped UI
  // surface so non-admins land on a friendly forbidden state instead.
  const user = useAuthStore((s) => s.user);
  const isAdmin = user?.role === 'admin';
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [draftNotes, setDraftNotes] = useState('');
  const [draftRating, setDraftRating] = useState<number>(0);

  const { data: employeesData } = useQuery({
    queryKey: ['employees', 'simple'],
    enabled: isAdmin,
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Employee[] }>('/employees');
      return res.data.data;
    },
  });
  const employees: Employee[] = employeesData || [];

  const { data: reviewsData } = useQuery({
    queryKey: ['team', 'reviews', selectedUserId],
    enabled: isAdmin && !!selectedUserId,
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Review[] }>(
        `/team/reviews?user_id=${selectedUserId}`,
      );
      return res.data.data;
    },
  });
  const reviews: Review[] = reviewsData || [];

  const createMut = useMutation({
    mutationFn: async () => {
      await api.post('/team/reviews', {
        user_id: selectedUserId,
        notes: draftNotes,
        rating: draftRating || null,
      });
    },
    onSuccess: () => {
      toast.success('Review saved');
      setDraftNotes('');
      setDraftRating(0);
      queryClient.invalidateQueries({ queryKey: ['team', 'reviews', selectedUserId] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to save'),
  });

  const deleteMut = useMutation({
    mutationFn: async (id: number) => {
      await api.delete(`/team/reviews/${id}`);
    },
    onSuccess: () => {
      toast.success('Review deleted');
      queryClient.invalidateQueries({ queryKey: ['team', 'reviews', selectedUserId] });
    },
  });

  if (!isAdmin) {
    return (
      <div className="p-6 max-w-6xl mx-auto">
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <ShieldOff className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-4" aria-hidden="true" />
          <h1 className="text-lg font-semibold text-surface-700 dark:text-surface-200">Admin access required</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400 mt-2 max-w-md">
            Performance reviews are restricted to administrators. Contact your shop admin if you need access.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <header className="mb-6">
        <h1 className="text-2xl font-bold text-gray-800 dark:text-surface-100">Performance Reviews</h1>
        <p className="text-sm text-gray-500 dark:text-surface-400">Admin-only notes and ratings per employee.</p>
      </header>

      <div className="grid grid-cols-[240px_1fr] gap-4">
        <aside className="bg-white dark:bg-surface-900 rounded-lg shadow border dark:border-surface-700 p-2 max-h-[600px] overflow-y-auto">
          {employees.map((e) => (
            <button
              key={e.id}
              className={`w-full text-left px-3 py-2 rounded text-sm ${
                selectedUserId === e.id
                  ? 'bg-primary-100 dark:bg-primary-900/40 text-primary-800 dark:text-primary-200 font-semibold'
                  : 'hover:bg-gray-50 dark:hover:bg-surface-800/60 text-gray-700 dark:text-surface-200'
              }`}
              onClick={() => setSelectedUserId(e.id)}
            >
              <div>
                {e.first_name} {e.last_name}
              </div>
              <div className="text-xs text-gray-500 dark:text-surface-400">{e.role}</div>
            </button>
          ))}
        </aside>

        <section className="space-y-4">
          {selectedUserId && (
            <div className="bg-white rounded-lg shadow border p-4">
              <h2 className="text-sm font-semibold text-gray-800 mb-2">New review</h2>
              <div className="flex items-center gap-1 mb-2">
                {[1, 2, 3, 4, 5].map((n) => (
                  <button
                    key={n}
                    className="focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 rounded"
                    onClick={() => setDraftRating(n)}
                  >
                    <Star
                      className={`w-6 h-6 ${
                        n <= draftRating ? 'fill-amber-400 text-amber-400' : 'text-gray-300'
                      }`}
                    />
                  </button>
                ))}
                {draftRating > 0 && (
                  <button
                    className="text-xs text-gray-500 ml-2"
                    onClick={() => setDraftRating(0)}
                  >
                    clear
                  </button>
                )}
              </div>
              <textarea
                className="w-full border rounded px-3 py-2 text-sm"
                rows={4}
                placeholder="Notes (private to managers)..."
                value={draftNotes}
                onChange={(e) => setDraftNotes(e.target.value)}
              />
              <button
                className="mt-2 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 disabled:opacity-50 inline-flex items-center"
                disabled={!draftNotes.trim() || createMut.isPending}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save review
              </button>
            </div>
          )}

          {selectedUserId && (
            <div className="bg-white rounded-lg shadow border">
              <div className="px-4 py-3 border-b text-sm font-semibold text-gray-800">
                Past reviews ({reviews.length})
              </div>
              {reviews.length === 0 && (
                <p className="px-4 py-6 text-sm text-gray-500 text-center">
                  No reviews yet for this employee.
                </p>
              )}
              <div className="divide-y">
                {reviews.map((r) => (
                  <div key={r.id} className="px-4 py-3 text-sm">
                    <div className="flex items-center justify-between">
                      <div className="text-xs text-gray-500">
                        {new Date(r.created_at).toLocaleDateString()} by{' '}
                        {r.reviewer_first} {r.reviewer_last}
                      </div>
                      <button
                        className="text-red-500 hover:text-red-700 disabled:opacity-40"
                        onClick={() => deleteMut.mutate(r.id)}
                        disabled={deleteMut.isPending && deleteMut.variables === r.id}
                        aria-label="Delete review"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                    <div className="flex items-center gap-1 mt-1">
                      {[1, 2, 3, 4, 5].map((n) => (
                        <Star
                          key={n}
                          className={`w-4 h-4 ${
                            r.rating !== null && n <= r.rating
                              ? 'fill-amber-400 text-amber-400'
                              : 'text-gray-200'
                          }`}
                        />
                      ))}
                    </div>
                    <p className="text-gray-700 whitespace-pre-wrap mt-2">{r.notes}</p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {!selectedUserId && (
            <div className="bg-white rounded-lg shadow border p-12 text-center text-gray-500">
              Pick an employee to view their reviews.
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
