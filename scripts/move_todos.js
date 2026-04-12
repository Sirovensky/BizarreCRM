const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const todoPath = path.join(root, 'TODO.md');
const doneTodosPath = path.join(root, 'DONETODOS.md');
const note = '> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).';
const formatNote = '> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).';

const content = fs.readFileSync(todoPath, 'utf8');
const lines = content.split(/\r?\n/);

const remainingLines = [];
const doneLines = [];

for (const line of lines) {
  if (/^\s*-\s*\[[xX]\]/.test(line)) {
    doneLines.push(line);
  } else if (line.trim() !== note && line.trim() !== formatNote) {
    remainingLines.push(line);
  }
}

let frontMatterEnd = -1;
let markerCount = 0;
for (let i = 0; i < remainingLines.length; i += 1) {
  if (remainingLines[i].trim() === '---') {
    markerCount += 1;
    if (markerCount === 2) {
      frontMatterEnd = i;
      break;
    }
  }
}

const noteBlock = ['', note, formatNote, ''];
if (frontMatterEnd !== -1) {
  remainingLines.splice(frontMatterEnd + 1, 0, ...noteBlock);
} else {
  remainingLines.unshift(...noteBlock);
}

const existingDone = fs.existsSync(doneTodosPath)
  ? fs.readFileSync(doneTodosPath, 'utf8').split(/\r?\n/).filter((line) => line && line !== '# Completed Tasks')
  : [];
const archived = Array.from(new Set([...existingDone, ...doneLines]));

fs.writeFileSync(todoPath, `${remainingLines.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd()}\n`, 'utf8');
fs.writeFileSync(doneTodosPath, `# Completed Tasks\n\n${archived.join('\n')}\n`, 'utf8');

console.log(`Moved ${doneLines.length} completed task(s) to DONETODOS.md`);
