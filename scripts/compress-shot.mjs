// Compress a PNG to JPEG with max long side 1900px. Args: inputPath [outputPath]
// Default output: input with .jpg extension.
import sharp from '../node_modules/sharp/lib/index.js';
import { resolve, dirname, basename, extname, join } from 'node:path';
const [,, input, outArg] = process.argv;
if (!input) { console.error('usage: node compress-shot.mjs <input> [output]'); process.exit(1); }
const output = outArg || join(dirname(input), basename(input, extname(input)) + '.jpg');
const img = sharp(input);
const meta = await img.metadata();
const longSide = Math.max(meta.width, meta.height);
const opts = longSide > 1900 ? (meta.width > meta.height ? { width: 1900 } : { height: 1900 }) : null;
let pipe = img;
if (opts) pipe = pipe.resize(opts);
await pipe.jpeg({ quality: 75 }).toFile(output);
console.log(`${input} → ${output}`);
