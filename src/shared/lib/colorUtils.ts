export const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/;

export type Hsv = { h: number; s: number; v: number };
export type Rgb = { r: number; g: number; b: number };

export function isHexColor(value: string): boolean {
  return HEX_COLOR_RE.test(value);
}

export function normalizeHex(color: string): string {
  if (isHexColor(color)) return color.toLowerCase();
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  if (!ctx) return "#808080";
  ctx.fillStyle = color;
  const normalized = ctx.fillStyle;
  return normalized.startsWith("#") ? normalized.toLowerCase() : "#808080";
}

export function hexToHsv(hex: string): Hsv {
  const value = normalizeHex(hex);
  const r = Number.parseInt(value.slice(1, 3), 16) / 255;
  const g = Number.parseInt(value.slice(3, 5), 16) / 255;
  const b = Number.parseInt(value.slice(5, 7), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;

  let h = 0;
  if (delta !== 0) {
    if (max === r) h = ((g - b) / delta) % 6;
    else if (max === g) h = (b - r) / delta + 2;
    else h = (r - g) / delta + 4;
    h *= 60;
    if (h < 0) h += 360;
  }

  const s = max === 0 ? 0 : delta / max;
  return { h, s: s * 100, v: max * 100 };
}

export function hsvToHex(h: number, s: number, v: number): string {
  const sat = clamp(s, 0, 100) / 100;
  const val = clamp(v, 0, 100) / 100;
  const hue = ((h % 360) + 360) % 360;
  const c = val * sat;
  const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = val - c;

  let r = 0;
  let g = 0;
  let b = 0;
  if (hue < 60) [r, g, b] = [c, x, 0];
  else if (hue < 120) [r, g, b] = [x, c, 0];
  else if (hue < 180) [r, g, b] = [0, c, x];
  else if (hue < 240) [r, g, b] = [0, x, c];
  else if (hue < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];

  const toByte = (channel: number) =>
    Math.round(clamp((channel + m) * 255, 0, 255))
      .toString(16)
      .padStart(2, "0");

  return `#${toByte(r)}${toByte(g)}${toByte(b)}`;
}

/** Hue in degrees, saturation and lightness in percent, as the theme uses them. */
export function hslToRgb(
  hue: number,
  saturation: number,
  lightness: number,
): Rgb {
  const sat = clamp(saturation, 0, 100) / 100;
  const light = clamp(lightness, 0, 100) / 100;
  const h = ((hue % 360) + 360) % 360;
  const c = (1 - Math.abs(2 * light - 1)) * sat;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = light - c / 2;
  const [r, g, b] = [
    [c, x, 0],
    [x, c, 0],
    [0, c, x],
    [0, x, c],
    [x, 0, c],
    [c, 0, x],
  ][Math.floor(h / 60) % 6];
  const channel = (value: number) => Math.round(clamp(value + m, 0, 1) * 255);
  return { r: channel(r), g: channel(g), b: channel(b) };
}

export type Hsl = { h: number; s: number; l: number };

function hexChannels(hex: string): [number, number, number] {
  return [1, 3, 5].map((offset) =>
    Number.parseInt(hex.slice(offset, offset + 2), 16),
  ) as [number, number, number];
}

function toHex({ r, g, b }: Rgb): string {
  const byte = (channel: number) =>
    Math.round(clamp(channel, 0, 255)).toString(16).padStart(2, "0");
  return `#${byte(r)}${byte(g)}${byte(b)}`;
}

/** Hue in degrees, saturation and lightness in percent, from `#rrggbb`. */
export function hexToHsl(hex: string): Hsl {
  const [r, g, b] = hexChannels(hex).map((channel) => channel / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  const l = (max + min) / 2;
  if (delta === 0) return { h: 0, s: 0, l: l * 100 };
  let h: number;
  if (max === r) h = ((g - b) / delta) % 6;
  else if (max === g) h = (b - r) / delta + 2;
  else h = (r - g) / delta + 4;
  h = (h * 60 + 360) % 360;
  const s = delta / (1 - Math.abs(2 * l - 1));
  return { h, s: s * 100, l: l * 100 };
}

export function hslToHex(hue: number, saturation: number, lightness: number) {
  return toHex(hslToRgb(hue, saturation, lightness));
}

/** WCAG relative luminance of `#rrggbb`. */
export function relativeLuminance(hex: string): number {
  const [r, g, b] = hexChannels(hex).map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio between two `#rrggbb` colors, from 1 to 21. */
export function contrastRatio(a: string, b: string): number {
  const first = relativeLuminance(a);
  const second = relativeLuminance(b);
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

/** `weight` of `a` over the rest of `b`, mixed in sRGB like `color-mix`. */
export function mixHex(a: string, b: string, weight: number): string {
  const [ar, ag, ab] = hexChannels(a);
  const [br, bg, bb] = hexChannels(b);
  const w = clamp(weight, 0, 1);
  return toHex({
    r: ar * w + br * (1 - w),
    g: ag * w + bg * (1 - w),
    b: ab * w + bb * (1 - w),
  });
}

/** Which way a color has to move to stand out from `background`. */
function contrastDirection(background: string): "lighter" | "darker" {
  return contrastRatio(background, "#ffffff") >=
    contrastRatio(background, "#000000")
    ? "lighter"
    : "darker";
}

/**
 * Moves a color's lightness, keeping its hue and saturation, until `accepts`
 * does. A color that already passes is returned unchanged, so a palette is only
 * touched where it fails. Falls back to the extreme if nothing passes.
 */
export function liftToPass(
  color: string,
  background: string,
  accepts: (candidate: string) => boolean,
): string {
  if (accepts(color)) return color;
  const { h, s, l } = hexToHsl(color);
  const step = contrastDirection(background) === "lighter" ? 0.5 : -0.5;
  let candidate = color;
  for (let lightness = l + step; lightness >= 0 && lightness <= 100; lightness += step) {
    candidate = hslToHex(h, s, lightness);
    if (accepts(candidate)) return candidate;
  }
  return candidate;
}

/** The closest color to `color` that reads at `minimum`:1 against `background`. */
export function ensureContrast(
  color: string,
  background: string,
  minimum: number,
): string {
  return liftToPass(
    color,
    background,
    (candidate) => contrastRatio(candidate, background) >= minimum,
  );
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
