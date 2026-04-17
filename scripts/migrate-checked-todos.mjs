// Move every already-checked `- [x]` item from TODO.md to DONETODOS.md.
// Only handles top-level `- [x]` lines (no sublines). Preserves headings.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const TODO = join(ROOT, 'TODO.md');
const DONE = join(ROOT, 'DONETODOS.md');

const todoLines = readFileSync(TODO, 'utf8').split(/\r?\n/);
const checkedIndices = [];
for (let i = 0; i < todoLines.length; i++) {
  if (/^- \[x\] /.test(todoLines[i])) checkedIndices.push(i);
}

if (checkedIndices.length === 0) {
  console.log('no checked lines to migrate');
  process.exit(0);
}

// Extract checked lines. Skip ones that begin with ~~ (strikethrough — already-noted non-action)
const migrating = [];
for (const i of checkedIndices) {
  migrating.push(todoLines[i]);
}

// Remove from TODO (and also drop any trailing blank line that follows a removed line
// only if the next line is also going to be removed — keep section structure intact).
const keep = new Set(Array.from({ length: todoLines.length }, (_, i) => i));
for (const i of checkedIndices) keep.delete(i);

// Collapse adjacent blank lines that appear only because of removal — not strictly needed;
// file-stable is fine. Just write what we keep.
const newTodo = Array.from({ length: todoLines.length }, (_, i) => keep.has(i) ? todoLines[i] : null)
  .filter(l => l !== null)
  .join('\n');

// Prepend to DONETODOS.md under today's date (create section if missing)
const doneContent = readFileSync(DONE, 'utf8');
const today = '2026-04-16';
const header = `## ${today}`;

let newDone;
if (doneContent.includes(header)) {
  // Insert migrated items right after the header (before any other lines under it)
  const idx = doneContent.indexOf(header);
  const afterHeader = idx + header.length;
  const before = doneContent.slice(0, afterHeader);
  const rest = doneContent.slice(afterHeader);
  newDone = before + '\n\n' + migrating.join('\n') + '\n' + rest;
} else {
  // Add a new section at top, right after "# Completed Tasks" line
  const firstLineEnd = doneContent.indexOf('\n');
  const head = doneContent.slice(0, firstLineEnd + 1);
  const tail = doneContent.slice(firstLineEnd + 1);
  newDone = head + '\n' + header + '\n\n' + migrating.join('\n') + '\n' + tail;
}

writeFileSync(TODO, newTodo);
writeFileSync(DONE, newDone);
console.log(`migrated ${migrating.length} items`);
