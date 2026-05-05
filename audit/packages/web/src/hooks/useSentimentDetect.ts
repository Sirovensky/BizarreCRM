import { useMemo } from 'react';

/**
 * Customer sentiment classifier — audit §51.5.
 *
 * Pure keyword-based. NO external AI. Returns one of four labels:
 *   - 'urgent'  — asap / urgent / emergency / right now → highest priority
 *   - 'angry'   — terrible / awful / broken / scam / unacceptable
 *   - 'happy'   — thanks / great / awesome / perfect / love it
 *   - 'neutral' — default (no matching keywords)
 *
 * The server mirrors this classifier in inbox.routes.ts so the web client
 * can render a badge without a round-trip and still log the result on demand.
 */

export type Sentiment = 'angry' | 'happy' | 'neutral' | 'urgent';

export interface SentimentResult {
  sentiment: Sentiment;
  score: number; // 0..100 confidence
}

const ANGRY_WORDS: readonly string[] = [
  'terrible', 'awful', 'worst', 'broken', 'scam',
  'angry', 'unacceptable', 'ridiculous',
];

const HAPPY_WORDS: readonly string[] = [
  'thanks', 'thank you', 'great', 'awesome',
  'perfect', 'love it', 'amazing', 'excellent',
];

const URGENT_WORDS: readonly string[] = [
  'asap', 'urgent', 'emergency', 'right now', 'immediately',
];

function countMatches(text: string, words: readonly string[]): number {
  return words.reduce((sum, w) => sum + (text.includes(w) ? 1 : 0), 0);
}

/**
 * Classify a single string of text. Pure function — no side effects, safe to
 * call outside the hook (e.g. from a list render loop to batch-classify
 * inbound messages). Precedence: urgent > angry > happy > neutral.
 */
export function classifySentiment(text: string): SentimentResult {
  if (!text) return { sentiment: 'neutral', score: 0 };
  const t = text.toLowerCase();

  const urgent = countMatches(t, URGENT_WORDS);
  const angry = countMatches(t, ANGRY_WORDS);
  const happy = countMatches(t, HAPPY_WORDS);

  if (urgent > 0) {
    return { sentiment: 'urgent', score: Math.min(100, 40 + urgent * 20) };
  }
  if (angry > happy) {
    return { sentiment: 'angry', score: Math.min(100, 40 + angry * 15) };
  }
  if (happy > angry) {
    return { sentiment: 'happy', score: Math.min(100, 40 + happy * 15) };
  }
  return { sentiment: 'neutral', score: 50 };
}

/**
 * Memoized hook — re-classifies only when the input text changes. Returns
 * a stable object so the caller can safely use it as a useEffect dep.
 */
export function useSentimentDetect(text: string | null | undefined): SentimentResult {
  return useMemo(() => classifySentiment(text ?? ''), [text]);
}
