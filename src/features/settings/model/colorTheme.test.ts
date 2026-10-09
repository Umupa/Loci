// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { hslToHex } from "../../../shared/lib/colorUtils";
import {
  activeTheme,
  applyThemeColors,
  applyThemeTint,
  chatBackgroundSrc,
  currentColorScheme,
  initAppearance,
  loadChatBackgroundPath,
  loadThemeId,
  loadThemeWallpaperAuto,
  saveAccentColor,
  saveChatBackgroundPath,
  saveThemeHue,
  saveThemeId,
  saveThemePreference,
  saveThemeSaturation,
  saveThemeWallpaperAuto,
  setTheme,
  THEME_CHANGE_EVENT,
} from "./appearance";
import { findTheme, resolveTheme, THEMES } from "./themes";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async (command, args) => command === "download_wallpaper"
    ? `/app-data/wallpaper-cache/${args.cacheKey}` : undefined),
  convertFileSrc: (path: string) => `asset://${path}`,
}));

const THEME_KEY = "loci.themeId";

function mockLocalStorage() {
  const data = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => data.set(key, value),
    removeItem: (key: string) => data.delete(key),
    clear: () => data.clear(),
    key: (index: number) => [...data.keys()][index] ?? null,
    get length() {
      return data.size;
    },
  });
}

const root = () => document.documentElement;
const prop = (name: string) => root().style.getPropertyValue(name);
const number = (name: string) => Number.parseFloat(prop(name));
const pageColor = () =>
  hslToHex(
    number("--theme-hue"),
    number("--theme-saturation"),
    number("--background-lightness"),
  );
const inkColor = () =>
  hslToHex(
    number("--content-hue"),
    number("--content-saturation"),
    number("--content-lightness"),
  );

beforeEach(() => {
  mockLocalStorage();
  root().removeAttribute("style");
  root().className = "";
  delete root().dataset.theme;
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("theme setting", () => {
  it("defaults to Loci's own theme", () => {
    expect(loadThemeId()).toBeNull();
    expect(activeTheme()).toBeNull();
  });

  it("persists a known theme and forgets an unknown one", () => {
    saveThemeId("nord");
    expect(localStorage.getItem(THEME_KEY)).toBe("nord");
    expect(loadThemeId()).toBe("nord");
    saveThemeId(null);
    expect(localStorage.getItem(THEME_KEY)).toBeNull();
    saveThemeId("not-a-theme");
    expect(localStorage.getItem(THEME_KEY)).toBeNull();
  });

  it("ignores a stored id that is not a theme any more", () => {
    for (const stored of ["not-a-theme", "", " nord", "NORD", "__proto__"]) {
      localStorage.setItem(THEME_KEY, stored);
      expect(loadThemeId(), stored).toBeNull();
    }
  });

  it("prefers the wallpaper to follow the theme until told otherwise", () => {
    expect(loadThemeWallpaperAuto()).toBe(true);
    saveThemeWallpaperAuto(false);
    expect(loadThemeWallpaperAuto()).toBe(false);
  });
});

describe("applying a theme", () => {
  it.each(THEMES.map((theme) => [theme.id, theme] as const))(
    "%s sets the page and text colors exactly",
    (_id, theme) => {
      setTheme(theme.id);
      const resolved = resolveTheme(theme);
      expect(pageColor()).toBe(theme.palette.background);
      expect(inkColor()).toBe(resolved.content);
      expect(prop("--link-color")).toBe(resolved.link);
      expect(prop("--color-markdown-heading")).toBe(resolved.heading);
      expect(prop("--color-skill")).toBe(resolved.skill);
      expect(prop("--color-mention")).toBe(resolved.mention);
      expect(prop("--color-diff-add")).toBe(theme.palette.green);
      expect(prop("--color-diff-del-fg")).toBe(resolved.diffDelText);
      expect(root().dataset.theme).toBe(theme.id);
      expect(root().classList.contains("has-theme")).toBe(true);
      expect(root().classList.contains("theme-light")).toBe(theme.mode === "light");
    },
  );

  it("follows the theme's mode over the stored preference", () => {
    saveThemePreference("light");
    setTheme("tokyo-night");
    expect(root().classList.contains("theme-light")).toBe(false);
    expect(currentColorScheme()).toBe("dark");
    saveThemePreference("dark");
    setTheme("white");
    expect(root().classList.contains("theme-light")).toBe(true);
    expect(currentColorScheme()).toBe("light");
  });

  it("returns to the preference and the stored tint with the default theme", () => {
    saveThemePreference("light");
    saveThemeHue(100);
    saveThemeSaturation(30);
    setTheme("nord");
    expect(root().classList.contains("theme-light")).toBe(false);
    expect(pageColor()).toBe(findTheme("nord")!.palette.background);
    setTheme(null);
    expect(root().classList.contains("theme-light")).toBe(true);
    expect(root().classList.contains("has-theme")).toBe(false);
    expect(root().dataset.theme).toBeUndefined();
    expect(prop("--theme-hue")).toBe("100");
    expect(prop("--theme-saturation")).toBe("30%");
    for (const name of [
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
    ]) {
      expect(prop(name), name).toBe("");
    }
  });

  it("keeps the tint sliders from overwriting a theme's page color", () => {
    setTheme("gruvbox");
    const before = pageColor();
    expect(applyThemeTint(200, 80)).toEqual({ hue: 200, saturation: 80 });
    expect(pageColor()).toBe(before);
    expect(before).toBe(findTheme("gruvbox")!.palette.background);
  });

  it("restores a saved theme on startup", () => {
    saveThemeId("rose-pine");
    initAppearance();
    expect(root().dataset.theme).toBe("rose-pine");
    expect(root().classList.contains("theme-light")).toBe(true);
    expect(pageColor()).toBe(findTheme("rose-pine")!.palette.background);
    expect(applyThemeColors()?.id).toBe("rose-pine");
  });

  it("starts with the tint theme when nothing was saved", () => {
    initAppearance();
    expect(root().classList.contains("has-theme")).toBe(false);
    expect(prop("--theme-hue")).toBe("240");
    expect(prop("--theme-dark-lightness")).toBe("9%");
    expect(root().classList.contains("has-user-accent")).toBe(false);
  });

  it("announces the change", () => {
    const heard: unknown[] = [];
    const onChange = (event: Event) =>
      heard.push((event as CustomEvent<string | null>).detail);
    window.addEventListener(THEME_CHANGE_EVENT, onChange);
    setTheme("kanagawa");
    setTheme(null);
    window.removeEventListener(THEME_CHANGE_EVENT, onChange);
    expect(heard).toEqual(["kanagawa", null]);
  });

  it("treats an unknown theme as the default", () => {
    setTheme("kanagawa");
    setTheme("not-a-theme");
    expect(loadThemeId()).toBeNull();
    expect(root().classList.contains("has-theme")).toBe(false);
  });
});

describe("named themes before the first paint", () => {
  const bootScript = readFileSync("index.html", "utf8").match(/<script>([\s\S]*?)<\/script>/)![1];
  const boot = () => {
    root().removeAttribute("style");
    root().className = "";
    runInNewContext(bootScript, { document, localStorage, window, navigator });
  };

  it.each(THEMES)("paints $id before the app bundle loads", (theme) => {
    saveThemePreference(theme.mode === "dark" ? "light" : "dark");
    setTheme(theme.id);
    boot();
    expect(pageColor()).toBe(theme.palette.background);
    expect(root().classList.contains("theme-light")).toBe(theme.mode === "light");
  });

  it("drops the snapshot when returning to Default", () => {
    setTheme("rose-pine");
    setTheme(null);
    expect(localStorage.getItem("loci.themeBoot")).toBeNull();
    boot();
    expect(prop("--background-lightness")).toBe("");
    expect(root().classList.contains("theme-light")).toBe(false);
  });

  it.each([
    "not json",
    JSON.stringify(["other", "light", 120, 30, 90]),
    JSON.stringify(["nord", "invalid", 120, 30, 90]),
    JSON.stringify(["nord", "light", "120", 30, 90]),
    JSON.stringify(["nord", "light", 120, 101, 90]),
    JSON.stringify(["nord", "light", 120, 30]),
  ])("ignores a corrupt or mismatched snapshot: %s", (snapshot) => {
    saveThemeId("nord");
    saveThemeHue(80);
    saveThemeSaturation(20);
    localStorage.setItem("loci.themeBoot", snapshot);
    boot();
    expect(prop("--theme-hue")).toBe("80");
    expect(prop("--theme-saturation")).toBe("20%");
    expect(prop("--background-lightness")).toBe("");
    expect(root().classList.contains("theme-light")).toBe(false);
  });
});

describe("accent with a theme", () => {
  const accent = () => root().style.getPropertyValue("--user-accent-color");

  it("uses the theme's accent unless one was picked", () => {
    setTheme("tokyo-night");
    expect(root().classList.contains("has-user-accent")).toBe(true);
    expect(accent()).toBe(resolveTheme(findTheme("tokyo-night")!).accent);
    saveAccentColor("#ff00aa");
    setTheme("tokyo-night");
    expect(accent()).toBe("#ff00aa");
  });

  it("falls back to Loci's own accent with the default theme", () => {
    setTheme("tokyo-night");
    setTheme(null);
    expect(root().classList.contains("has-user-accent")).toBe(false);
    expect(accent()).toBe("");
  });
});

describe("theme wallpapers", () => {
  const first = (id: string) => findTheme(id)!.wallpapers[0].path;

  it("puts the theme's first wallpaper behind the chat", async () => {
    setTheme("nord");
    expect(loadChatBackgroundPath()).toBe(first("nord"));
    expect(root().classList.contains("has-chat-background")).toBe(true);
    await vi.waitFor(() => expect(root().style.getPropertyValue("--chat-background-image")).toContain(
      "asset:///app-data/wallpaper-cache/nord/0-black-moon.jpg",
    ));
  });

  it("moves to the next theme's wallpaper and drops it with the default theme", () => {
    setTheme("nord");
    setTheme("gruvbox");
    expect(loadChatBackgroundPath()).toBe(first("gruvbox"));
    setTheme(null);
    expect(loadChatBackgroundPath()).toBeNull();
    expect(root().classList.contains("has-chat-background")).toBe(false);
  });

  it("never replaces a picture the person chose", () => {
    saveChatBackgroundPath("/app-data/backgrounds/chat-background.png");
    setTheme("nord");
    expect(loadChatBackgroundPath()).toBe(
      "/app-data/backgrounds/chat-background.png",
    );
    setTheme(null);
    expect(loadChatBackgroundPath()).toBe(
      "/app-data/backgrounds/chat-background.png",
    );
  });

  it("respects a background removed on purpose", () => {
    saveThemeWallpaperAuto(false);
    setTheme("nord");
    expect(loadChatBackgroundPath()).toBeNull();
    // A wallpaper chosen by hand still follows the theme.
    saveChatBackgroundPath(first("nord"));
    setTheme("gruvbox");
    expect(loadChatBackgroundPath()).toBe(first("gruvbox"));
  });

  it("resolves a downloaded wallpaper to a local asset URL", async () => {
    setTheme("nord");
    await vi.waitFor(() => expect(chatBackgroundSrc(first("nord"))).toMatch(
      /^asset:\/\/\/app-data\/wallpaper-cache\/nord\/0-black-moon\.jpg\?v=\d+$/,
    ));
    expect(chatBackgroundSrc("/app-data/backgrounds/chat-background.png")).toMatch(
      /^asset:\/\/\/app-data\/backgrounds\/chat-background\.png\?v=\d+$/,
    );
    expect(chatBackgroundSrc("theme:nord/gone")).toBeNull();
    expect(chatBackgroundSrc(null)).toBeNull();
  });

  it("treats a wallpaper that left the catalog as no background", () => {
    localStorage.setItem("loci.chatBackgroundPath", "theme:nord/retired");
    expect(loadChatBackgroundPath()).toBeNull();
  });
});
