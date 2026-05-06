import { fetchMagentoSearchPage, isPriceFreshWithin } from './magento.js';
import type { SupplierSource } from './types.js';

const BASE_URL = 'https://www.phonelcdparts.com';

function buildSearchUrl(query: string, page: number): string {
  const encoded = encodeURIComponent(query);
  return `${BASE_URL}/catalogsearch/result/?q=${encoded}&p=${page}&product_list_limit=36`;
}

export const phoneLcdPartsSource: SupplierSource = {
  slug: 'phonelcdparts',
  displayName: 'PhoneLcdParts',
  authType: 'none',
  fetchPart({ query, page, context }) {
    return fetchMagentoSearchPage({
      source: 'phonelcdparts',
      baseUrl: BASE_URL,
      url: buildSearchUrl(query, page),
      page,
      context,
    });
  },
  isPriceFresh: isPriceFreshWithin,
};
