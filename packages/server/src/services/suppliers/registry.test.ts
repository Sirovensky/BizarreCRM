import { afterEach, describe, expect, it, vi } from 'vitest';
import { CATALOG_SOURCES, getSupplierSource, supplierSources } from './registry.js';
import type { CatalogSource, ScrapedProduct } from './types.js';

vi.mock('../../utils/ssrfGuard.js', () => ({
  assertPublicUrl: vi.fn(async () => undefined),
}));

const html = '<ol><li class="product-item"><a class="product-item-link" href="/part">Part</a><span class="price">$1.00</span></li></ol>';

function stubFetchWith(body: string, extraHeaders: Record<string, string> = {}) {
  const fetchMock = vi.fn(async (url: string | URL | Request) => new Response(body, {
    status: 200,
    headers: { 'content-type': 'text/html', ...extraHeaders },
  }));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function parseProductsFromHtml(
  _html: string,
  baseUrl: string,
  supplier: CatalogSource,
): ScrapedProduct[] {
  return [{
    externalId: `${supplier}-1`,
    name: `${baseUrl} Part`,
    sku: null,
    price: 1,
    comparePrice: null,
    imageUrl: null,
    productUrl: `${baseUrl}/part`,
    category: null,
    inStock: true,
    compatibleDevices: [],
  }];
}

describe('supplier source registry', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('registers the supported supplier sources', () => {
    expect(CATALOG_SOURCES).toEqual(['mobilesentrix', 'phonelcdparts']);
    expect(supplierSources.map((source) => source.displayName)).toEqual(['Mobilesentrix', 'PhoneLcdParts']);
    expect(supplierSources.every((source) => source.authType === 'none')).toBe(true);
  });

  it('keeps Mobilesentrix search URLs compatible with the current scraper', async () => {
    const fetchMock = stubFetchWith(html);
    const result = await getSupplierSource('mobilesentrix').fetchPart({
      query: 'iphone screen',
      page: 1,
      context: { parseProductsFromHtml },
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://www.mobilesentrix.com/catalogsearch/result/?q=iphone%20screen',
      expect.any(Object),
    );
    expect(result.products[0]).toMatchObject({ externalId: 'mobilesentrix-1' });
    expect(result.hasMore).toBe(false);
  });

  it('keeps PhoneLcdParts search URLs compatible with the current scraper', async () => {
    const fetchMock = stubFetchWith(html);
    const result = await getSupplierSource('phonelcdparts').fetchPart({
      query: 'galaxy oled',
      page: 2,
      context: { parseProductsFromHtml },
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://www.phonelcdparts.com/catalogsearch/result/?q=galaxy%20oled&p=2&product_list_limit=36',
      expect.any(Object),
    );
    expect(result.products[0]).toMatchObject({ externalId: 'phonelcdparts-1' });
  });

  it('reports supplier prices fresh for the default one-day window', () => {
    const source = getSupplierSource('mobilesentrix');
    const now = new Date('2026-05-05T12:00:00Z');

    expect(source.isPriceFresh('2026-05-05T00:00:00Z', now)).toBe(true);
    expect(source.isPriceFresh('2026-05-03T00:00:00Z', now)).toBe(false);
    expect(source.isPriceFresh(null, now)).toBe(false);
  });
});
