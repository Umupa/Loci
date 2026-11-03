const CODE_FONT_KEY = "loci.codeFont";
const UI_FONT_KEY = "loci.uiFont";
const READING_FONT_KEY = "loci.readingFont";

/**
 * The face for reader body text: the bundled book face (Literata with LXGW
 * WenKai for Chinese), the interface sans, or the system's book serif.
 */
export type ReadingFont = "book" | "sans" | "serif";
export const READING_FONT_DEFAULT: ReadingFont = "book";
/** Bundled with the app (bootstrap imports them), so it works offline. */
export const READING_FONT_BOOK = '"Literata Variable", "LXGW WenKai Screen", var(--font-sans)';
/** System faces only; the Chinese serifs keep CJK text in the same voice. */
export const READING_FONT_SERIF =
  '"New York", "Iowan Old Style", Georgia, "Songti SC", "Noto Serif CJK SC", serif';

/** Stored as the interface font to say "use the code font here too". */
export const UI_FONT_FOLLOWS_CODE = "@code";

/** Fired on `window` whenever a font setting changes. */
export const FONT_CHANGE_EVENT = "loci:fontchange";

/** A font offered by name, under each family name it is installed as, most likely first; `bundled` ships with Loci. */
export type FontPreset = { label: string; families: readonly string[]; bundled?: string };

/** JetBrains Mono ships with Loci (bootstrap imports it), so a code font is there on every machine, offline. */
export const BUNDLED_CODE_FONT = "JetBrains Mono Variable";

/**
 * The code fonts offered by name. Omarchy sets one monospace font for
 * everything and ships these as Nerd Fonts (its Install > Style > Font menu,
 * `bin/omarchy-menu`), under the names fontconfig knows them by; the same
 * fonts installed on a Mac or from their own releases go by other names,
 * which follow. Last, the monospace fonts macOS has built in.
 */
export const CODE_FONTS: readonly FontPreset[] = [
  { label: "JetBrains Mono", families: ["JetBrainsMono Nerd Font", "JetBrainsMono Nerd Font Mono", "JetBrains Mono"], bundled: BUNDLED_CODE_FONT },
  { label: "Cascadia Mono", families: ["CaskaydiaMono Nerd Font", "CaskaydiaCove Nerd Font Mono", "CaskaydiaCove Nerd Font", "Cascadia Mono", "Cascadia Code"] },
  { label: "Meslo LG Mono", families: ["MesloLGL Nerd Font", "MesloLGM Nerd Font", "MesloLGS Nerd Font", "Meslo LG M"] },
  { label: "Fira Code", families: ["FiraCode Nerd Font", "FiraCode Nerd Font Mono", "Fira Code"] },
  { label: "Victor Mono", families: ["VictorMono Nerd Font", "VictorMono Nerd Font Mono", "Victor Mono"] },
  { label: "Bitstream Vera Mono", families: ["BitstromWera Nerd Font", "Bitstream Vera Sans Mono"] },
  { label: "Iosevka", families: ["Iosevka Nerd Font Mono", "Iosevka Nerd Font", "Iosevka", "Iosevka Term"] },
  { label: "Menlo", families: ["Menlo"] },
  { label: "Monaco", families: ["Monaco"] },
  { label: "PT Mono", families: ["PT Mono"] },
];

/**
 * The name a preset is installed under here, or null when none of its names
 * is. A code font is installed when it draws as monospace by its name alone;
 * a missing one falls back to the proportional default. When nothing can be
 * measured, its first name is assumed. A copy installed on the system wins
 * (a Nerd Font has its icons); else the copy Loci ships, if it ships one.
 */
export function installedFamily(preset: FontPreset): string | null {
  for (const family of preset.families) {
    const mono = rendersMonospace(family);
    if (mono === null) return preset.families[0];
    if (mono) return family;
  }
  return preset.bundled ?? null;
}

/**
 * Whether a code font can be used: the bundled one always can (it may not
 * have loaded yet, so it is not measured); any other must draw as monospace.
 */
export function codeFontUsable(families: string): boolean {
  return families.split(",")[0].trim() === BUNDLED_CODE_FONT || rendersMonospace(families) !== false;
}

const GENERIC_FAMILIES = new Set([
  "serif",
  "sans-serif",
  "monospace",
  "cursive",
  "fantasy",
  "system-ui",
  "ui-serif",
  "ui-sans-serif",
  "ui-monospace",
  "ui-rounded",
  "emoji",
  "math",
  "fangsong",
]);
const MAX_FAMILIES = 4;
const MAX_FAMILY_LENGTH = 64;
// Letters and digits of any script, and the punctuation font names use.
const FAMILY_NAME = /^[\p{L}\p{N}][\p{L}\p{N} ._+-]*$/u;

/**
 * Reads a font choice typed by a person: one family or a comma-separated list.
 * Only plain names pass, so nothing typed can escape into the stylesheet.
 */
export function normalizeFontFamily(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const names = value
    .split(",")
    .map((name) => name.trim().replace(/^(["'])(.*)\1$/, "$2").trim())
    .filter(Boolean);
  if (names.length === 0 || names.length > MAX_FAMILIES) return null;
  for (const name of names) {
    if (name.length > MAX_FAMILY_LENGTH || !FAMILY_NAME.test(name)) return null;
  }
  return names.join(", ");
}

/** A stored interface font: a family list, or the follow-the-code-font marker. */
function normalizeUiFont(value: unknown): string | null {
  return value === UI_FONT_FOLLOWS_CODE ? value : normalizeFontFamily(value);
}

function readString(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeString(key: string, value: string | null) {
  try {
    if (value == null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch {
    // private mode / quota
  }
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(FONT_CHANGE_EVENT));
  }
}

export function loadCodeFont(): string | null {
  return normalizeFontFamily(readString(CODE_FONT_KEY));
}

export function saveCodeFont(value: string | null) {
  writeString(CODE_FONT_KEY, value == null ? null : normalizeFontFamily(value));
}

export function loadUiFont(): string | null {
  return normalizeUiFont(readString(UI_FONT_KEY));
}

export function saveUiFont(value: string | null) {
  writeString(UI_FONT_KEY, value == null ? null : normalizeUiFont(value));
}

export function loadReadingFont(): ReadingFont {
  const stored = readString(READING_FONT_KEY);
  return stored === "serif" || stored === "sans" ? stored : READING_FONT_DEFAULT;
}

export function saveReadingFont(value: ReadingFont) {
  writeString(READING_FONT_KEY, value === READING_FONT_DEFAULT ? null : value);
}

export function subscribeFonts(onChange: () => void) {
  if (typeof window === "undefined") return () => {};
  const onStorage = (event: StorageEvent) => {
    if (
      event.key === null ||
      event.key === CODE_FONT_KEY ||
      event.key === UI_FONT_KEY ||
      event.key === READING_FONT_KEY
    ) {
      onChange();
    }
  };
  window.addEventListener(FONT_CHANGE_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(FONT_CHANGE_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
  };
}

/** A normalized family list as a CSS value; generic names stay unquoted. */
export function cssFamilies(families: string): string {
  return families
    .split(", ")
    .map((name) => (GENERIC_FAMILIES.has(name.toLowerCase()) ? name : `"${name}"`))
    .join(", ");
}

/** The stored code font, unless it is known not to render as monospace. */
export function usableCodeFont(): string | null {
  const code = loadCodeFont();
  return code && codeFontUsable(code) ? code : null;
}

/**
 * Puts the chosen families in front of the system stacks that index.css keeps
 * in `--font-sans-system` and `--font-mono-system`. Clearing a choice removes
 * the override and the stack behaves exactly as before.
 */
export function applyFonts() {
  const root = document.documentElement;
  // A code font that does not render as monospace is not used: it is missing
  // or not a code font, and the system monospace is the safer face for code.
  const code = usableCodeFont();
  const ui = loadUiFont();
  const ownMono = code ? cssFamilies(code) : null;
  const sans = ui === UI_FONT_FOLLOWS_CODE ? ownMono : ui ? cssFamilies(ui) : null;
  if (ownMono) {
    root.style.setProperty("--font-mono-user", `${ownMono}, var(--font-mono-system)`);
  } else {
    root.style.removeProperty("--font-mono-user");
  }
  if (sans) {
    root.style.setProperty("--font-sans-user", `${sans}, var(--font-sans-system)`);
  } else {
    root.style.removeProperty("--font-sans-user");
  }
  // "Same as code font" with no code font set keeps the system interface font.
  root.classList.toggle("has-ui-font", sans != null);
  const reading = loadReadingFont();
  if (reading === READING_FONT_DEFAULT) root.style.removeProperty("--font-reading");
  else root.style.setProperty("--font-reading", reading === "serif" ? READING_FONT_SERIF : "var(--font-sans)");
}

// Narrow and wide letters: they only measure the same in a monospace font.
const NARROW_PROBE = "iiiiiiiiiiiiiiiiiiii";
const WIDE_PROBE = "WWWWWWWWWWWWWWWWWWWW";

/**
 * Whether a font list renders as monospace, measured as the page will draw it.
 * This is what guards the code font. fontconfig answers a family it does not
 * have with its closest match instead of letting CSS move on to the next
 * family, so a code font that is not installed can silently come out in a
 * proportional sans font. Null where nothing can be measured.
 */
export function rendersMonospace(families: string): boolean | null {
  const name = normalizeFontFamily(families);
  if (!name) return null;
  // Two measurements are cheap, and a font installed while Loci is open then
  // counts at once.
  try {
    const context = document.createElement("canvas").getContext("2d");
    if (!context) return null;
    context.font = `64px ${cssFamilies(name)}`;
    return (
      context.measureText(NARROW_PROBE).width ===
      context.measureText(WIDE_PROBE).width
    );
  } catch {
    return null;
  }
}
