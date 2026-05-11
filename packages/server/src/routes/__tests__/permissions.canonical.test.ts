import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { PERMISSIONS } from '@bizarre-crm/shared';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const routesDir = path.resolve(__dirname, '..');
const canonical = new Set<string>(Object.values(PERMISSIONS));

function routeFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === '__tests__' ? [] : routeFiles(fullPath);
    return entry.isFile() && entry.name.endsWith('.ts') ? [fullPath] : [];
  });
}

describe('route permission keys', () => {
  it('uses only canonical shared permission literals', () => {
    const unknown: string[] = [];
    const matcher = /requirePermission\(\s*['"`]([^'"`]+)['"`]\s*\)/g;

    for (const file of routeFiles(routesDir)) {
      const source = fs.readFileSync(file, 'utf8');
      for (const match of source.matchAll(matcher)) {
        const key = match[1];
        if (!canonical.has(key)) {
          unknown.push(`${path.relative(routesDir, file)}: ${key}`);
        }
      }
    }

    expect(unknown).toEqual([]);
  });
});
