// Shrink a PNG via sharp. Usage: node shrink.js <in> <out> [width=480]
const sharp = require('../node_modules/sharp');
const [, , input, output, widthArg] = process.argv;
const width = parseInt(widthArg || '480', 10);
sharp(input)
  .resize({ width, withoutEnlargement: true })
  .png({ quality: 80, compressionLevel: 9, palette: true })
  .toFile(output)
  .then((info) => console.log(`${output} ${info.width}x${info.height} ${info.size}b`))
  .catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
