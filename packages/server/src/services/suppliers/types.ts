export type CatalogSource = 'mobilesentrix' | 'phonelcdparts';

export type SupplierAuthType = 'none';

export interface ScrapedProduct {
  externalId: string;
  name: string;
  sku: string | null;
  price: number;
  comparePrice: number | null;
  imageUrl: string | null;
  productUrl: string;
  category: string | null;
  inStock: boolean;
  compatibleDevices: string[];
}

export interface SupplierFetchPartContext {
  parseProductsFromHtml(html: string, baseUrl: string, supplier: CatalogSource): ScrapedProduct[];
}

export interface SupplierFetchPartParams {
  query: string;
  page: number;
  context: SupplierFetchPartContext;
}

export interface SupplierFetchPartResult {
  products: ScrapedProduct[];
  hasMore: boolean;
}

export interface SupplierSource {
  slug: CatalogSource;
  displayName: string;
  authType: SupplierAuthType;
  fetchPart(params: SupplierFetchPartParams): Promise<SupplierFetchPartResult>;
  isPriceFresh(lastSyncedAt: string | Date | null | undefined, now?: Date): boolean;
}
