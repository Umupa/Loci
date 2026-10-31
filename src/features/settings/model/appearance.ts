import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { hslToRgb, isHexColor, type Rgb } from "../../../shared/lib/colorUtils";
import { IS_LINUX, IS_MAC } from "../../../platform/tauri/platform";
import { readFlag, writeFlag } from "./storageFlags";
import { applyFonts } from "./fonts";
import {
  findTheme,
  isThemeWallpaperPath,
  resolveTheme,
  resolveThemeWallpaper,
  type ThemeDefinition,
} from "./themes";
import { applyUiScale, loadUiScale } from "./uiScale";
import {
  applyPreparedNewThreadBackground,
  clearPreparedNewThreadBackground,
} from "./newThreadBackgroundEffects";

const ACCENT_COLOR_KEY = "loci.accentColor";
const THEME_HUE_KEY = "loci.themeHue";
const THEME_SATURATION_KEY = "loci.themeSaturation";
const THEME_DARK_LIGHTNESS_KEY = "loci.themeDarkLightness";
const OPACITY_KEY = "loci.sidebarOpacity";
const BLUR_KEY = "loci.sidebarBlur";
const BODY_KEY = "loci.bodyGlass";
const SCHEME_KEY = "loci.colorScheme";
const TRANSCRIPT_LAYOUT_KEY = "loci.transcriptLayout";
const TRANSCRIPT_ANCHOR_KEY = "loci.transcriptAnchor";
const CHAT_BACKGROUND_PATH_KEY = "loci.chatBackgroundPath";
const CHAT_BACKGROUND_OPACITY_KEY = "loci.chatBackgroundOpacity";
const CHAT_BACKGROUND_EMPTY_OPACITY_KEY = "loci.chatBackgroundEmptyOpacity";
const CHAT_BACKGROUND_SESSION_OPACITY_KEY =
  "loci.chatBackgroundSessionOpacity";
const CHAT_BACKGROUND_SCOPE_KEY = "loci.chatBackgroundScope";
const NEW_THREAD_BACKGROUND_EFFECT_KEY = "loci.newThreadBackgroundEffect";
const THEME_ID_KEY = "loci.themeId";
const THEME_BOOT_KEY = "loci.themeBoot";
const THEME_WALLPAPER_AUTO_KEY = "loci.themeWallpaperAuto";
let chatBackgroundRevision = Date.now();
let nativeGlassReady = false;
let glassFadeTimer: number | undefined;
let glassSyncGeneration = 0;

export const CHAT_BACKGROUND_PATH_CHANGE_EVENT =
  "loci:chat-background-path-change";

export type ColorScheme = "dark" | "light";
export type ThemePreference = ColorScheme | "system";
export type TranscriptLayout = "full" | "chat";
export type ChatBackgroundScope = "empty" | "all";
export type NewThreadBackgroundEffect =
  "none" | "dither" | "ascii" | "halftone" | "scanlines" | "gradient-blur";

export const NEW_THREAD_BACKGROUND_EFFECTS: readonly NewThreadBackgroundEffect[] =
  ["none", "dither", "ascii", "halftone", "scanlines", "gradient-blur"];

export const NEW_THREAD_BACKGROUND_EFFECT_DEFAULT: NewThreadBackgroundEffect =
  "none";

export const NEW_THREAD_BACKGROUND_EFFECT_LABELS: Record<
  NewThreadBackgroundEffect,
  string
> = {
  none: "None",
  dither: "Dither",
  ascii: "ASCII",
  halftone: "Halftone",
  scanlines: "Scanlines",
  "gradient-blur": "Haze",
};

export const NEW_THREAD_BACKGROUND_EFFECT_DESCRIPTIONS: Record<
  NewThreadBackgroundEffect,
  string
> = {
  none: "Shows the original artwork.",
  dither: "Rebuilds the artwork with a dithered color palette.",
  ascii: "Recreates the artwork with colored characters on black.",
  halftone: "Recreates the artwork with colored print dots on black.",
  scanlines: "Adds a pronounced horizontal display-line texture.",
  "gradient-blur": "Blurs and fades the artwork into the background below.",
};

export const THEME_PREFERENCE_DEFAULT: ThemePreference = "dark";

export const ACCENT_COLOR_DEFAULT = null;

/** Fired on `window` whenever the color scheme flips (detail: ColorScheme). */
export const SCHEME_CHANGE_EVENT = "loci:schemechange";

/** Fired on `window` whenever the color theme changes (detail: theme id or null). */
export const THEME_CHANGE_EVENT = "loci:themechange";

export const TRANSCRIPT_LAYOUT_DEFAULT: TranscriptLayout = "chat";

export const TRANSCRIPT_ANCHOR_DEFAULT = true;

/** Fired on `window` whenever prompt-to-top anchoring flips (detail: boolean). */
export const TRANSCRIPT_ANCHOR_CHANGE_EVENT = "loci:transcriptanchorchange";

/** Fired on `window` whenever the transcript layout flips (detail: TranscriptLayout). */
export const TRANSCRIPT_LAYOUT_CHANGE_EVENT = "loci:transcriptlayoutchange";

export const THEME_HUE_MIN = 0;
export const THEME_HUE_MAX = 360;
export const THEME_HUE_DEFAULT = 240;

export const THEME_SATURATION_MIN = 0;
export const THEME_SATURATION_MAX = 100;
export const THEME_SATURATION_DEFAULT = 0;

export const THEME_DARK_LIGHTNESS_MIN = 0;
export const THEME_DARK_LIGHTNESS_MAX = 30;
export const THEME_DARK_LIGHTNESS_DEFAULT = 9;

export const SIDEBAR_OPACITY_MIN = 0.15;
export const SIDEBAR_OPACITY_MAX = 1;
export const SIDEBAR_OPACITY_DEFAULT = 0.85;

export const SIDEBAR_BLUR_MIN = 1;
export const SIDEBAR_BLUR_MAX = 64;
export const SIDEBAR_BLUR_DEFAULT = 24;


export const BODY_GLASS_DEFAULT = !IS_LINUX;

export const CHAT_BACKGROUND_OPACITY_MIN = 0.05;
export const CHAT_BACKGROUND_OPACITY_MAX = 0.65;
export const CHAT_BACKGROUND_OPACITY_DEFAULT = 0.24;
export const CHAT_BACKGROUND_EMPTY_OPACITY_DEFAULT =
  CHAT_BACKGROUND_OPACITY_DEFAULT;
export const CHAT_BACKGROUND_SESSION_OPACITY_DEFAULT =
  CHAT_BACKGROUND_OPACITY_DEFAULT;
export const CHAT_BACKGROUND_SCOPE_DEFAULT: ChatBackgroundScope = "all";

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function readNumber(key: string): number | null {
  try {
    const raw = localStorage.getItem(key);
    if (raw == null) return null;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

function writeNumber(key: string, value: number) {
  try {
    localStorage.setItem(key, String(value));
  } catch {
    // private mode / quota
  }
}

function normalizeAccentColor(value: unknown): string | null {
  return typeof value === "string" && isHexColor(value)
    ? value.toLowerCase()
    : ACCENT_COLOR_DEFAULT;
}

function accentForeground(color: string): "#000000" | "#ffffff" {
  const channels = [1, 3, 5].map((offset) => {
    const value = Number.parseInt(color.slice(offset, offset + 2), 16) / 255;
    return value <= 0.04045
      ? value / 12.92
      : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  const luminance =
    0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  return luminance > 0.179 ? "#000000" : "#ffffff";
}

export function loadAccentColor(): string | null {
  try {
    return normalizeAccentColor(localStorage.getItem(ACCENT_COLOR_KEY));
  } catch {
    return ACCENT_COLOR_DEFAULT;
  }
}

export function saveAccentColor(value: string | null) {
  try {
    const next = normalizeAccentColor(value);
    if (next == null) localStorage.removeItem(ACCENT_COLOR_KEY);
    else localStorage.setItem(ACCENT_COLOR_KEY, next);
  } catch {
    // private mode / quota
  }
}

export function applyAccentColor(value: string | null) {
  const next = normalizeAccentColor(value);
  document.documentElement.classList.toggle("has-user-accent", next != null);
  if (next == null) {
    document.documentElement.style.removeProperty("--user-accent-color");
    document.documentElement.style.removeProperty("--user-accent-foreground");
    return next;
  }
  document.documentElement.style.setProperty("--user-accent-color", next);
  document.documentElement.style.setProperty(
    "--user-accent-foreground",
    accentForeground(next),
  );
  return next;
}

export function loadThemeHue(): number {
  return Math.round(
    clamp(
      readNumber(THEME_HUE_KEY) ?? THEME_HUE_DEFAULT,
      THEME_HUE_MIN,
      THEME_HUE_MAX,
    ),
  );
}

export function saveThemeHue(value: number) {
  writeNumber(
    THEME_HUE_KEY,
    Math.round(clamp(value, THEME_HUE_MIN, THEME_HUE_MAX)),
  );
}

export function loadThemeSaturation(): number {
  return Math.round(
    clamp(
      readNumber(THEME_SATURATION_KEY) ?? THEME_SATURATION_DEFAULT,
      THEME_SATURATION_MIN,
      THEME_SATURATION_MAX,
    ),
  );
}

export function saveThemeSaturation(value: number) {
  writeNumber(
    THEME_SATURATION_KEY,
    Math.round(clamp(value, THEME_SATURATION_MIN, THEME_SATURATION_MAX)),
  );
}

export function loadThemeDarkLightness(): number {
  return Math.round(
    clamp(
      readNumber(THEME_DARK_LIGHTNESS_KEY) ?? THEME_DARK_LIGHTNESS_DEFAULT,
      THEME_DARK_LIGHTNESS_MIN,
      THEME_DARK_LIGHTNESS_MAX,
    ),
  );
}

export function saveThemeDarkLightness(value: number) {
  writeNumber(
    THEME_DARK_LIGHTNESS_KEY,
    Math.round(
      clamp(value, THEME_DARK_LIGHTNESS_MIN, THEME_DARK_LIGHTNESS_MAX),
    ),
  );
}

export function applyThemeDarkLightness(value: number) {
  const next = Math.round(
    clamp(value, THEME_DARK_LIGHTNESS_MIN, THEME_DARK_LIGHTNESS_MAX),
  );
  document.documentElement.style.setProperty(
    "--theme-dark-lightness",
    `${next}%`,
  );
  refreshNativeTint();
  return next;
}

export function applyThemeTint(hue: number, saturation: number) {
  const nextHue = Math.round(clamp(hue, THEME_HUE_MIN, THEME_HUE_MAX));
  const nextSaturation = Math.round(
    clamp(saturation, THEME_SATURATION_MIN, THEME_SATURATION_MAX),
  );
  // A named theme sets these channels itself; the stored tint comes back with
  // the default theme.
  if (!activeTheme()) {
    document.documentElement.style.setProperty("--theme-hue", String(nextHue));
    document.documentElement.style.setProperty(
      "--theme-saturation",
      `${nextSaturation}%`,
    );
  }
  refreshNativeTint();
  return { hue: nextHue, saturation: nextSaturation };
}

export function initAppearance() {
  document.documentElement.classList.toggle("is-mac", IS_MAC);
  applyFonts();
  // The page channels come first: the native window reads them below.
  applyThemeColors();
  applyEffectiveAccent();
  applyThemePreference(loadThemePreference());
  watchSystemColorScheme();
  applySidebarOpacity(loadSidebarOpacity());
  applySidebarBlur(loadSidebarBlur());
  applyBodyGlass(loadBodyGlass());
  applyChatBackground(loadChatBackgroundPath());
  applyChatBackgroundEmptyOpacity(loadChatBackgroundEmptyOpacity());
  applyChatBackgroundSessionOpacity(loadChatBackgroundSessionOpacity());
  applyChatBackgroundScope(loadChatBackgroundScope());
  void applyUiScale(loadUiScale());
}

function isThemePreference(value: unknown): value is ThemePreference {
  return value === "dark" || value === "light" || value === "system";
}

export function loadThemePreference(): ThemePreference {
  try {
    const raw = localStorage.getItem(SCHEME_KEY);
    return isThemePreference(raw) ? raw : THEME_PREFERENCE_DEFAULT;
  } catch {
    return THEME_PREFERENCE_DEFAULT;
  }
}

export function saveThemePreference(value: ThemePreference) {
  try {
    localStorage.setItem(SCHEME_KEY, value);
  } catch {
    // private mode / quota
  }
}

function systemQuery(): MediaQueryList | null {
  if (typeof window === "undefined" || !window.matchMedia) return null;
  return window.matchMedia("(prefers-color-scheme: light)");
}

function systemColorScheme(): ColorScheme {
  return systemQuery()?.matches ? "light" : "dark";
}

export function resolveColorScheme(value: ThemePreference): ColorScheme {
  return value === "system" ? systemColorScheme() : value;
}

export function isLightScheme(): boolean {
  return document.documentElement.classList.contains("theme-light");
}

/** The scheme in effect: a named theme is dark or light, otherwise the preference decides. */
export function currentColorScheme(): ColorScheme {
  return activeTheme()?.mode ?? resolveColorScheme(loadThemePreference());
}

export function applyThemePreference(value: ThemePreference): ColorScheme {
  const next = activeTheme()?.mode ?? resolveColorScheme(value);
  document.documentElement.classList.toggle("theme-light", next === "light");
  if (nativeGlassReady) syncNativeGlass(next);
  window.dispatchEvent(
    new CustomEvent<ColorScheme>(SCHEME_CHANGE_EVENT, { detail: next }),
  );
  const backgroundPath = loadChatBackgroundPath();
  if (
    backgroundPath &&
    document.documentElement.classList.contains("has-chat-background")
  ) {
    renderChatBackground(backgroundPath);
  }
  return next;
}

/** The page colour, also used by the native macOS glass tint. */
function opaqueWindowBackground(): Rgb {
  const style = getComputedStyle(document.documentElement);
  const read = (name: string, fallback: number) => {
    const value = Number.parseFloat(style.getPropertyValue(name));
    return Number.isFinite(value) ? value : fallback;
  };
  return hslToRgb(
    read("--theme-hue", THEME_HUE_DEFAULT),
    read("--theme-saturation", THEME_SATURATION_DEFAULT),
    read("--background-lightness", THEME_DARK_LIGHTNESS_DEFAULT),
  );
}

/** Compose both shared CSS tints into the native fill, including the shell's
 * base tint, so the steady page and a newly exposed resize edge match. */
function nativeWindowOpacity(): number {
  const style = getComputedStyle(document.documentElement);
  const glass = clamp(
    Number.parseFloat(style.getPropertyValue("--sidebar-opacity")) ||
      SIDEBAR_OPACITY_DEFAULT,
    SIDEBAR_OPACITY_MIN,
    SIDEBAR_OPACITY_MAX,
  );
  const storedBase = Number.parseFloat(
    style.getPropertyValue("--window-background-opacity"),
  );
  const base = Number.isFinite(storedBase) ? clamp(storedBase, 0, 1) : 0.4;
  return base + glass * (1 - base);
}

/** How long the page takes to reach opaque, from the same token the CSS uses. */
function glassFadeMs(): number {
  const value = getComputedStyle(document.documentElement)
    .getPropertyValue("--motion-feedback-duration")
    .trim();
  const milliseconds = parseFloat(value) * (value.endsWith("ms") ? 1 : 1000);
  return Number.isFinite(milliseconds) ? Math.max(0, milliseconds) : 0;
}

/**
 * `has-native-glass` follows the window, not the platform: Linux can turn glass
 * off in dark mode too. Whichever side moves second has to wait for the other,
 * or one of them shows through the gap - so entering glass settles the window
 * first, and leaving it fades the page first. A call that a newer one has
 * overtaken is dropped rather than left to settle last.
 */
export function syncNativeGlass(scheme: ColorScheme) {
  const enabled = scheme === "dark" && (!IS_LINUX || loadBodyGlass());
  const root = document.documentElement;
  const generation = ++glassSyncGeneration;
  const setWindow = () =>
    invoke<boolean>("set_window_glass_enabled", {
      enabled,
      background: opaqueWindowBackground(),
      ...(IS_MAC ? { opacity: nativeWindowOpacity() } : {}),
    }).catch(() => {});

  if (glassFadeTimer !== undefined) {
    window.clearTimeout(glassFadeTimer);
    glassFadeTimer = undefined;
  }

  if (enabled) {
    void setWindow().then((nativeTint) => {
      if (generation === glassSyncGeneration) {
        // An older native host or browser preview has no native tint. Keep
        // the CSS tint unless the window confirms it supplied one. If a
        // later update fails, retain the tint already applied by AppKit.
        if (IS_MAC && nativeTint === true) {
          root.classList.add("has-native-glass-tint");
        }
        root.classList.add("has-native-glass");
      }
    });
    return;
  }

  root.classList.remove("has-native-glass", "has-native-glass-tint");
  glassFadeTimer = window.setTimeout(() => {
    glassFadeTimer = undefined;
    void setWindow();
  }, glassFadeMs());
}

/** Settings update the native colour too, once the launch cover has painted. */
function refreshNativeTint() {
  if (nativeGlassReady && IS_MAC) {
    syncNativeGlass(isLightScheme() ? "light" : "dark");
  }
}

/** Applies native transparency once the opaque launch cover can be removed. */
export function activateWindowAppearance() {
  nativeGlassReady = true;
  syncNativeGlass(isLightScheme() ? "light" : "dark");
}

/** Keeps the "system" preference in sync when the OS flips appearance. */
export function watchSystemColorScheme() {
  const query = systemQuery();
  if (!query) return;
  query.addEventListener("change", () => {
    const preference = loadThemePreference();
    // A named theme is dark or light by itself, whatever the OS does.
    if (preference === "system" && !activeTheme()) {
      applyThemePreference(preference);
    }
  });
}

export function loadThemeId(): string | null {
  try {
    return findTheme(localStorage.getItem(THEME_ID_KEY))?.id ?? null;
  } catch {
    return null;
  }
}

export function saveThemeId(id: string | null) {
  try {
    if (id != null && findTheme(id)) localStorage.setItem(THEME_ID_KEY, id);
    else localStorage.removeItem(THEME_ID_KEY);
  } catch {
    // private mode / quota
  }
  saveThemeBoot(activeTheme());
}

/** Small validated snapshot for the inline splash script, before the bundle loads. */
function saveThemeBoot(theme: ThemeDefinition | null) {
  try {
    if (!theme) {
      localStorage.removeItem(THEME_BOOT_KEY);
      return;
    }
    const { h, s, l } = resolveTheme(theme).backgroundHsl;
    localStorage.setItem(THEME_BOOT_KEY, JSON.stringify([
      theme.id, theme.mode, Number(channel(h)), Number(channel(s)), Number(channel(l)),
    ]));
  } catch {
    // private mode / quota
  }
}

/** The named theme in effect, or null for Loci's own tint-based theme. */
export function activeTheme(): ThemeDefinition | null {
  return findTheme(loadThemeId());
}

/** Whether picking a theme also puts its wallpaper behind the chat. */
export const THEME_WALLPAPER_AUTO_DEFAULT = true;

export function loadThemeWallpaperAuto(): boolean {
  return readFlag(THEME_WALLPAPER_AUTO_KEY) ?? THEME_WALLPAPER_AUTO_DEFAULT;
}

export function saveThemeWallpaperAuto(value: boolean) {
  writeFlag(THEME_WALLPAPER_AUTO_KEY, value);
}

const THEME_CHANNELS = [
  "--content-hue",
  "--content-saturation",
  "--content-lightness",
  "--background-lightness",
  "--link-color",
  "--color-markdown-heading",
  "--color-skill",
  "--color-mention",
  "--color-diff-add",
  "--color-diff-add-fg",
  "--color-diff-del",
  "--color-diff-del-fg",
] as const;

function channel(value: number): string {
  return String(Math.round(value * 100) / 100);
}

/**
 * Writes the active theme's colors into the CSS channels the tokens are built
 * from, or hands the page back to the stored tint when there is none. Going
 * through the existing channels is what keeps the glass panes, the native
 * window tint and the background effects in step without knowing about themes.
 */
export function applyThemeColors(): ThemeDefinition | null {
  const root = document.documentElement;
  const theme = activeTheme();
  saveThemeBoot(theme);
  if (!theme) {
    root.classList.remove("has-theme");
    delete root.dataset.theme;
    for (const property of THEME_CHANNELS) root.style.removeProperty(property);
    applyThemeTint(loadThemeHue(), loadThemeSaturation());
    applyThemeDarkLightness(loadThemeDarkLightness());
    return null;
  }
  const colors = resolveTheme(theme);
  const set = (name: string, value: string) =>
    root.style.setProperty(name, value);
  set("--theme-hue", channel(colors.backgroundHsl.h));
  set("--theme-saturation", `${channel(colors.backgroundHsl.s)}%`);
  set("--background-lightness", `${channel(colors.backgroundHsl.l)}%`);
  set("--content-hue", channel(colors.contentHsl.h));
  set("--content-saturation", `${channel(colors.contentHsl.s)}%`);
  set("--content-lightness", `${channel(colors.contentHsl.l)}%`);
  set("--link-color", colors.link);
  set("--color-markdown-heading", colors.heading);
  set("--color-skill", colors.skill);
  set("--color-mention", colors.mention);
  set("--color-diff-add", colors.diffAdd);
  set("--color-diff-add-fg", colors.diffAddText);
  set("--color-diff-del", colors.diffDel);
  set("--color-diff-del-fg", colors.diffDelText);
  root.classList.add("has-theme");
  root.dataset.theme = theme.id;
  return theme;
}

/** The accent a person picked wins; otherwise the theme's; otherwise Loci's own. */
export function applyEffectiveAccent(): string | null {
  const theme = activeTheme();
  return applyAccentColor(
    loadAccentColor() ?? (theme ? resolveTheme(theme).accent : null),
  );
}

/**
 * A theme's wallpaper follows the theme only while the chat background is
 * empty or already one of the bundled wallpapers. A picture a person chose
 * stays, and so does a background they removed on purpose.
 */
function followThemeWallpaper(theme: ThemeDefinition | null) {
  const current = loadChatBackgroundPath();
  const bundled = isThemeWallpaperPath(current);
  let next: string | null | undefined;
  if (!theme) next = bundled ? null : undefined;
  else if (bundled || (current == null && loadThemeWallpaperAuto())) {
    next = theme.wallpapers[0]?.path ?? null;
  }
  if (next === undefined || next === current) return;
  saveChatBackgroundPath(next);
  applyChatBackground(next);
}

/** Switches the color theme; null returns to Loci's own tint-based theme. */
export function setTheme(id: string | null): ThemeDefinition | null {
  saveThemeId(id);
  const theme = applyThemeColors();
  applyThemePreference(loadThemePreference());
  applyEffectiveAccent();
  followThemeWallpaper(theme);
  window.dispatchEvent(
    new CustomEvent<string | null>(THEME_CHANGE_EVENT, {
      detail: theme?.id ?? null,
    }),
  );
  return theme;
}

export function loadSidebarOpacity(): number {
  return clamp(
    readNumber(OPACITY_KEY) ?? SIDEBAR_OPACITY_DEFAULT,
    SIDEBAR_OPACITY_MIN,
    SIDEBAR_OPACITY_MAX,
  );
}

export function saveSidebarOpacity(value: number) {
  writeNumber(
    OPACITY_KEY,
    clamp(value, SIDEBAR_OPACITY_MIN, SIDEBAR_OPACITY_MAX),
  );
}

export function applySidebarOpacity(value: number) {
  const next = clamp(value, SIDEBAR_OPACITY_MIN, SIDEBAR_OPACITY_MAX);
  document.documentElement.style.setProperty("--sidebar-opacity", String(next));
  refreshNativeTint();
  return next;
}

export function loadSidebarBlur(): number {
  return Math.round(
    clamp(
      readNumber(BLUR_KEY) ?? SIDEBAR_BLUR_DEFAULT,
      SIDEBAR_BLUR_MIN,
      SIDEBAR_BLUR_MAX,
    ),
  );
}

export function saveSidebarBlur(value: number) {
  writeNumber(
    BLUR_KEY,
    Math.round(clamp(value, SIDEBAR_BLUR_MIN, SIDEBAR_BLUR_MAX)),
  );
}

export function applySidebarBlur(value: number) {
  const next = Math.round(clamp(value, SIDEBAR_BLUR_MIN, SIDEBAR_BLUR_MAX));
  void invoke("set_window_background_blur", { radius: next });
  return next;
}

export function loadBodyGlass(): boolean {
  return readFlag(BODY_KEY) ?? BODY_GLASS_DEFAULT;
}

export function saveBodyGlass(value: boolean) {
  writeFlag(BODY_KEY, value);
}

export function applyBodyGlass(value: boolean) {
  document.documentElement.classList.toggle("glass-body", value);
  return value;
}

export function loadChatBackgroundPath(): string | null {
  try {
    const value = localStorage.getItem(CHAT_BACKGROUND_PATH_KEY)?.trim() || null;
    // A bundled wallpaper that no longer exists is no background at all.
    if (isThemeWallpaperPath(value) && !resolveThemeWallpaper(value)) return null;
    return value;
  } catch {
    return null;
  }
}

export function saveChatBackgroundPath(value: string | null) {
  try {
    if (value) localStorage.setItem(CHAT_BACKGROUND_PATH_KEY, value);
    else localStorage.removeItem(CHAT_BACKGROUND_PATH_KEY);
  } catch {
    // private mode / quota
  }
  if (typeof window === "undefined") return;
  window.dispatchEvent(new Event(CHAT_BACKGROUND_PATH_CHANGE_EVENT));
}

export function subscribeChatBackgroundPath(onStoreChange: () => void) {
  if (typeof window === "undefined") return () => {};
  window.addEventListener(CHAT_BACKGROUND_PATH_CHANGE_EVENT, onStoreChange);
  return () =>
    window.removeEventListener(
      CHAT_BACKGROUND_PATH_CHANGE_EVENT,
      onStoreChange,
    );
}

export function applyChatBackground(path: string | null) {
  const revision = ++chatBackgroundRevision;
  const root = document.documentElement;
  root.classList.toggle("has-chat-background", !!path);
  if (!path) {
    clearPreparedNewThreadBackground();
    return null;
  }
  renderChatBackground(path);
  if (isThemeWallpaperPath(path) && !wallpaperLocalPaths.has(path)) {
    void ensureThemeWallpaperCached(path).then((ok) => {
      // A slow download must not replace a newer selection or restore a removed image.
      if (ok && revision === chatBackgroundRevision) applyChatBackground(path);
    });
  }
  return path;
}

/** Maps "theme:<id>/<wid>" → asset:// URL of the downloaded original. */
const wallpaperLocalPaths = new Map<string, string>();
const wallpaperDownloads = new Map<string, Promise<boolean>>();

export function chatBackgroundSrc(path: string | null): string | null {
  if (!path) return null;
  if (isThemeWallpaperPath(path)) {
    const src = wallpaperLocalPaths.get(path)
      ?? resolveThemeWallpaper(path)?.wallpaper.thumb;
    return src ? `${src}?v=${chatBackgroundRevision}` : null;
  }
  return `${convertFileSrc(path)}?v=${chatBackgroundRevision}`;
}

/** Downloads the original wallpaper if not already cached, then populates wallpaperLocalPaths. */
function ensureThemeWallpaperCached(path: string): Promise<boolean> {
  if (wallpaperLocalPaths.has(path)) return Promise.resolve(true);
  const pending = wallpaperDownloads.get(path);
  if (pending) return pending;
  const resolved = resolveThemeWallpaper(path);
  if (!resolved) return Promise.resolve(false);
  const { theme, wallpaper } = resolved;
  const download = invoke<string>("download_wallpaper", {
    cdnUrl: wallpaper.cdnUrl,
    cacheKey: `${theme.id}/${wallpaper.id}.${wallpaper.ext}`,
  })
    .then((localPath) => {
      wallpaperLocalPaths.set(path, convertFileSrc(localPath));
      return true;
    })
    .catch(() => false)
    .finally(() => wallpaperDownloads.delete(path));
  wallpaperDownloads.set(path, download);
  return download;
}

function isNewThreadBackgroundEffect(
  value: unknown,
): value is NewThreadBackgroundEffect {
  return NEW_THREAD_BACKGROUND_EFFECTS.includes(
    value as NewThreadBackgroundEffect,
  );
}

export function loadNewThreadBackgroundEffect(): NewThreadBackgroundEffect {
  try {
    const raw = localStorage.getItem(NEW_THREAD_BACKGROUND_EFFECT_KEY);
    return isNewThreadBackgroundEffect(raw)
      ? raw
      : NEW_THREAD_BACKGROUND_EFFECT_DEFAULT;
  } catch {
    return NEW_THREAD_BACKGROUND_EFFECT_DEFAULT;
  }
}

export function saveNewThreadBackgroundEffect(
  effect: NewThreadBackgroundEffect,
) {
  try {
    localStorage.setItem(NEW_THREAD_BACKGROUND_EFFECT_KEY, effect);
  } catch {
    // private mode / quota
  }
}

function renderChatBackground(
  path: string,
  effect = loadNewThreadBackgroundEffect(),
) {
  const src = chatBackgroundSrc(path);
  if (!src) return;
  void applyPreparedNewThreadBackground(
    `${path}?v=${chatBackgroundRevision}`,
    src,
    effect,
    isLightScheme(),
  );
}

export function applyNewThreadBackgroundEffect(
  effect: NewThreadBackgroundEffect,
) {
  const path = loadChatBackgroundPath();
  if (path) renderChatBackground(path, effect);
  return effect;
}

export function setNewThreadBackgroundEffect(
  effect: NewThreadBackgroundEffect,
) {
  saveNewThreadBackgroundEffect(effect);
  applyNewThreadBackgroundEffect(effect);
  window.dispatchEvent(new Event(CHAT_BACKGROUND_PATH_CHANGE_EVENT));
}

export function loadChatBackgroundOpacity(): number {
  return loadChatBackgroundEmptyOpacity();
}

export function saveChatBackgroundOpacity(value: number) {
  const next = clamp(
    value,
    CHAT_BACKGROUND_OPACITY_MIN,
    CHAT_BACKGROUND_OPACITY_MAX,
  );
  saveChatBackgroundEmptyOpacity(next);
  saveChatBackgroundSessionOpacity(next);
  writeNumber(CHAT_BACKGROUND_OPACITY_KEY, next);
}

export function applyChatBackgroundOpacity(value: number) {
  const next = applyChatBackgroundEmptyOpacity(value);
  applyChatBackgroundSessionOpacity(next);
  return next;
}

function loadChatBackgroundOpacityValue(key: string): number {
  const next = clamp(
    readNumber(key) ??
      readNumber(CHAT_BACKGROUND_OPACITY_KEY) ??
      CHAT_BACKGROUND_OPACITY_DEFAULT,
    CHAT_BACKGROUND_OPACITY_MIN,
    CHAT_BACKGROUND_OPACITY_MAX,
  );
  return next;
}

function saveChatBackgroundOpacityValue(key: string, value: number) {
  writeNumber(
    key,
    clamp(value, CHAT_BACKGROUND_OPACITY_MIN, CHAT_BACKGROUND_OPACITY_MAX),
  );
}

function applyChatBackgroundOpacityValue(variable: string, value: number) {
  const next = clamp(
    value,
    CHAT_BACKGROUND_OPACITY_MIN,
    CHAT_BACKGROUND_OPACITY_MAX,
  );
  document.documentElement.style.setProperty(variable, String(next));
  return next;
}

export function loadChatBackgroundEmptyOpacity(): number {
  return loadChatBackgroundOpacityValue(CHAT_BACKGROUND_EMPTY_OPACITY_KEY);
}

export function saveChatBackgroundEmptyOpacity(value: number) {
  saveChatBackgroundOpacityValue(CHAT_BACKGROUND_EMPTY_OPACITY_KEY, value);
}

export function applyChatBackgroundEmptyOpacity(value: number) {
  return applyChatBackgroundOpacityValue(
    "--chat-background-empty-opacity",
    value,
  );
}

export function loadChatBackgroundSessionOpacity(): number {
  return loadChatBackgroundOpacityValue(CHAT_BACKGROUND_SESSION_OPACITY_KEY);
}

export function saveChatBackgroundSessionOpacity(value: number) {
  saveChatBackgroundOpacityValue(CHAT_BACKGROUND_SESSION_OPACITY_KEY, value);
}

export function applyChatBackgroundSessionOpacity(value: number) {
  return applyChatBackgroundOpacityValue(
    "--chat-background-session-opacity",
    value,
  );
}

function isChatBackgroundScope(value: unknown): value is ChatBackgroundScope {
  return value === "empty" || value === "all";
}

export function loadChatBackgroundScope(): ChatBackgroundScope {
  try {
    const raw = localStorage.getItem(CHAT_BACKGROUND_SCOPE_KEY);
    return isChatBackgroundScope(raw) ? raw : CHAT_BACKGROUND_SCOPE_DEFAULT;
  } catch {
    return CHAT_BACKGROUND_SCOPE_DEFAULT;
  }
}

export function saveChatBackgroundScope(value: ChatBackgroundScope) {
  try {
    localStorage.setItem(CHAT_BACKGROUND_SCOPE_KEY, value);
  } catch {
    // private mode / quota
  }
}

export function applyChatBackgroundScope(value: ChatBackgroundScope) {
  document.documentElement.classList.toggle(
    "chat-background-empty-only",
    value === "empty",
  );
  return value;
}

function isTranscriptLayout(value: unknown): value is TranscriptLayout {
  return value === "full" || value === "chat";
}

export function loadTranscriptLayout(): TranscriptLayout {
  try {
    const raw = localStorage.getItem(TRANSCRIPT_LAYOUT_KEY);
    return isTranscriptLayout(raw) ? raw : TRANSCRIPT_LAYOUT_DEFAULT;
  } catch {
    return TRANSCRIPT_LAYOUT_DEFAULT;
  }
}

export function saveTranscriptLayout(value: TranscriptLayout) {
  const next = isTranscriptLayout(value) ? value : TRANSCRIPT_LAYOUT_DEFAULT;
  try {
    localStorage.setItem(TRANSCRIPT_LAYOUT_KEY, next);
  } catch {
    // private mode / quota
  }
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent<TranscriptLayout>(TRANSCRIPT_LAYOUT_CHANGE_EVENT, {
      detail: next,
    }),
  );
}

export function loadTranscriptAnchor(): boolean {
  return readFlag(TRANSCRIPT_ANCHOR_KEY) ?? TRANSCRIPT_ANCHOR_DEFAULT;
}

export function saveTranscriptAnchor(value: boolean) {
  writeFlag(TRANSCRIPT_ANCHOR_KEY, value);
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent<boolean>(TRANSCRIPT_ANCHOR_CHANGE_EVENT, {
      detail: value,
    }),
  );
}
