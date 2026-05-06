import { describe, expect, it } from 'vitest';

import { escapeCsvField, toCsv } from './csv';

describe('CSV renderer utility', () => {
  it('escapes quotes, commas, newlines, and spreadsheet formulas', () => {
    expect(escapeCsvField('ACME, Inc.')).toBe('"ACME, Inc."');
    expect(escapeCsvField('needs "quotes"')).toBe('"needs ""quotes"""');
    expect(escapeCsvField('line\nbreak')).toBe('"line\nbreak"');
    expect(escapeCsvField('=SUM(A1:A2)')).toBe("'=SUM(A1:A2)");
  });

  it('exports selected columns in a stable order', () => {
    const csv = toCsv(
      ['tenant', 'status'],
      [
        { tenant: 'north', status: 'online', ignored: true },
        { tenant: 'south', status: '@offline' },
      ],
    );

    expect(csv).toBe("tenant,status\nnorth,online\nsouth,'@offline\n");
  });
});
