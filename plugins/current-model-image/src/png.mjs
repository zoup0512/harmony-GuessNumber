import { deflateSync, inflateSync } from 'node:zlib';

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const MAX_BYTES = 64 * 1024 * 1024;
const MAX_PIXELS = 16_000_000;
const CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
  let c = n;
  for (let k = 0; k < 8; k++) c = (c & 1) ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  CRC_TABLE[n] = c >>> 0;
}
const LINEAR = Float64Array.from({ length: 256 }, (_, n) => {
  const s = n / 255;
  return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
});

function dimensions(width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height) ||
      width < 1 || height < 1 || width > 4096 || height > 4096 ||
      width * height > MAX_PIXELS) {
    throw new Error('PNG dimensions must be 1..4096 and at most 16,000,000 pixels.');
  }
}

function crc32(buffer, start = 0, end = buffer.length) {
  let c = 0xffffffff;
  for (let i = start; i < end; i++) c = CRC_TABLE[(c ^ buffer[i]) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function asBuffer(value) {
  if (!Buffer.isBuffer(value) && !(value instanceof Uint8Array)) {
    throw new Error('PNG input must be a Buffer or Uint8Array.');
  }
  return Buffer.isBuffer(value) ? value : Buffer.from(value.buffer, value.byteOffset, value.byteLength);
}

function paeth(a, b, c) {
  const p = a + b - c;
  const da = Math.abs(p - a), db = Math.abs(p - b), dc = Math.abs(p - c);
  return da <= db && da <= dc ? a : db <= dc ? b : c;
}

function decodePng(value) {
  const buffer = asBuffer(value);
  if (buffer.length < 45 || buffer.length > MAX_BYTES || !buffer.subarray(0, 8).equals(SIGNATURE)) {
    throw new Error('Invalid PNG signature or file size (maximum 64 MiB).');
  }
  let width, height, colorType, channels;
  let offset = 8, seenHeader = false, seenData = false, endedData = false, seenEnd = false;
  let seenPalette = false, transparent = null, compressedBytes = 0;
  const parts = [];
  while (offset < buffer.length) {
    if (offset + 12 > buffer.length) throw new Error('Truncated PNG chunk.');
    const length = buffer.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (length > MAX_BYTES || end > buffer.length) throw new Error('Invalid PNG chunk length.');
    const type = buffer.toString('ascii', offset + 4, offset + 8);
    for (let i = offset + 4; i < offset + 8; i++) {
      const n = buffer[i];
      if (!((n >= 65 && n <= 90) || (n >= 97 && n <= 122))) throw new Error('Invalid PNG chunk type.');
    }
    if (buffer[offset + 6] & 32) throw new Error('Invalid PNG reserved chunk bit.');
    if (crc32(buffer, offset + 4, end - 4) !== buffer.readUInt32BE(end - 4)) {
      throw new Error('PNG CRC check failed.');
    }
    const data = buffer.subarray(offset + 8, end - 4);
    if (!seenHeader && type !== 'IHDR') throw new Error('PNG IHDR must be first.');
    if (seenData && type !== 'IDAT') endedData = true;
    if (type === 'IHDR') {
      if (seenHeader || length !== 13) throw new Error('Invalid PNG IHDR.');
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      dimensions(width, height);
      colorType = data[9];
      if (data[8] !== 8 || ![2, 6].includes(colorType) || data[10] !== 0 || data[11] !== 0 || data[12] !== 0) {
        throw new Error('Only 8-bit, non-interlaced RGB/RGBA PNG is supported.');
      }
      channels = colorType === 6 ? 4 : 3;
      seenHeader = true;
    } else if (type === 'PLTE') {
      if (seenPalette || seenData || transparent || !length || length % 3 || length > 768) {
        throw new Error('Invalid PNG palette.');
      }
      seenPalette = true;
    } else if (type === 'tRNS') {
      if (colorType !== 2 || seenData || transparent || length !== 6) throw new Error('Invalid PNG transparency.');
      transparent = [data.readUInt16BE(0), data.readUInt16BE(2), data.readUInt16BE(4)];
      if (transparent.some(n => n > 255)) throw new Error('Invalid 8-bit PNG transparency value.');
    } else if (type === 'IDAT') {
      if (endedData) throw new Error('PNG IDAT chunks must be consecutive.');
      seenData = true;
      compressedBytes += length;
      if (compressedBytes > MAX_BYTES) throw new Error('PNG compressed data exceeds 64 MiB.');
      parts.push(data);
    } else if (type === 'IEND') {
      if (!seenData || length !== 0 || end !== buffer.length) throw new Error('Invalid PNG ending.');
      seenEnd = true;
    } else if ((buffer[offset + 4] & 32) === 0) {
      throw new Error('Unsupported critical PNG chunk.');
    } else if (type === 'acTL' || type === 'fcTL' || type === 'fdAT') {
      throw new Error('Animated PNG is not supported.');
    }
    offset = end;
    if (seenEnd) break;
  }
  if (!seenEnd || !compressedBytes) throw new Error('PNG is missing image data or IEND.');
  const rowBytes = width * channels;
  const expected = (rowBytes + 1) * height;
  if (expected > MAX_BYTES) throw new Error('PNG decompressed data exceeds 64 MiB.');
  let inflated;
  try {
    const compressed = Buffer.concat(parts, compressedBytes);
    const result = inflateSync(compressed, { maxOutputLength: expected, info: true });
    inflated = result.buffer;
    if (result.engine.bytesWritten !== compressed.length) throw new Error('Trailing compressed data.');
  } catch {
    throw new Error('Invalid PNG compressed data or decompression limit exceeded.');
  }
  if (inflated.length !== expected) throw new Error('PNG decompressed length does not match its dimensions.');
  const pixels = Buffer.allocUnsafe(rowBytes * height);
  for (let y = 0; y < height; y++) {
    const input = y * (rowBytes + 1), output = y * rowBytes;
    const filter = inflated[input];
    if (filter > 4) throw new Error('Unsupported PNG row filter.');
    for (let x = 0; x < rowBytes; x++) {
      const a = x >= channels ? pixels[output + x - channels] : 0;
      const b = y > 0 ? pixels[output + x - rowBytes] : 0;
      const c = y > 0 && x >= channels ? pixels[output + x - rowBytes - channels] : 0;
      const predictor = filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b :
        filter === 3 ? Math.floor((a + b) / 2) : paeth(a, b, c);
      pixels[output + x] = (inflated[input + 1 + x] + predictor) & 255;
    }
  }
  const rgba = channels === 4 ? pixels : Buffer.allocUnsafe(width * height * 4);
  if (channels === 3) {
    for (let i = 0, p = 0; i < pixels.length; i += 3, p += 4) {
      rgba[p] = pixels[i]; rgba[p + 1] = pixels[i + 1]; rgba[p + 2] = pixels[i + 2];
      rgba[p + 3] = transparent && pixels[i] === transparent[0] &&
        pixels[i + 1] === transparent[1] && pixels[i + 2] === transparent[2] ? 0 : 255;
    }
  }
  return { width, height, bitDepth: 8, colorType, channels, hasAlpha: channels === 4 || !!transparent, bytes: buffer.length, rgba };
}

/** Validates chunks, CRCs, filters and the bounded decompressed image. */
export function inspectPng(buffer) {
  const { rgba, ...metadata } = decodePng(buffer);
  return metadata;
}

function chunk(type, data) {
  const output = Buffer.allocUnsafe(data.length + 12);
  output.writeUInt32BE(data.length, 0);
  output.write(type, 4, 4, 'ascii');
  data.copy(output, 8);
  output.writeUInt32BE(crc32(output, 4, output.length - 4), output.length - 4);
  return output;
}

/** Encodes an exact, row-major RGBA byte buffer as an 8-bit PNG. */
export function encodePng(width, height, rgba) {
  dimensions(width, height);
  const data = asBuffer(rgba);
  if (data.length !== width * height * 4) throw new Error('RGBA data length does not match PNG dimensions.');
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4);
  header[8] = 8; header[9] = 6;
  const stride = width * 4, rows = Buffer.allocUnsafe((stride + 1) * height);
  if (rows.length > MAX_BYTES) throw new Error('PNG decompressed data exceeds 64 MiB.');
  for (let y = 0; y < height; y++) {
    rows[y * (stride + 1)] = 0;
    data.copy(rows, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const output = Buffer.concat([SIGNATURE, chunk('IHDR', header), chunk('IDAT', deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
  if (output.length > MAX_BYTES) throw new Error('Encoded PNG exceeds 64 MiB.');
  return output;
}

function srgb(linear) {
  const n = Math.max(0, Math.min(1, linear));
  return Math.round(255 * (n <= 0.0031308 ? 12.92 * n : 1.055 * n ** (1 / 2.4) - 0.055));
}

/** Center-crop to fill; linear-sRGB bilinear interpolation with premultiplied alpha. */
export function resizePng(buffer, width, height) {
  dimensions(width, height);
  const source = decodePng(buffer);
  if (source.width === width && source.height === height) return Buffer.from(asBuffer(buffer));
  const output = Buffer.allocUnsafe(width * height * 4);
  const scale = Math.max(width / source.width, height / source.height);
  const cropWidth = width / scale, cropHeight = height / scale;
  const cropX = (source.width - cropWidth) / 2, cropY = (source.height - cropHeight) / 2;
  const left = new Uint32Array(width), right = new Uint32Array(width), weightX = new Float64Array(width);
  for (let x = 0; x < width; x++) {
    const position = Math.max(0, Math.min(source.width - 1, cropX + (x + 0.5) / scale - 0.5));
    left[x] = Math.floor(position); right[x] = Math.min(source.width - 1, left[x] + 1);
    weightX[x] = position - left[x];
  }
  const pixels = source.rgba;
  for (let y = 0; y < height; y++) {
    const position = Math.max(0, Math.min(source.height - 1, cropY + (y + 0.5) / scale - 0.5));
    const top = Math.floor(position), bottom = Math.min(source.height - 1, top + 1), fy = position - top;
    for (let x = 0; x < width; x++) {
      const fx = weightX[x];
      const a = (top * source.width + left[x]) * 4, b = (top * source.width + right[x]) * 4;
      const c = (bottom * source.width + left[x]) * 4, d = (bottom * source.width + right[x]) * 4;
      const wa = (1 - fx) * (1 - fy), wb = fx * (1 - fy), wc = (1 - fx) * fy, wd = fx * fy;
      const aa = pixels[a + 3] * wa, ab = pixels[b + 3] * wb, ac = pixels[c + 3] * wc, ad = pixels[d + 3] * wd;
      const alpha = aa + ab + ac + ad, out = (y * width + x) * 4;
      output[out + 3] = Math.round(alpha);
      for (let ch = 0; ch < 3; ch++) {
        output[out + ch] = alpha > 0 ? srgb((LINEAR[pixels[a + ch]] * aa + LINEAR[pixels[b + ch]] * ab +
          LINEAR[pixels[c + ch]] * ac + LINEAR[pixels[d + ch]] * ad) / alpha) : 0;
      }
    }
  }
  return encodePng(width, height, output);
}
