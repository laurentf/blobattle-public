import zlib from 'node:zlib';

export function decode(buffer) {
  let pos = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  const idat = [];
  while (pos < buffer.length) {
    const length = buffer.readUInt32BE(pos);
    const type = buffer.toString('ascii', pos + 4, pos + 8);
    const data = buffer.subarray(pos + 8, pos + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const depth = data[8];
      const color = data[9];
      if (depth !== 8 || data[12] !== 0 || (color !== 2 && color !== 6)) {
        throw new Error(`unsupported png: depth ${depth}, color ${color}, interlace ${data[12]}`);
      }
      channels = color === 6 ? 4 : 3;
    } else if (type === 'IDAT') {
      idat.push(data);
    }
    pos += 12 + length;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = new Uint8Array(width * height * 4);
  const prev = new Uint8Array(stride);
  const line = new Uint8Array(stride);
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i += 1) {
      const a = i >= channels ? line[i - channels] : 0;
      const b = prev[i];
      const c = i >= channels ? prev[i - channels] : 0;
      let v = src[i];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) {
        const p = a + b - c;
        const pa = Math.abs(p - a);
        const pb = Math.abs(p - b);
        const pc = Math.abs(p - c);
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
      }
      line[i] = v & 255;
    }
    for (let x = 0; x < width; x += 1) {
      const o = (y * width + x) * 4;
      out[o] = line[x * channels];
      out[o + 1] = line[x * channels + 1];
      out[o + 2] = line[x * channels + 2];
      out[o + 3] = channels === 4 ? line[x * channels + 3] : 255;
    }
    prev.set(line);
  }
  return { width, height, pixels: out };
}

export function colours(image, box = null) {
  const { width, height, pixels } = image;
  const [x0, y0, x1, y1] = box ?? [0, 0, width, height];
  const seen = new Set();
  for (let y = y0; y < y1; y += 1) {
    for (let x = x0; x < x1; x += 1) {
      const o = (y * width + x) * 4;
      seen.add((pixels[o] >> 3) * 1024 + (pixels[o + 1] >> 3) * 32 + (pixels[o + 2] >> 3));
    }
  }
  return seen.size;
}

export function share(image, rgb, tolerance = 24, box = null) {
  const { width, height, pixels } = image;
  const [x0, y0, x1, y1] = box ?? [0, 0, width, height];
  let hit = 0;
  for (let y = y0; y < y1; y += 1) {
    for (let x = x0; x < x1; x += 1) {
      const o = (y * width + x) * 4;
      if (
        Math.abs(pixels[o] - rgb[0]) <= tolerance &&
        Math.abs(pixels[o + 1] - rgb[1]) <= tolerance &&
        Math.abs(pixels[o + 2] - rgb[2]) <= tolerance
      ) {
        hit += 1;
      }
    }
  }
  return hit / ((x1 - x0) * (y1 - y0));
}

export function changed(a, b, tolerance = 24, box = null) {
  const [x0, y0, x1, y1] = box ?? [0, 0, a.width, a.height];
  let hit = 0;
  for (let y = y0; y < y1; y += 1) {
    for (let x = x0; x < x1; x += 1) {
      const o = (y * a.width + x) * 4;
      if (
        Math.abs(a.pixels[o] - b.pixels[o]) > tolerance ||
        Math.abs(a.pixels[o + 1] - b.pixels[o + 1]) > tolerance ||
        Math.abs(a.pixels[o + 2] - b.pixels[o + 2]) > tolerance
      ) {
        hit += 1;
      }
    }
  }
  return hit / ((x1 - x0) * (y1 - y0));
}

export function centroid(image, rgb, tolerance = 24) {
  const { width, height, pixels } = image;
  let hit = 0;
  let sum = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const o = (y * width + x) * 4;
      if (
        Math.abs(pixels[o] - rgb[0]) <= tolerance &&
        Math.abs(pixels[o + 1] - rgb[1]) <= tolerance &&
        Math.abs(pixels[o + 2] - rgb[2]) <= tolerance
      ) {
        hit += 1;
        sum += y;
      }
    }
  }
  return hit === 0 ? null : sum / hit / height;
}
