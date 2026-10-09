#!/usr/bin/env node
// Imports Omarchy's themes into Loci: palettes, wallpapers and the syntax-token
// mapping. Run it against a checkout of https://github.com/omacom/omarchy:
//
//   node scripts/import-omarchy-themes.mjs ../omarchy
//
// It reads themes/ and default/themed/ from the checkout (a sparse checkout of
// those two folders is enough), and rewrites
// src/features/settings/model/omarchyThemes.generated.ts, public/themes/ and wallpapers/.
// Originals are copied to wallpapers/ for CDN delivery; only picker thumbnails
// are bundled in public/themes/. Install `vips` to generate them (`--skip-images`
// regenerates only the catalog). Omarchy is MIT licensed; its license text is
// copied next to the wallpapers.
import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const skipImages = args.includes("--skip-images");
const source = args.find((arg) => !arg.startsWith("--"));
if (!source) {
  console.error("usage: node scripts/import-omarchy-themes.mjs <omarchy checkout> [--skip-images]");
  process.exit(1);
}
const omarchy = resolve(source);
const themesDir = join(omarchy, "themes");
if (!existsSync(themesDir)) {
  console.error(`${themesDir} does not exist; point this at an Omarchy checkout.`);
  process.exit(1);
}

// Keep in step with PALETTE_KEYS in src/features/settings/model/themes.ts.
const PALETTE_KEYS = [
  "background", "foreground", "accent", "selection", "muted",
  "dark_background", "darker_background", "lighter_background",
  "dark_foreground", "light_foreground", "bright_foreground",
  "red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown",
  "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta",
];
// Bundle thumbnails for the picker and loading fallback; fetch originals from the public source CDN.
const THUMB_WIDTH = 320;
const THUMB_QUALITY = 60;

const out = {
  catalog: join(root, "src/features/settings/model/omarchyThemes.generated.ts"),
  thumbs: join(root, "public/themes"),
  originals: join(root, "wallpapers"),
};
const HEX = /^#[0-9a-fA-F]{6}$/;

function git(...gitArgs) {
  return execFileSync("git", ["-C", omarchy, ...gitArgs], { encoding: "utf8" }).trim();
}

/** Omarchy's colors.toml files are flat `key = "value"` lines. */
function parseColors(text, file) {
  const values = {};
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.replace(/\s+#.*$/, "").trim();
    if (!line || line.startsWith("#")) continue;
    const match = /^([A-Za-z0-9_-]+)\s*=\s*"?([^"]*?)"?$/.exec(line);
    if (!match) throw new Error(`${file}:${index + 1}: cannot read "${raw}"`);
    values[match[1]] = match[2].trim();
  }
  return values;
}

const channels = (hex) => [1, 3, 5].map((at) => Number.parseInt(hex.slice(at, at + 2), 16));
const toHex = (rgb) => `#${rgb.map((c) => Math.round(c).toString(16).padStart(2, "0")).join("")}`;
const mix = (a, b, weight) => {
  const [x, y] = [channels(a), channels(b)];
  return toHex(x.map((c, i) => c * weight + y[i] * (1 - weight)));
};
const luminance = (hex) =>
  channels(hex)
    .map((c) => c / 255)
    .map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
    .reduce((sum, c, i) => sum + c * [0.2126, 0.7152, 0.0722][i], 0);

/** The fallbacks of Omarchy's own bin/omarchy-theme-color, so a theme that omits a shade gets the same one. */
function normalizePalette(raw, id) {
  const colors = {};
  for (const [key, value] of Object.entries(raw)) {
    if (key === "mode") continue;
    if (HEX.test(value)) colors[key] = value.toLowerCase();
  }
  for (const key of ["background", "foreground", "accent", "red", "green", "yellow", "blue", "magenta", "cyan"]) {
    if (!colors[key]) throw new Error(`${id}: colors.toml has no usable "${key}"`);
  }
  const set = (key, value) => { colors[key] ??= value; };
  set("light_foreground", colors.foreground);
  set("bright_foreground", colors.foreground);
  set("lighter_background", colors.background);
  set("dark_foreground", colors.foreground);
  set("muted", colors.dark_foreground);
  set("selection", colors.muted);
  set("orange", colors.yellow);
  set("brown", mix(colors.orange, "#000000", 0.5));
  set("dark_background", mix(colors.background, "#000000", 0.75));
  set("darker_background", mix(colors.background, "#000000", 0.5));
  for (const key of ["red", "yellow", "green", "cyan", "blue", "magenta"]) {
    set(`bright_${key}`, mix(colors[key], "#ffffff", 0.8));
  }
  return Object.fromEntries(PALETTE_KEYS.map((key) => [key, colors[key]]));
}

const titleCase = (slug) =>
  slug.split("-").filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" ");

function vips(...vipsArgs) {
  execFileSync("vips", vipsArgs, { stdio: ["ignore", "ignore", "pipe"] });
}

function generateThumb(from, toDir, id) {
  vips("thumbnail", from, `${join(toDir, id)}.thumb.webp[Q=${THUMB_QUALITY},strip]`, String(THUMB_WIDTH), "--size", "down");
}

const commit = git("rev-parse", "HEAD");
const branch = git("rev-parse", "--abbrev-ref", "HEAD");
const repository = git("remote", "get-url", "origin")
  .replace(/^git@github\.com:/, "https://github.com/")
  .replace(/\.git$/, "");

if (!skipImages) {
  rmSync(out.thumbs, { recursive: true, force: true });
  mkdirSync(out.thumbs, { recursive: true });
  rmSync(out.originals, { recursive: true, force: true });
  mkdirSync(out.originals, { recursive: true });
}

const themes = [];
for (const id of readdirSync(themesDir).filter((name) => statSync(join(themesDir, name)).isDirectory()).sort()) {
  const colorsFile = join(themesDir, id, "colors.toml");
  if (!existsSync(colorsFile)) continue;
  const raw = parseColors(readFileSync(colorsFile, "utf8"), colorsFile);
  const palette = normalizePalette(raw, id);
  const mode = raw.mode === "light" || raw.mode === "dark"
    ? raw.mode
    : luminance(palette.background) > 0.5 ? "light" : "dark";

  const wallpapers = [];
  const names = new Map();
  const backgrounds = join(themesDir, id, "backgrounds");
  const files = existsSync(backgrounds)
    ? readdirSync(backgrounds).filter((name) => /\.(png|jpe?g|webp)$/i.test(name)).sort()
    : [];
  for (const file of files) {
    const stem = basename(file, extname(file));
    // `omarchy.webp` is a wordmark placeholder, not artwork.
    if (stem.replace(/^\d+-/, "") === "omarchy") continue;
    const wallpaperId = stem.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    const base = titleCase(stem.replace(/^\d+-/, "").toLowerCase().replace(/[^a-z0-9]+/g, "-"));
    const seen = (names.get(base) ?? 0) + 1;
    names.set(base, seen);
    const ext = extname(file).slice(1).toLowerCase();
    wallpapers.push({ id: wallpaperId, name: seen === 1 ? base : `${base} ${seen}`, ext });
    if (!skipImages) {
      const thumbDir = join(out.thumbs, id);
      const origDir = join(out.originals, id);
      mkdirSync(thumbDir, { recursive: true });
      mkdirSync(origDir, { recursive: true });
      generateThumb(join(backgrounds, file), thumbDir, wallpaperId);
      copyFileSync(join(backgrounds, file), join(origDir, `${wallpaperId}.${ext}`));
    }
  }
  themes.push({ id, name: titleCase(id), mode, palette, wallpapers });
}

// Omarchy maps its palette onto TextMate scopes in its VS Code template.
const template = JSON.parse(readFileSync(join(omarchy, "default/themed/vscode-theme.json.tpl"), "utf8"));
const tokenRules = template.tokenColors.map((rule) => {
  const color = /^\{\{ (\w+) \}\}$/.exec(rule.settings.foreground ?? "")?.[1];
  if (!color || !PALETTE_KEYS.includes(color)) {
    throw new Error(`token rule "${rule.name}" uses an unsupported color ${rule.settings.foreground}`);
  }
  return {
    name: rule.name,
    scope: Array.isArray(rule.scope) ? rule.scope : [rule.scope],
    color,
    ...(rule.settings.fontStyle ? { fontStyle: rule.settings.fontStyle } : {}),
  };
});

const header = `// Generated by scripts/import-omarchy-themes.mjs. Do not edit by hand.
// Source: ${repository} (branch ${branch}, commit ${commit}), MIT License.
// Original wallpapers are under wallpapers/<theme>/<wallpaper>.<ext>; see wallpapers/LICENSE.
// Thumbnails (picker and loading fallback) are under public/themes/<theme>/<wallpaper>.thumb.webp.
import type { ThemeSource, TokenRule } from "./themes";

export const OMARCHY_SOURCE = ${JSON.stringify({ repository, branch, commit }, null, 2)} as const;

export const OMARCHY_THEME_SOURCES: readonly ThemeSource[] = ${JSON.stringify(themes, null, 2)};

/** The palette-to-TextMate mapping from Omarchy's default/themed/vscode-theme.json.tpl. */
export const OMARCHY_TOKEN_RULES: readonly TokenRule[] = ${JSON.stringify(tokenRules, null, 2)};
`;
writeFileSync(out.catalog, header);

if (existsSync(out.originals)) {
  const license = readFileSync(join(omarchy, "LICENSE"), "utf8");
  writeFileSync(
    join(out.originals, "LICENSE"),
    `The wallpapers in this folder come from the Omarchy repository\n${repository} (branch ${branch}, commit ${commit}).\nOmarchy is released under the license below. The repository does not record who made each image.\n\n${license}`,
  );
  writeFileSync(
    join(out.thumbs, "LICENSE"),
    `The wallpaper thumbnails in this folder come from the Omarchy repository\n${repository} (branch ${branch}, commit ${commit}).\nOmarchy is released under the license below. The repository does not record who made each image.\n\n${license}`,
  );
}

console.log(`${themes.length} themes, ${themes.reduce((sum, theme) => sum + theme.wallpapers.length, 0)} wallpapers, ${tokenRules.length} token rules from ${repository}@${commit.slice(0, 7)}`);
