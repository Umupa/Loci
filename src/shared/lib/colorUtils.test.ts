import { describe, expect, it } from "vitest";
import {
  contrastRatio,
  ensureContrast,
  hexToHsl,
  hslToHex,
  hslToRgb,
  liftToPass,
  mixHex,
  relativeLuminance,
} from "./colorUtils";

describe("hslToRgb", () => {
  it("matches the theme backgrounds the native window is filled with", () => {
    expect(hslToRgb(240, 0, 9)).toEqual({ r: 23, g: 23, b: 23 });
    expect(hslToRgb(240, 0, 97)).toEqual({ r: 247, g: 247, b: 247 });
  });

  it("tints toward the accent hue", () => {
    expect(hslToRgb(0, 100, 50)).toEqual({ r: 255, g: 0, b: 0 });
    expect(hslToRgb(120, 100, 50)).toEqual({ r: 0, g: 255, b: 0 });
    expect(hslToRgb(240, 100, 50)).toEqual({ r: 0, g: 0, b: 255 });
  });

  it("wraps hue and clamps the ends", () => {
    expect(hslToRgb(-120, 100, 50)).toEqual(hslToRgb(240, 100, 50));
    expect(hslToRgb(600, 100, 50)).toEqual(hslToRgb(240, 100, 50));
    expect(hslToRgb(240, 0, -20)).toEqual({ r: 0, g: 0, b: 0 });
    expect(hslToRgb(240, 0, 120)).toEqual({ r: 255, g: 255, b: 255 });
  });
});

describe("hex and hsl", () => {
  it("round-trips through the lightness the theme tokens use", () => {
    for (const hex of ["#1a1b26", "#faf4ed", "#7aa2f7", "#ffcead", "#000000", "#ffffff"]) {
      const { h, s, l } = hexToHsl(hex);
      expect(hslToHex(h, s, l)).toBe(hex);
    }
  });

  it("reads known colors", () => {
    expect(hexToHsl("#ff0000")).toEqual({ h: 0, s: 100, l: 50 });
    expect(hexToHsl("#808080").s).toBe(0);
    expect(Math.round(hexToHsl("#1a1b26").h)).toBe(235);
  });
});

describe("contrast", () => {
  it("matches the WCAG reference values", () => {
    expect(relativeLuminance("#000000")).toBe(0);
    expect(relativeLuminance("#ffffff")).toBeCloseTo(1, 6);
    expect(contrastRatio("#000000", "#ffffff")).toBeCloseTo(21, 6);
    expect(contrastRatio("#ffffff", "#000000")).toBeCloseTo(21, 6);
    expect(contrastRatio("#777777", "#ffffff")).toBeCloseTo(4.48, 2);
    expect(contrastRatio("#336699", "#336699")).toBe(1);
  });

  it("mixes in sRGB", () => {
    expect(mixHex("#ffffff", "#000000", 0.5)).toBe("#808080");
    expect(mixHex("#ff0000", "#0000ff", 1)).toBe("#ff0000");
    expect(mixHex("#ff0000", "#0000ff", 0)).toBe("#0000ff");
  });
});

describe("ensureContrast", () => {
  it("leaves a color that already reads", () => {
    expect(ensureContrast("#ffffff", "#1a1b26", 4.5)).toBe("#ffffff");
  });

  it("lightens on a dark background and keeps the hue", () => {
    const fixed = ensureContrast("#414868", "#1a1b26", 4.5);
    expect(contrastRatio(fixed, "#1a1b26")).toBeGreaterThanOrEqual(4.5);
    expect(Math.abs(hexToHsl(fixed).h - hexToHsl("#414868").h)).toBeLessThan(3);
    expect(hexToHsl(fixed).l).toBeGreaterThan(hexToHsl("#414868").l);
  });

  it("darkens on a light background", () => {
    const fixed = ensureContrast("#df8e1d", "#eff1f5", 4.5);
    expect(contrastRatio(fixed, "#eff1f5")).toBeGreaterThanOrEqual(4.5);
    expect(hexToHsl(fixed).l).toBeLessThan(hexToHsl("#df8e1d").l);
  });

  it("stops at the extreme when nothing can pass", () => {
    expect(ensureContrast("#777777", "#808080", 21)).toBe("#000000");
  });

  it("accepts any predicate", () => {
    const lifted = liftToPass("#444444", "#000000", (hex) => hexToHsl(hex).l >= 60);
    expect(hexToHsl(lifted).l).toBeGreaterThanOrEqual(60);
    expect(hexToHsl(lifted).l).toBeLessThan(61);
  });
});
