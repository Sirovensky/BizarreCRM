// Compress a PNG to JPEG capping the long side. Args: inputPath [outputPath] [maxLongSide]
// Default max long side: 1900px. Default output: input with .jpg extension.
import sharp from '../node_modules/sharp/lib/index.js';
import { dirname, basename, extname, join } from 'node:path';
const [,, input, outArg, maxArg] = process.argv;
if (!input) { console.error('usage: node compress-shot.mjs <input> [output] [maxLongSide]'); process.exit(1); }
const max = maxArg ? Number.parseInt(maxArg, 10) : 1900;
if (!Number.isFinite(max) || max < 100) { console.error(`bad maxLongSide: ${maxArg}`); process.exit(1); }
const output = outArg || join(dirname(input), basename(input, extname(input)) + '.jpg');
const img = sharp(input);
const meta = await img.metadata();
const longSide = Math.max(meta.width, meta.height);
const opts = longSide > max ? (meta.width > meta.height ? { width: max } : { height: max }) : null;
let pipe = img;
if (opts) pipe = pipe.resize(opts);
await pipe.jpeg({ quality: 75 }).toFile(output);
console.log(`${input} → ${output} (max ${max}px)`);
