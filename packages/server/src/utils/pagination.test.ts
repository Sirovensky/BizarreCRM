import { describe, expect, it } from 'vitest';
import { paginateKnownTotal } from './pagination.js';

describe('paginateKnownTotal', () => {
  it('returns in-range page metadata and offset', () => {
    expect(paginateKnownTotal({ page: '3', pageSize: 25, total: 101 })).toEqual({
      requestedPage: 3,
      page: 3,
      pageSize: 25,
      total: 101,
      totalPages: 5,
      offset: 50,
      outOfBounds: false,
    });
  });

  it('caps out-of-range requests to the last known page', () => {
    expect(paginateKnownTotal({ page: '999999999', pageSize: 20, total: 45 })).toEqual({
      requestedPage: 999999999,
      page: 3,
      pageSize: 20,
      total: 45,
      totalPages: 3,
      offset: 40,
      outOfBounds: true,
    });
  });

  it('handles empty result sets without producing a large offset', () => {
    expect(paginateKnownTotal({ page: '5000', pageSize: 50, total: 0 })).toEqual({
      requestedPage: 5000,
      page: 1,
      pageSize: 50,
      total: 0,
      totalPages: 0,
      offset: 0,
      outOfBounds: true,
    });
  });

  it('can preserve legacy one-page-empty pagination metadata', () => {
    expect(paginateKnownTotal({
      page: '5000',
      pageSize: 50,
      total: 0,
      minimumTotalPages: 1,
    })).toMatchObject({
      page: 1,
      totalPages: 1,
      offset: 0,
      outOfBounds: true,
    });
  });
});
