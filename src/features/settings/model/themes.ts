import type { ThemeRegistration } from "shiki";
import {
  contrastRatio,
  ensureContrast,
  hexToHsl,
  liftToPass,
  mixHex,
  type Hsl,
} from "../../../shared/lib/colorUtils";
import {
  OMARCHY_THEME_SOURCES,
  OMARCHY_TOKEN_RULES,
} from "./omarchyThemes.generated";

/** The keys of an Omarchy `colors.toml` after its own fallbacks are applied. */
export const PALETTE_KEYS = [
  "background",
  "foreground",
  "accent",
  "selection",
  "muted",
  "dark_background",
  "darker_background",
  "lighter_background",
  "dark_foreground",
  "light_foreground",
  "bright_foreground",
  "red",
  "orange",
  "yellow",
  "green",
  "cyan",
  "blue",
  "magenta",
  "brown",
  "bright_red",
  "bright_yellow",
  "bright_green",
  "bright_cyan",
  "bright_blue",
  "bright_magenta",
] as const;

export type PaletteKey = (typeof PALETTE_KEYS)[number];
export type ThemePalette = Record<PaletteKey, string>;
export type ThemeMode = "dark" | "light";

export type ThemeSource = {
  id: string;
  name: string;
  mode: ThemeMode;
  palette: ThemePalette;
  wallpapers: { id: string; name: string }[];
};

/** A syntax rule from Omarchy's editor template: scopes painted in one palette color. */
export type TokenRule = {
  name: string;
  scope: string[];
  color: PaletteKey;
  fontStyle?: string;
};

export type ThemeWallpaper = {
  id: string;
  name: string;
  /** Same-origin URL of the shrunk wallpaper. */
  src: string;
  thumb: string;
  /** What the chat background setting stores to refer to this wallpaper. */
  path: string;
};

export type ThemeDefinition = Omit<ThemeSource, "wallpapers"> & {
  wallpapers: ThemeWallpaper[];
};

const ASSET_BASE = "/themes";
/** A chat background value that names a bundled wallpaper instead of a file. */
const WALLPAPER_PREFIX = "theme:";

function withWallpapers(source: ThemeSource): ThemeDefinition {
  return {
    ...source,
    wallpapers: source.wallpapers.map((wallpaper) => ({
      ...wallpaper,
      src: `${ASSET_BASE}/${source.id}/${wallpaper.id}.webp`,
      thumb: `${ASSET_BASE}/${source.id}/${wallpaper.id}.thumb.webp`,
      path: `${WALLPAPER_PREFIX}${source.id}/${wallpaper.id}`,
    })),
  };
}

export const THEMES: readonly ThemeDefinition[] =
  OMARCHY_THEME_SOURCES.map(withWallpapers);

export function findTheme(id: unknown): ThemeDefinition | null {
  return typeof id === "string"
    ? (THEMES.find((theme) => theme.id === id) ?? null)
    : null;
}

export function themesWithMode(mode: ThemeMode): ThemeDefinition[] {
  return THEMES.filter((theme) => theme.mode === mode);
}

export function isThemeWallpaperPath(value: unknown): value is string {
  return typeof value === "string" && value.startsWith(WALLPAPER_PREFIX);
}

/** The bundled wallpaper a chat background value refers to, if it still exists. */
export function resolveThemeWallpaper(
  value: string | null | undefined,
): { theme: ThemeDefinition; wallpaper: ThemeWallpaper } | null {
  if (!isThemeWallpaperPath(value)) return null;
  const [themeId, wallpaperId] = value.slice(WALLPAPER_PREFIX.length).split("/");
  const theme = findTheme(themeId);
  const wallpaper = theme?.wallpapers.find((item) => item.id === wallpaperId);
  return theme && wallpaper ? { theme, wallpaper } : null;
}

/** Primary text against the page. */
export const MIN_TEXT_CONTRAST = 7;
/**
 * Secondary text is the same ink at 45% strength, the level most hints and
 * descriptions use. Loci's own themes give 4.0:1 (dark) and 2.5:1 (light) there.
 * These are product baselines for muted text, not an accessibility-conformance
 * claim: small text at these levels can fall below WCAG AA's 4.5:1 threshold.
 */
export const SECONDARY_TEXT_STRENGTH = 0.45;
export const MIN_SECONDARY_CONTRAST: Record<ThemeMode, number> = {
  dark: 3,
  light: 2.5,
};
/** Links, headings, chips and syntax colors. */
export const MIN_READABLE_CONTRAST = 4.5;
/** Controls and icons painted in the accent. */
export const MIN_ACCENT_CONTRAST = 3;
/** Code sits on the page tinted this much toward the text color. */
export const CODE_SURFACE_MIX = 0.06;

export type ResolvedTheme = {
  mode: ThemeMode;
  background: string;
  content: string;
  /** The same two colors split into the channels the CSS tokens are built from. */
  backgroundHsl: Hsl;
  contentHsl: Hsl;
  accent: string;
  link: string;
  heading: string;
  skill: string;
  mention: string;
  diffAdd: string;
  diffAddText: string;
  diffDel: string;
  diffDelText: string;
};

const resolved = new Map<string, ResolvedTheme>();

/**
 * Maps a palette onto what Loci paints. Omarchy's colors are made for a
 * terminal, where a dim yellow or a muted gray is fine; here they carry text,
 * so each one that would be hard to read is moved along its own hue, and only
 * as far as it has to be.
 */
export function resolveTheme(theme: ThemeDefinition): ResolvedTheme {
  const cached = resolved.get(theme.id);
  if (cached) return cached;
  const { palette } = theme;
  const background = palette.background;
  const readable = (color: string) =>
    ensureContrast(color, background, MIN_READABLE_CONTRAST);
  const reads = (candidate: string) =>
    contrastRatio(candidate, background) >= MIN_TEXT_CONTRAST &&
    contrastRatio(
      mixHex(candidate, background, SECONDARY_TEXT_STRENGTH),
      background,
    ) >= MIN_SECONDARY_CONTRAST[theme.mode];
  // The palette's own brighter text colors come first; a color of our own is
  // the last resort.
  const content =
    [palette.foreground, palette.light_foreground, palette.bright_foreground].find(
      reads,
    ) ?? liftToPass(palette.foreground, background, reads);
  const result: ResolvedTheme = {
    mode: theme.mode,
    background,
    content,
    backgroundHsl: hexToHsl(background),
    contentHsl: hexToHsl(content),
    accent: ensureContrast(palette.accent, background, MIN_ACCENT_CONTRAST),
    link: readable(palette.blue),
    heading: readable(palette.magenta),
    skill: readable(palette.yellow),
    mention: readable(palette.cyan),
    diffAdd: palette.green,
    diffAddText: readable(palette.green),
    diffDel: palette.red,
    diffDelText: readable(palette.red),
  };
  resolved.set(theme.id, result);
  return result;
}

const codeThemes = new Map<string, ThemeRegistration>();

/** What code blocks are painted on, as far as the syntax colors are concerned. */
export function codeSurface(theme: ThemeDefinition): string {
  const { background, content } = resolveTheme(theme);
  return mixHex(content, background, CODE_SURFACE_MIX);
}

/**
 * A Shiki theme made of the palette, through the scope rules Omarchy ships for
 * its editor theme. Colors that would not read on a code block are lifted.
 */
export function buildCodeTheme(theme: ThemeDefinition): ThemeRegistration {
  const cached = codeThemes.get(theme.id);
  if (cached) return cached;
  const { background, content } = resolveTheme(theme);
  const surface = codeSurface(theme);
  // The surface is tinted toward the ink, which costs a little contrast.
  const text = ensureContrast(content, surface, MIN_TEXT_CONTRAST);
  const colors = new Map<PaletteKey, string>();
  const readable = (key: PaletteKey) => {
    let color = colors.get(key);
    if (!color) {
      color = ensureContrast(theme.palette[key], surface, MIN_READABLE_CONTRAST);
      colors.set(key, color);
    }
    return color;
  };
  const built: ThemeRegistration = {
    name: `loci-${theme.id}`,
    type: theme.mode,
    fg: text,
    bg: background,
    colors: { "editor.foreground": text, "editor.background": background },
    tokenColors: OMARCHY_TOKEN_RULES.map((rule) => ({
      name: rule.name,
      scope: rule.scope,
      settings: {
        foreground: readable(rule.color),
        ...(rule.fontStyle ? { fontStyle: rule.fontStyle } : {}),
      },
    })),
  };
  codeThemes.set(theme.id, built);
  return built;
}
