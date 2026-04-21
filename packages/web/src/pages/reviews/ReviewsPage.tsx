import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Star, MessageSquare, CheckCircle, ChevronLeft, ChevronRight, Loader2, X,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { crmApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────

interface CustomerReview {
  id: number;
  ticket_id: number | null;
  customer_id: number | null;
  rating: number;
  comment: string | null;
  response: string | null;
  responded_at: string | null;
  public_posted: number;
  created_at: string;
  customer_first_name: string | null;
  customer_last_name: string | null;
  ticket_order_id: string | null;
}

// ─── Helpers ─────────────────────────────────────────────────────

function StarRow({ rating }: { rating: number }) {
  return (
    <span className="flex gap-0.5">
      {Array.from({ length: 5 }, (_, i) => (
        <Star
          key={i}
          className={cn(
            'h-3.5 w-3.5',
            i < rating ? 'fill-amber-400 text-amber-400' : 'fill-surface-200 text-surface-200 dark:fill-surface-700 dark:text-surface-700',
          )}
        />
      ))}
    </span>
  );
}

function customerLabel(r: CustomerReview): string {
  const name = [r.customer_first_name, r.customer_last_name].filter(Boolean).join(' ');
  return name || 'Anonymous';
}

// ─── Reply Modal ──────────────────────────────────────────────────

interface ReplyModalProps {
  review: CustomerReview;
  onClose: () => void;
}

function ReplyModal({ review, onClose }: ReplyModalProps) {
  const queryClient = useQueryClient();
  const [text, setText] = useState(review.response ?? '');

  const replyMut = useMutation({
    mutationFn: (response: string) => crmApi.replyToReview(review.id, { response }),
    onSuccess: () => {
      toast.success('Reply saved');
      queryClient.invalidateQueries({ queryKey: ['customer-reviews'] });
      onClose();
    },
    onError: () => toast.error('Failed to save reply'),
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div
        className="w-full max-w-lg rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100">
            {review.response ? 'Edit Reply' : 'Reply to Review'}
          </h2>
          <button aria-label="Close" onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="px-6 py-4 space-y-3">
          {/* Original review summary */}
          <div className="rounded-lg border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-900">
            <div className="flex items-center gap-2 mb-1">
              <StarRow rating={review.rating} />
              <span className="text-xs text-surface-500">{customerLabel(review)}</span>
            </div>
            {review.comment && (
              <p className="text-sm text-surface-700 dark:text-surface-300">{review.comment}</p>
            )}
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Your reply
            </label>
            <textarea
              rows={4}
              value={text}
              onChange={(e) => setText(e.target.value)}
              maxLength={2000}
              placeholder="Thank the customer and address their feedback..."
              className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500/20"
            />
            <p className="mt-0.5 text-right text-xs text-surface-400">{text.length}/2000</p>
          </div>
        </div>

        <div className="flex justify-end gap-3 border-t border-surface-200 px-6 py-3 dark:border-surface-700">
          <button
            onClick={onClose}
            className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300"
          >
            Cancel
          </button>
          <button
            onClick={() => replyMut.mutate(text)}
            disabled={replyMut.isPending || text.trim().length === 0}
            className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50"
          >
            {replyMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Save Reply
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────

export function ReviewsPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [ratingFilter, setRatingFilter] = useState<number | ''>('');
  const [repliedFilter, setRepliedFilter] = useState<'' | 'true' | 'false'>('');
  const [replyTarget, setReplyTarget] = useState<CustomerReview | null>(null);

  const params = {
    page,
    pagesize: 20,
    ...(ratingFilter !== '' ? { rating: ratingFilter } : {}),
    ...(repliedFilter !== '' ? { replied: repliedFilter } : {}),
  };

  const { data, isLoading } = useQuery({
    queryKey: ['customer-reviews', params],
    queryFn: () => crmApi.listReviews(params),
    placeholderData: (prev) => prev,
  });

  const reviews: CustomerReview[] = (data as { data?: { data?: { reviews?: CustomerReview[] } } })?.data?.data?.reviews ?? [];
  const pagination = (data as { data?: { data?: { pagination?: { total: number; total_pages: number; per_page: number } } } })?.data?.data?.pagination ?? { total: 0, total_pages: 1, per_page: 20 };

  const markPublicMut = useMutation({
    mutationFn: ({ id, public_posted }: { id: number; public_posted: boolean }) =>
      crmApi.replyToReview(id, { public_posted }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer-reviews'] });
    },
    onError: () => toast.error('Failed to update review'),
  });

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Customer Reviews</h1>
          <p className="text-surface-500 dark:text-surface-400">
            Moderate and reply to reviews submitted via the customer portal
          </p>
        </div>
      </div>

      {/* Filters */}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1.5">
          <span className="text-sm text-surface-600 dark:text-surface-400">Rating:</span>
          <select
            value={ratingFilter}
            onChange={(e) => { setRatingFilter(e.target.value === '' ? '' : Number(e.target.value) as number); setPage(1); }}
            className="rounded-lg border border-surface-200 bg-surface-50 px-2 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          >
            <option value="">All</option>
            {[5, 4, 3, 2, 1].map((r) => (
              <option key={r} value={r}>{r} star{r !== 1 ? 's' : ''}</option>
            ))}
          </select>
        </div>

        <div className="flex items-center gap-1.5">
          <span className="text-sm text-surface-600 dark:text-surface-400">Status:</span>
          <select
            value={repliedFilter}
            onChange={(e) => { setRepliedFilter(e.target.value as '' | 'true' | 'false'); setPage(1); }}
            className="rounded-lg border border-surface-200 bg-surface-50 px-2 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          >
            <option value="">All</option>
            <option value="false">Needs reply</option>
            <option value="true">Replied</option>
          </select>
        </div>
      </div>

      <div className="card overflow-hidden">
        {isLoading ? (
          <div className="flex items-center justify-center py-20">
            <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
          </div>
        ) : reviews.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20">
            <Star className="mb-4 h-14 w-14 text-surface-300 dark:text-surface-600" />
            <p className="text-lg font-medium text-surface-600 dark:text-surface-400">No reviews yet</p>
            <p className="mt-1 text-sm text-surface-400">
              Reviews submitted via the customer portal will appear here.
            </p>
          </div>
        ) : (
          <div className="divide-y divide-surface-100 dark:divide-surface-800">
            {reviews.map((r) => (
              <div key={r.id} className="px-5 py-4 hover:bg-surface-50 dark:hover:bg-surface-800/40 transition-colors">
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <StarRow rating={r.rating} />
                      <span className="text-sm font-medium text-surface-900 dark:text-surface-100">
                        {customerLabel(r)}
                      </span>
                      {r.ticket_order_id && (
                        <span className="text-xs text-surface-400">· {r.ticket_order_id}</span>
                      )}
                      <span className="text-xs text-surface-400">
                        · {new Date(r.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
                      </span>
                    </div>

                    {r.comment && (
                      <p className="text-sm text-surface-700 dark:text-surface-300 mb-2">{r.comment}</p>
                    )}

                    {r.response && (
                      <div className="mt-2 rounded-lg border border-primary-200 bg-primary-50/60 px-3 py-2 dark:border-primary-900 dark:bg-primary-950/30">
                        <p className="text-xs font-semibold text-primary-700 dark:text-primary-400 mb-0.5">
                          Your reply
                          {r.responded_at && (
                            <span className="ml-1 font-normal text-surface-400">
                              · {new Date(r.responded_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                            </span>
                          )}
                        </p>
                        <p className="text-sm text-surface-700 dark:text-surface-300">{r.response}</p>
                      </div>
                    )}
                  </div>

                  <div className="flex shrink-0 items-center gap-2">
                    {!r.responded_at && (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700 dark:bg-amber-900/40 dark:text-amber-400">
                        Needs reply
                      </span>
                    )}
                    <button
                      onClick={() => setReplyTarget(r)}
                      title={r.response ? 'Edit reply' : 'Reply'}
                      className="inline-flex items-center gap-1 rounded-lg border border-surface-200 px-2.5 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                    >
                      <MessageSquare className="h-3.5 w-3.5" />
                      {r.response ? 'Edit' : 'Reply'}
                    </button>
                    <button
                      title={r.public_posted ? 'Mark private' : 'Mark as publicly posted'}
                      onClick={() => markPublicMut.mutate({ id: r.id, public_posted: !r.public_posted })}
                      className={cn(
                        'rounded-lg p-1.5 transition-colors',
                        r.public_posted
                          ? 'text-green-600 hover:bg-green-50 dark:hover:bg-green-950/30'
                          : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700',
                      )}
                    >
                      <CheckCircle className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Pagination */}
        {pagination.total_pages > 1 && (
          <div className="flex items-center justify-between border-t border-surface-200 px-5 py-3 dark:border-surface-700">
            <p className="text-sm text-surface-500">
              {pagination.total === 0 ? 'No results' : (
                <>
                  Showing {(page - 1) * pagination.per_page + 1}–
                  {Math.min(page * pagination.per_page, pagination.total)} of {pagination.total}
                </>
              )}
            </p>
            <div className="flex items-center gap-1">
              <button
                aria-label="Previous page"
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
                className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-40 dark:hover:bg-surface-700"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button
                aria-label="Next page"
                disabled={page >= pagination.total_pages}
                onClick={() => setPage((p) => p + 1)}
                className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 disabled:opacity-40 dark:hover:bg-surface-700"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}
      </div>

      {replyTarget && (
        <ReplyModal review={replyTarget} onClose={() => setReplyTarget(null)} />
      )}
    </div>
  );
}
