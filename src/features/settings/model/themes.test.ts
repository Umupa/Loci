import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { createHighlighter } from "shiki";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";
import { describe, expect, it, vi } from "vitest";
import {
  contrastRatio,
  hexToHsl,
  hslToHex,
  isHexColor,
  mixHex,
} from "../../../shared/lib/colorUtils";
import { OMARCHY_SOURCE, OMARCHY_TOKEN_RULES } from "./omarchyThemes.generated";
import {
  buildCodeTheme,
  codeSurface,
  findTheme,
  isThemeWallpaperPath,
  MIN_ACCENT_CONTRAST,
  MIN_READABLE_CONTRAST,
  MIN_SECONDARY_CONTRAST,
  SECONDARY_TEXT_STRENGTH,
  MIN_TEXT_CONTRAST,
  PALETTE_KEYS,
  resolveTheme,
  resolveThemeWallpaper,
  THEMES,
  themesWithMode,
} from "./themes";

vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

const PUBLIC = join(process.cwd(), "public");

describe("the Omarchy catalog", () => {
  it("has the themes of the quattro branch", () => {
    expect(THEMES.length).toBe(22);
    expect(themesWithMode("light").map((theme) => theme.id)).toEqual([
      "catppuccin-latte",
      "flexoki-light",
      "lupine",
      "rose-pine",
      "white",
    ]);
    expect(themesWithMode("dark")).toHaveLength(17);
  });

  it("gives every theme a full, valid palette", () => {
    const ids = THEMES.map((theme) => theme.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const theme of THEMES) {
      expect(Object.keys(theme.palette).sort(), theme.id).toEqual(
        [...PALETTE_KEYS].sort(),
      );
      for (const [key, value] of Object.entries(theme.palette)) {
        expect(isHexColor(value), `${theme.id}.${key}`).toBe(true);
        expect(value, `${theme.id}.${key}`).toBe(value.toLowerCase());
      }
      expect(["dark", "light"]).toContain(theme.mode);
      expect(theme.name.length).toBeGreaterThan(0);
    }
  });

  it("keeps Omarchy's own colors", () => {
    const tokyo = findTheme("tokyo-night")!;
    expect(tokyo.name).toBe("Tokyo Night");
    expect(tokyo.mode).toBe("dark");
    expect(tokyo.palette.background).toBe("#1a1b26");
    expect(tokyo.palette.foreground).toBe("#a9b1d6");
    expect(tokyo.palette.accent).toBe("#7aa2f7");
    expect(findTheme("white")!.palette.background).toBe("#ffffff");
    // `white` defines no orange or brown; Omarchy derives them.
    expect(findTheme("white")!.palette.orange).toBe(
      findTheme("white")!.palette.yellow,
    );
  });

  it("ships every wallpaper it lists, and nothing else", () => {
    const listed = new Set<string>();
    const originals = new Set<string>();
    for (const theme of THEMES) {
      expect(theme.wallpapers.length, theme.id).toBeGreaterThan(0);
      const ids = theme.wallpapers.map((wallpaper) => wallpaper.id);
      expect(new Set(ids).size, theme.id).toBe(ids.length);
      for (const wallpaper of theme.wallpapers) {
        const key = `${theme.id}/${wallpaper.id}.${wallpaper.ext}`;
        expect(wallpaper.cdnUrl).toBe(`https://cdn.jsdelivr.net/gh/omacom/omarchy@${OMARCHY_SOURCE.commit}/themes/${theme.id}/backgrounds/${wallpaper.id}.${wallpaper.ext}`);
        expect(existsSync(join(process.cwd(), "wallpapers", key)), key).toBe(true);
        originals.add(key);
        expect(wallpaper.thumb.startsWith("/themes/")).toBe(true);
        expect(existsSync(join(PUBLIC, wallpaper.thumb)), wallpaper.thumb).toBe(true);
        listed.add(wallpaper.thumb);
      }
    }
    const onDisk = readdirSync(join(PUBLIC, "themes"), { recursive: true })
      .map(String)
      .filter((file) => file.endsWith(".webp"))
      .map((file) => `/themes/${file}`);
    expect(onDisk.sort()).toEqual([...listed].sort());
    expect(existsSync(join(PUBLIC, "themes", "LICENSE"))).toBe(true);
    const originalFiles = readdirSync(join(process.cwd(), "wallpapers"), { recursive: true })
      .map(String).filter((file) => /\.(webp|jpg|jpeg|png|gif)$/.test(file));
    expect(originalFiles.sort()).toEqual([...originals].sort());
    expect(existsSync(join(process.cwd(), "wallpapers", "LICENSE"))).toBe(true);
  });

  it("names wallpapers for people", () => {
    const tokyo = findTheme("tokyo-night")!;
    expect(tokyo.wallpapers[0]).toMatchObject({
      id: "0-winding-road",
      name: "Winding Road",
      path: "theme:tokyo-night/0-winding-road",
    });
    // Three images called "white" stay distinguishable.
    expect(findTheme("white")!.wallpapers.map((item) => item.name)).toEqual([
      "White",
      "White 2",
      "White 3",
    ]);
    // The wordmark placeholders are not wallpapers.
    for (const theme of THEMES) {
      for (const wallpaper of theme.wallpapers) {
        expect(wallpaper.name.toLowerCase(), theme.id).not.toBe("omarchy");
      }
    }
  });
});

describe("wallpaper references", () => {
  it("round-trips and rejects what is gone", () => {
    const wallpaper = findTheme("nord")!.wallpapers[1];
    const found = resolveThemeWallpaper(wallpaper.path);
    expect(found?.theme.id).toBe("nord");
    expect(found?.wallpaper).toBe(wallpaper);
    expect(isThemeWallpaperPath(wallpaper.path)).toBe(true);
    expect(isThemeWallpaperPath("/home/me/picture.png")).toBe(false);
    expect(resolveThemeWallpaper("theme:nord/missing")).toBeNull();
    expect(resolveThemeWallpaper("theme:nowhere/0-x")).toBeNull();
    expect(resolveThemeWallpaper("/home/me/picture.png")).toBeNull();
    expect(resolveThemeWallpaper(null)).toBeNull();
  });
});

describe("readable colors", () => {
  it.each(THEMES.map((theme) => [theme.id, theme] as const))(
    "%s reads on its own background",
    (_id, theme) => {
      const resolved = resolveTheme(theme);
      const { background } = resolved;
      expect(background).toBe(theme.palette.background);
      expect(contrastRatio(resolved.content, background)).toBeGreaterThanOrEqual(
        MIN_TEXT_CONTRAST,
      );
      // Secondary text is the same ink, thinned out.
      expect(
        contrastRatio(
          mixHex(resolved.content, background, SECONDARY_TEXT_STRENGTH),
          background,
        ),
      ).toBeGreaterThanOrEqual(MIN_SECONDARY_CONTRAST[theme.mode]);
      expect(contrastRatio(resolved.accent, background)).toBeGreaterThanOrEqual(
        MIN_ACCENT_CONTRAST,
      );
      for (const color of [
        resolved.link,
        resolved.heading,
        resolved.skill,
        resolved.mention,
        resolved.diffAddText,
        resolved.diffDelText,
      ]) {
        expect(contrastRatio(color, background)).toBeGreaterThanOrEqual(
          MIN_READABLE_CONTRAST,
        );
      }
    },
  );

  it("leaves a palette alone when it already reads", () => {
    const nord = resolveTheme(findTheme("nord")!);
    expect(nord.content).toBe("#d8dee9");
    const tokyo = resolveTheme(findTheme("tokyo-night")!);
    expect(tokyo.accent).toBe("#7aa2f7");
    expect(tokyo.link).toBe("#7aa2f7");
    const catppuccin = findTheme("catppuccin")!;
    expect(resolveTheme(catppuccin).content).toBe(catppuccin.palette.foreground);
  });

  it("changes a palette's text color only where secondary text would be too faint", () => {
    const changed = THEMES.filter(
      (theme) => resolveTheme(theme).content !== theme.palette.foreground,
    ).map((theme) => theme.id);
    expect(changed).toEqual([
      "catppuccin-latte",
      "everforest",
      "gruvbox",
      "matte-black",
      "miasma",
      "osaka-jade",
      "rose-pine",
      "tokyo-night",
    ]);
  });

  it("prefers the palette's own brighter text colors to inventing one", () => {
    // Omarchy ships these for exactly this: a lighter ink in the same family.
    const tokyo = findTheme("tokyo-night")!;
    expect(resolveTheme(tokyo).content).toBe(tokyo.palette.bright_foreground);
    const jade = findTheme("osaka-jade")!;
    expect(resolveTheme(jade).content).toBe(jade.palette.light_foreground);
  });

  it("moves the rest along their own hue, by as little as it takes", () => {
    for (const id of ["gruvbox", "rose-pine", "everforest"]) {
      const theme = findTheme(id)!;
      const before = hexToHsl(theme.palette.foreground);
      const after = resolveTheme(theme).contentHsl;
      expect(Math.abs(after.h - before.h), id).toBeLessThan(4);
      expect(after.l, id).not.toBe(before.l);
      // Dark palettes get brighter text and light palettes darker text.
      expect(after.l > before.l, id).toBe(theme.mode === "dark");
    }
    // Barely any change where the palette was nearly there.
    const matte = findTheme("matte-black")!;
    expect(
      Math.abs(resolveTheme(matte).contentHsl.l - hexToHsl(matte.palette.foreground).l),
    ).toBeLessThan(3);
  });

  it("splits colors into channels that give the same color back", () => {
    for (const theme of THEMES) {
      const { backgroundHsl, background } = resolveTheme(theme);
      expect(
        hslToHex(backgroundHsl.h, backgroundHsl.s, backgroundHsl.l),
        theme.id,
      ).toBe(background);
    }
  });
});

describe("code themes", () => {
  it.each(THEMES.map((theme) => [theme.id, theme] as const))(
    "%s keeps every syntax color readable on a code block",
    (_id, theme) => {
      const built = buildCodeTheme(theme);
      const surface = codeSurface(theme);
      expect(built.name).toBe(`loci-${theme.id}`);
      expect(built.type).toBe(theme.mode);
      expect(built.tokenColors).toHaveLength(OMARCHY_TOKEN_RULES.length);
      expect(contrastRatio(built.fg!, surface)).toBeGreaterThanOrEqual(
        MIN_TEXT_CONTRAST,
      );
      for (const rule of built.tokenColors!) {
        const color = rule.settings!.foreground!;
        expect(
          contrastRatio(color, surface),
          `${theme.id}: ${rule.name}`,
        ).toBeGreaterThanOrEqual(MIN_READABLE_CONTRAST);
      }
    },
  );

  it("is built once per theme", () => {
    const theme = findTheme("gruvbox")!;
    expect(buildCodeTheme(theme)).toBe(buildCodeTheme(theme));
  });

  it("keeps italic comments and the palette's own keyword color", () => {
    const theme = findTheme("tokyo-night")!;
    const built = buildCodeTheme(theme);
    const comment = built.tokenColors!.find((rule) => rule.name === "Comment")!;
    expect(comment.settings!.fontStyle).toBe("italic");
    const keyword = built.tokenColors!.find((rule) => rule.name === "Keyword")!;
    expect(keyword.settings!.foreground).toBe(theme.palette.bright_magenta);
  });

  it("is accepted by Shiki and paints tokens only in palette colors", async () => {
    const theme = findTheme("gruvbox")!;
    const built = buildCodeTheme(theme);
    const highlighter = await createHighlighter({
      themes: [built],
      langs: ["typescript"],
      engine: createJavaScriptRegexEngine({ forgiving: true }),
    });
    const { tokens } = highlighter.codeToTokens(
      'const answer = "42"; // note',
      { lang: "typescript", theme: built.name! },
    );
    const allowed = new Set([
      built.fg!.toLowerCase(),
      ...built.tokenColors!.map((rule) =>
        rule.settings!.foreground!.toLowerCase(),
      ),
    ]);
    const painted = tokens.flat();
    for (const token of painted) {
      expect(allowed.has(token.color!.toLowerCase()), token.content).toBe(true);
    }
    expect(new Set(painted.map((token) => token.color)).size).toBeGreaterThan(3);
    const comment = painted.find((token) => token.content.includes("note"))!;
    // FontStyle.Italic
    expect((comment.fontStyle ?? 0) & 1).toBe(1);
    highlighter.dispose();
  });
});

function mixHalf(foreground: string, background: string): string {
  const channel = (hex: string, at: number) =>
    Number.parseInt(hex.slice(at, at + 2), 16);
  return `#${[1, 3, 5]
    .map((at) =>
      Math.round((channel(foreground, at) + channel(background, at)) / 2)
        .toString(16)
        .padStart(2, "0"),
    )
    .join("")}`;
}
