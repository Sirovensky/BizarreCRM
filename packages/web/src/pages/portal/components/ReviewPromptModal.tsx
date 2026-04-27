/**
 * ReviewPromptModal — 5-star rating modal shown after pickup.
 *
 * Ratings >= portal_review_threshold get forwarded to the shop's Google
 * Reviews URL via the funnel defined by the marketing module schema.
 * Ratings below threshold are stored locally so owners can respond
 * privately without the damage hitting public review sites.
 */
import React, { useEffect, useState } from 'react';
import { submitReview } from './enrichApi';
import { usePortalI18n } from '../i18n';

interface ReviewPromptModalProps {
  ticketId: number;
  open: boolean;
  onClose: () => void;
}

export function ReviewPromptModal({
  ticketId,
  open,
  onClose,
}: ReviewPromptModalProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [rating, setRating] = useState<number>(0);
  const [hover, setHover] = useState<number>(0);
  const [comment, setComment] = useState<string>('');
  const [phase, setPhase] = useState<'ask' | 'thanks' | 'google'>('ask');
  const [googleUrl, setGoogleUrl] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState<boolean>(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  const handleSubmit = async (): Promise<void> => {
    if (rating < 1) return;
    setSubmitting(true);
    try {
      const result = await submitReview(ticketId, rating, comment);
      if (result.forward_url) {
        setGoogleUrl(result.forward_url);
        setPhase('google');
      } else {
        setPhase('thanks');
      }
    } catch {
      setPhase('thanks');
    } finally {
      setSubmitting(false);
    }
  };

  const displayRating = hover || rating;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="review-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-sm w-full p-6"
      >
        {phase === 'ask' ? (
          <>
            <h2
              id="review-title"
              className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-1"
            >
              {t('review.title')}
            </h2>
            <p className="text-sm text-gray-600 dark:text-gray-300 mb-4">
              {t('review.prompt')}
            </p>
            <div
              role="radiogroup"
              aria-label={t('review.rating_label')}
              className="flex gap-1 justify-center mb-4"
            >
              {[1, 2, 3, 4, 5].map((n) => (
                <button
                  key={n}
                  type="button"
                  role="radio"
                  aria-checked={rating === n}
                  aria-label={`${n} stars`}
                  onMouseEnter={() => setHover(n)}
                  onMouseLeave={() => setHover(0)}
                  onClick={() => setRating(n)}
                  className="text-3xl transition-transform hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-400 focus-visible:ring-offset-2 rounded"
                >
                  <span className={n <= displayRating ? 'text-yellow-400' : 'text-gray-300 dark:text-gray-600'}>
                    {'\u2605'}
                  </span>
                </button>
              ))}
            </div>
            <label
              htmlFor="review-comment"
              className="block text-xs font-medium text-gray-600 dark:text-gray-400 mb-1"
            >
              {t('review.comment_label')}
            </label>
            <textarea
              id="review-comment"
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              rows={3}
              maxLength={2000}
              className="w-full rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-900 text-sm text-gray-900 dark:text-gray-100 p-2 mb-4 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
            />
            <div className="flex gap-2">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 rounded border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-200 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-700"
              >
                Later
              </button>
              <button
                type="button"
                onClick={handleSubmit}
                disabled={rating < 1 || submitting}
                className="flex-1 rounded bg-primary-600 hover:bg-primary-700 text-primary-950 py-2 text-sm font-medium disabled:opacity-50"
              >
                {t('review.submit')}
              </button>
            </div>
          </>
        ) : null}

        {phase === 'thanks' ? (
          <div className="text-center">
            <div className="text-4xl mb-2" aria-hidden="true">
              {'\u{1F64F}'}
            </div>
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
              {t('review.thanks')}
            </h2>
            <button
              type="button"
              onClick={onClose}
              className="rounded bg-primary-600 hover:bg-primary-700 text-primary-950 px-4 py-2 text-sm font-medium"
            >
              Close
            </button>
          </div>
        ) : null}

        {phase === 'google' && googleUrl ? (
          <div className="text-center">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-2">
              {t('review.thanks')}
            </h2>
            <p className="text-sm text-gray-600 dark:text-gray-300 mb-4">
              {t('review.google_prompt')}
            </p>
            <div className="flex flex-col gap-2">
              <a
                href={googleUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded bg-primary-600 hover:bg-primary-700 text-primary-950 py-2 text-sm font-medium"
                onClick={onClose}
              >
                {t('review.google_button')}
              </a>
              <button
                type="button"
                onClick={onClose}
                className="text-sm text-gray-500 dark:text-gray-400 py-1"
              >
                Maybe later
              </button>
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
