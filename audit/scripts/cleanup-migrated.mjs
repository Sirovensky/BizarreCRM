// Remove items from TODO.md that already appear as closed in DONETODOS.md
// (same ID). Reads the DONE file, extracts item IDs ("- [x] ID. ..."),
// and strips matching "- [ ] ID." lines from TODO.md.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const TODO = join(ROOT, 'TODO.md');
const DONE = join(ROOT, 'DONETODOS.md');

const doneText = readFileSync(DONE, 'utf8');
const closed = new Set();
for (const line of doneText.split(/\r?\n/)) {
  const m = line.match(/^- \[x\] (~?~?[A-Z]+[0-9A-Za-z-]*)\./);
  if (m) closed.add(m[1].replace(/^~~|~~$/g, ''));
}
console.log(`${closed.size} closed IDs in DONETODOS`);

const todoLines = readFileSync(TODO, 'utf8').split(/\r?\n/);
const out = [];
let removed = 0;
for (let i = 0; i < todoLines.length; i++) {
  const line = todoLines[i];
  const m = line.match(/^- \[ \] ([A-Z]+[0-9A-Za-z-]*)\./);
  if (m && closed.has(m[1])) {
    removed++;
    // Also swallow a single blank line that typically follows. Keep structure.
    if (i + 1 < todoLines.length && todoLines[i + 1].trim() === '') i++;
    continue;
  }
  out.push(line);
}
writeFileSync(TODO, out.join('\n'));
console.log(`removed ${removed} items`);
