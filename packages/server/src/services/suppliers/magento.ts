import * as cheerio from 'cheerio';
import { assertPublicUrl } from '../../utils/ssrfGuard.js';
import type {
  CatalogSource,
  SupplierFetchPartContext,
  SupplierFetchPartResult,
} from './types.js';

const REQUEST_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};

const RESPONSE_BODY_CAP_BYTES = 10 * 1024 * 1024;
const DEFAULT_PRICE_FRESHNESS_MS = 24 * 60 * 60 * 1000;

interface FetchMagentoSearchPageOptions {
  source: CatalogSource;
  baseUrl: string;
  url: string;
  page: number;
  context: SupplierFetchPartContext;
}

export async function fetchMagentoSearchPage({
  source,
  baseUrl,
  url,
  page,
  context,
}: FetchMagentoSearchPageOptions): Promise<SupplierFetchPartResult> {
  // Keep the scraper's outbound protections with each source plugin so future
  // suppliers inherit the same guardrails by using this helper.
  await assertPublicUrl(url);

  const res = await fetch(url, { headers: REQUEST_HEADERS, signal: AbortSignal.timeout(15000) });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} fetching ${url}`);
  }

  const contentLengthHeader = res.headers.get('content-length');
  if (contentLengthHeader) {
    const contentLength = parseInt(contentLengthHeader, 10);
    if (Number.isFinite(contentLength) && contentLength > RESPONSE_BODY_CAP_BYTES) {
      throw new Error(`Upstream response too large (${contentLength} bytes > ${RESPONSE_BODY_CAP_BYTES}) for ${url}`);
    }
  }

  const buf = await res.arrayBuffer();
  if (buf.byteLength > RESPONSE_BODY_CAP_BYTES) {
    throw new Error(`Upstream response too large (${buf.byteLength} bytes > ${RESPONSE_BODY_CAP_BYTES}) for ${url}`);
  }

  const html = Buffer.from(buf).toString('utf8');
  const $ = cheerio.load(html);
  const products = context.parseProductsFromHtml(html, baseUrl, source);
  const nextBtn = $('a.next, .pages-item-next:not(.disabled), a[title="Next"]').length > 0;
  const hasMore = nextBtn || (page < 2 && products.length >= 30);

  return { products, hasMore };
}

export function isPriceFreshWithin(
  lastSyncedAt: string | Date | null | undefined,
  now: Date = new Date(),
  maxAgeMs: number = DEFAULT_PRICE_FRESHNESS_MS,
): boolean {
  if (!lastSyncedAt) return false;
  const lastSynced = lastSyncedAt instanceof Date ? lastSyncedAt : new Date(lastSyncedAt);
  const lastSyncedMs = lastSynced.getTime();
  if (!Number.isFinite(lastSyncedMs)) return false;
  return now.getTime() - lastSyncedMs <= maxAgeMs;
}
