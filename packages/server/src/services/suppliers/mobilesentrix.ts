import { fetchMagentoSearchPage, isPriceFreshWithin } from './magento.js';
import type { SupplierSource } from './types.js';

const BASE_URL = 'https://www.mobilesentrix.com';

function buildSearchUrl(query: string, page: number): string {
  const encoded = encodeURIComponent(query);
  return page > 1
    ? `${BASE_URL}/catalogsearch/result/?q=${encoded}&p=${page}`
    : `${BASE_URL}/catalogsearch/result/?q=${encoded}`;
}

export const mobilesentrixSource: SupplierSource = {
  slug: 'mobilesentrix',
  displayName: 'Mobilesentrix',
  authType: 'none',
  fetchPart({ query, page, context }) {
    return fetchMagentoSearchPage({
      source: 'mobilesentrix',
      baseUrl: BASE_URL,
      url: buildSearchUrl(query, page),
      page,
      context,
    });
  },
  isPriceFresh: isPriceFreshWithin,
};
