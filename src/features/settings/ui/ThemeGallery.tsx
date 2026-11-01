import { t, useLocale } from "../../../shared/i18n/locale";
import type { ReactNode } from "react";
import { hslToHex } from "../../../shared/lib/colorUtils";
import { Check } from "../../../shared/ui/icons";
import {
  themesWithMode,
  type ThemeDefinition,
  type ThemeWallpaper,
} from "../model/themes";

/** Loci's own theme as a card shows it. The page colors change with the theme, so the swatch is fixed. */
const DEFAULT_PREVIEW = {
  background: hslToHex(240, 0, 9),
  foreground: hslToHex(240, 0, 92),
  accent: hslToHex(211, 92, 62),
  dots: ["#f87171", "#34d399", "#fbbf24", "#60a5fa", "#c084fc", "#22d3ee"],
};

const CARD_GRID =
  "grid grid-cols-[repeat(auto-fill,minmax(8rem,1fr))] gap-2";

function ThemeCard({
  name,
  active,
  background,
  foreground,
  accent,
  dots,
  onSelect,
}: {
  name: string;
  active: boolean;
  background: string;
  foreground: string;
  accent: string;
  dots: readonly string[];
  onSelect: () => void;
}) {
  useLocale();
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      aria-label={name}
      onClick={onSelect}
      className={`flex flex-col overflow-hidden rounded-lg border text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-content/40 ${
        active ? "border-content/70" : "border-content/10 hover:border-content/30"
      }`}
    >
      {/* The card paints the theme's own colors, whatever theme Loci wears now. */}
      <span
        aria-hidden
        className="relative block h-14 w-full"
        style={{ background }}
      >
        <span
          className="absolute left-2.5 top-2.5 h-1.5 w-12 rounded-full"
          style={{ background: foreground }}
        />
        <span
          className="absolute left-2.5 top-[1.1rem] h-1.5 w-8 rounded-full"
          style={{ background: foreground, opacity: 0.45 }}
        />
        <span
          className="absolute right-2.5 top-2.5 h-3 w-5 rounded-[4px]"
          style={{ background: accent }}
        />
        <span className="absolute bottom-2 left-2.5 flex gap-1">
          {dots.map((color, index) => (
            <span
              key={index}
              className="size-2 rounded-full"
              style={{ background: color }}
            />
          ))}
        </span>
      </span>
      <span className="flex items-center justify-between gap-2 px-2.5 py-1.5 text-[12px] text-content">
        <span className="min-w-0 truncate">{name}</span>
        {active ? <Check className="size-3.5 shrink-0" aria-hidden /> : null}
      </span>
    </button>
  );
}

function themeCard(
  theme: ThemeDefinition,
  activeId: string | null,
  onSelect: (id: string | null) => void,
) {
  const { palette } = theme;
  return (
    <ThemeCard
      key={theme.id}
      name={theme.name}
      active={activeId === theme.id}
      background={palette.background}
      foreground={palette.foreground}
      accent={palette.accent}
      dots={[
        palette.red,
        palette.green,
        palette.yellow,
        palette.blue,
        palette.magenta,
        palette.cyan,
      ]}
      onSelect={() => onSelect(theme.id)}
    />
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  useLocale();
  return (
    <div>
      <div className="mb-1.5 text-[12px] font-medium text-content/40">
        {title}
      </div>
      <div className={CARD_GRID}>{children}</div>
    </div>
  );
}

const DARK_THEME_ORDER = [
  "tokyo-night",
  "catppuccin",
  "nord",
  "gruvbox",
  "kanagawa",
  "everforest",
  "hackerman",
  "lumon",
  "retro-82",
  "ethereal",
  "osaka-jade",
  "last-horizon",
  "miasma",
  "matte-black",
  "ristretto",
  "solitude",
  "vantablack",
];

function sortedDarkThemes(): ThemeDefinition[] {
  const dark = themesWithMode("dark");
  return [...dark].sort((a, b) => {
    const ai = DARK_THEME_ORDER.indexOf(a.id);
    const bi = DARK_THEME_ORDER.indexOf(b.id);
    if (ai === -1 && bi === -1) return 0;
    if (ai === -1) return 1;
    if (bi === -1) return -1;
    return ai - bi;
  });
}

/** Every theme as a card: Default first inside Dark, then Light. */
export function ThemeGallery({
  activeId,
  onSelect,
}: {
  activeId: string | null;
  onSelect: (id: string | null) => void;
}) {
  useLocale();
  return (
    <div role="radiogroup" aria-label={t("Color theme")} className="space-y-4">
      <Section title={t("Dark")}>
        <ThemeCard
          name={t("Default")}
          active={activeId == null}
          {...DEFAULT_PREVIEW}
          onSelect={() => onSelect(null)}
        />
        {sortedDarkThemes().map((theme) => themeCard(theme, activeId, onSelect))}
      </Section>
      <Section title={t("Light")}>
        {themesWithMode("light").map((theme) => themeCard(theme, activeId, onSelect))}
      </Section>
    </div>
  );
}

/** The theme's own wallpapers, as thumbnails to pick the chat background from. */
export function WallpaperStrip({
  theme,
  selectedPath,
  onSelect,
}: {
  theme: ThemeDefinition;
  selectedPath: string | null;
  onSelect: (wallpaper: ThemeWallpaper) => void;
}) {
  useLocale();
  return (
    <div className="border-b border-content/5 p-4">
      <div className="mb-2 text-[12px] text-content/45">
        {t("{0} wallpapers", theme.name)}
      </div>
      <div
        role="radiogroup"
        aria-label={t("{0} wallpapers", theme.name)}
        className="flex gap-2 overflow-x-auto pb-1"
      >
        {theme.wallpapers.map((wallpaper) => {
          const selected = selectedPath === wallpaper.path;
          return (
            <button
              key={wallpaper.id}
              type="button"
              role="radio"
              aria-checked={selected}
              aria-label={wallpaper.name}
              title={wallpaper.name}
              onClick={() => onSelect(wallpaper)}
              className={`h-14 w-24 shrink-0 overflow-hidden rounded-md border outline-none focus-visible:ring-2 focus-visible:ring-content/40 ${
                selected
                  ? "border-content/70 ring-1 ring-content/70"
                  : "border-content/10 hover:border-content/30"
              }`}
            >
              <img
                src={wallpaper.thumb}
                alt=""
                loading="lazy"
                decoding="async"
                draggable={false}
                className="size-full object-cover"
              />
            </button>
          );
        })}
      </div>
    </div>
  );
}
