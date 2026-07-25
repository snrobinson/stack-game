// Renders the App Store icon to a 1024x1024 PNG.
//
// Written as a script rather than committed as a binary blob so the icon stays
// editable: change the palette or the stack here and regenerate. It uses the
// same isometric projection and per-face shading as the game, so the icon and
// the first frame of gameplay agree with each other.
//
// Run: node Tools/icon-generator/generate-icon.mjs

import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = 1024;
const SS = 2; // supersampling factor; 2x2 = 4 samples per output pixel
const W = OUT * SS;
const H = OUT * SS;

// ---------------------------------------------------------------------------
// Canvas
// ---------------------------------------------------------------------------

const pixels = new Float64Array(W * H * 3);

function setPixel(x, y, r, g, b) {
  const i = (y * W + x) * 3;
  pixels[i] = r;
  pixels[i + 1] = g;
  pixels[i + 2] = b;
}

function blendPixel(x, y, r, g, b, a) {
  if (x < 0 || y < 0 || x >= W || y >= H || a <= 0) return;
  const i = (y * W + x) * 3;
  pixels[i] += (r - pixels[i]) * a;
  pixels[i + 1] += (g - pixels[i + 1]) * a;
  pixels[i + 2] += (b - pixels[i + 2]) * a;
}

/// Scanline fill for a convex polygon.
function fillPolygon(points, [r, g, b], alpha = 1) {
  let minY = Infinity;
  let maxY = -Infinity;
  for (const [, y] of points) {
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  minY = Math.max(0, Math.floor(minY));
  maxY = Math.min(H - 1, Math.ceil(maxY));

  for (let y = minY; y <= maxY; y++) {
    const sampleY = y + 0.5;
    const crossings = [];
    for (let i = 0; i < points.length; i++) {
      const [x1, y1] = points[i];
      const [x2, y2] = points[(i + 1) % points.length];
      if (y1 === y2) continue;
      if (sampleY >= Math.min(y1, y2) && sampleY < Math.max(y1, y2)) {
        crossings.push(x1 + ((sampleY - y1) / (y2 - y1)) * (x2 - x1));
      }
    }
    if (crossings.length < 2) continue;
    crossings.sort((a, c) => a - c);
    for (let k = 0; k + 1 < crossings.length; k += 2) {
      const from = Math.max(0, Math.ceil(crossings[k] - 0.5));
      const to = Math.min(W - 1, Math.floor(crossings[k + 1] - 0.5));
      for (let x = from; x <= to; x++) blendPixel(x, y, r, g, b, alpha);
    }
  }
}

/// Soft elliptical glow, used for the shadow and the emissive pool.
function radialGlow(cx, cy, radiusX, radiusY, [r, g, b], strength, exponent = 2) {
  const x0 = Math.max(0, Math.floor(cx - radiusX));
  const x1 = Math.min(W - 1, Math.ceil(cx + radiusX));
  const y0 = Math.max(0, Math.floor(cy - radiusY));
  const y1 = Math.min(H - 1, Math.ceil(cy + radiusY));

  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      const dx = (x - cx) / radiusX;
      const dy = (y - cy) / radiusY;
      const d = Math.sqrt(dx * dx + dy * dy);
      if (d >= 1) continue;
      blendPixel(x, y, r, g, b, Math.pow(1 - d, exponent) * strength);
    }
  }
}

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------

// Proportions mirror the game: blockHeight/initialSize * heightScale/tileWidth
// works out to roughly 0.14, so the blocks read as slabs rather than columns.
const TILE = 690 * SS;
const BLOCK_H = 98 * SS;
const CX = W / 2;

// Centre the *composition*, not the origin. The stack extends upward from the
// base block, so the geometric middle sits well above CY.
const STACK_LEVELS = 3;
const CY = H / 2 + (STACK_LEVELS / 2) * BLOCK_H;

/// Matches `IsoProjection.project` in the game.
///
/// Note the *minus* on the (x + z) term. SpriteKit's y axis points up and this
/// canvas's points down, so without the flip the camera would end up in the
/// opposite octant and the visible faces would be the ones at maximum x and z
/// rather than minimum — the blocks render as flat plates with stray wings.
function project(x, y, z) {
  return [
    CX + (x - z) * TILE * 0.5,
    CY - (x + z) * TILE * 0.25 - y * BLOCK_H,
  ];
}

/// Same face brightnesses the game's analytic lighting produces.
const FACE_SHADE = { top: 1.0, left: 0.62, right: 0.45 };

function shade([r, g, b], face, glow = 0) {
  const k = FACE_SHADE[face];
  return [
    Math.min(255, r * k + glow * 255 * 0.35),
    Math.min(255, g * k + glow * 255 * 0.24),
    Math.min(255, b * k + glow * 255 * 0.08),
  ];
}

function drawBlock({ x, z, w, d, level, color, glow = 0 }) {
  const yLow = level;
  const yHigh = level + 1;
  const x1 = x + w;
  const z1 = z + d;

  // Back to front: sides first, then the top cap.
  fillPolygon(
    [project(x, yHigh, z), project(x, yHigh, z1), project(x, yLow, z1), project(x, yLow, z)],
    shade(color, 'left', glow),
  );
  fillPolygon(
    [project(x, yHigh, z), project(x1, yHigh, z), project(x1, yLow, z), project(x, yLow, z)],
    shade(color, 'right', glow),
  );
  fillPolygon(
    [project(x, yHigh, z), project(x1, yHigh, z), project(x1, yHigh, z1), project(x, yHigh, z1)],
    shade(color, 'top', glow),
  );
}

// Background: deep indigo, lifting to violet behind the tower.
for (let y = 0; y < H; y++) {
  const t = y / H;
  const r = 13 + t * 26;
  const g = 14 + t * 20;
  const b = 30 + t * 44;
  for (let x = 0; x < W; x++) setPixel(x, y, r, g, b);
}
radialGlow(CX, H * 0.46, W * 0.70, H * 0.52, [116, 88, 214], 0.34);

// Contact shadow, pooled under the base block.
radialGlow(CX, CY + TILE * 0.16, TILE * 0.72, TILE * 0.22, [3, 3, 10], 0.60);

const MARBLE = [234, 235, 242];
const STEEL = [170, 177, 196];
const GOLD = [255, 191, 82];

// Three blocks: two settled, one landing slightly proud of the stack. The offset
// is the point — a perfectly flush stack says "tower", this says "timing".
drawBlock({ x: -0.50, z: -0.50, w: 1.00, d: 1.00, level: 0, color: STEEL });
drawBlock({ x: -0.47, z: -0.47, w: 0.94, d: 0.94, level: 1, color: MARBLE });

// Emissive pool where the gold block meets the one below, as if it just landed.
radialGlow(...project(0, 2, 0), TILE * 0.62, TILE * 0.26, [255, 172, 60], 0.46);
drawBlock({ x: -0.41, z: -0.53, w: 0.88, d: 0.88, level: 2, color: GOLD, glow: 0.18 });

// Rim of light above the gold, to lift it off the background.
radialGlow(...project(0, 3.05, 0), TILE * 0.46, TILE * 0.13, [255, 226, 170], 0.30, 3);

// ---------------------------------------------------------------------------
// Downsample + encode
// ---------------------------------------------------------------------------

const out = Buffer.alloc(OUT * OUT * 4);
for (let y = 0; y < OUT; y++) {
  for (let x = 0; x < OUT; x++) {
    let r = 0;
    let g = 0;
    let b = 0;
    for (let sy = 0; sy < SS; sy++) {
      for (let sx = 0; sx < SS; sx++) {
        const i = ((y * SS + sy) * W + (x * SS + sx)) * 3;
        r += pixels[i];
        g += pixels[i + 1];
        b += pixels[i + 2];
      }
    }
    const n = SS * SS;
    const o = (y * OUT + x) * 4;
    out[o] = Math.round(Math.min(255, r / n));
    out[o + 1] = Math.round(Math.min(255, g / n));
    out[o + 2] = Math.round(Math.min(255, b / n));
    // Fully opaque: iOS rejects app icons with an alpha channel that is
    // actually used, and applies its own corner mask.
    out[o + 3] = 255;
  }
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(OUT, 0);
ihdr.writeUInt32BE(OUT, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 6; // colour type: RGBA
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

// Each scanline is prefixed with its filter byte (0 = none).
const raw = Buffer.alloc(OUT * (OUT * 4 + 1));
for (let y = 0; y < OUT; y++) {
  raw[y * (OUT * 4 + 1)] = 0;
  out.copy(raw, y * (OUT * 4 + 1) + 1, y * OUT * 4, (y + 1) * OUT * 4);
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

const here = dirname(fileURLToPath(import.meta.url));
const target = join(here, '../../StackGame/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, png);

console.log(`Wrote ${target} (${(png.length / 1024).toFixed(0)} KB, ${OUT}x${OUT})`);
