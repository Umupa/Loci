// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyFonts,
  cssFamilies,
  FONT_CHANGE_EVENT,
  loadCodeFont,
  loadReadingFont,
  loadUiFont,
  normalizeFontFamily,
  OMARCHY_FONTS,
  READING_FONT_DEFAULT,
  READING_FONT_SERIF,
  rendersMonospace,
  saveCodeFont,
  saveReadingFont,
  saveUiFont,
  subscribeFonts,
  UI_FONT_FOLLOWS_CODE,
  usableCodeFont,
} from "./fonts";

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

beforeEach(() => {
  mockLocalStorage();
  root().removeAttribute("style");
  root().className = "";
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("normalizeFontFamily", () => {
  it("accepts plain family names and lists", () => {
    expect(normalizeFontFamily("JetBrainsMono Nerd Font")).toBe("JetBrainsMono Nerd Font");
    expect(normalizeFontFamily("  Fira Code ,  monospace ")).toBe("Fira Code, monospace");
    expect(normalizeFontFamily('"Iosevka Nerd Font Mono"')).toBe("Iosevka Nerd Font Mono");
    expect(normalizeFontFamily("'Noto Sans SC', 苹方-简")).toBe("Noto Sans SC, 苹方-简");
    expect(normalizeFontFamily("Source Code Pro 2.0")).toBe("Source Code Pro 2.0");
  });

  it("rejects anything that could leave the font-family value", () => {
    for (const value of [
      "",
      "   ",
      ",",
      "a; color: red",
      "a } body { x",
      "url(https://example.com/f.woff)",
      "a\\62",
      "a\nb",
      "a/*b*/",
      "<style>",
      "a, b, c, d, e",
      "x".repeat(65),
      "-Leading",
      "--var",
      null,
      undefined,
      12,
    ]) {
      expect(normalizeFontFamily(value), String(value)).toBeNull();
    }
  });

  it("is safe to apply: every accepted value is a list of simple names", () => {
    for (const value of ["A B", "A, B", "Λ Font", "a.b-c_d+e"]) {
      expect(cssFamilies(normalizeFontFamily(value)!)).toMatch(/^("[^"\\;{}()<>]+"|[a-z-]+)(, ("[^"\\;{}()<>]+"|[a-z-]+))*$/);
    }
  });
});

describe("cssFamilies", () => {
  it("quotes families and leaves generic names alone", () => {
    expect(cssFamilies("Fira Code")).toBe('"Fira Code"');
    expect(cssFamilies("Fira Code, monospace")).toBe('"Fira Code", monospace');
    expect(cssFamilies("System-UI, Georgia")).toBe('System-UI, "Georgia"');
  });
});

describe("font settings", () => {
  it("default to the system fonts", () => {
    expect(loadCodeFont()).toBeNull();
    expect(loadUiFont()).toBeNull();
  });

  it("persist, normalize and clear", () => {
    saveCodeFont(" 'FiraCode Nerd Font' ");
    expect(localStorage.getItem("loci.codeFont")).toBe("FiraCode Nerd Font");
    expect(loadCodeFont()).toBe("FiraCode Nerd Font");
    saveCodeFont(null);
    expect(localStorage.getItem("loci.codeFont")).toBeNull();
    saveCodeFont("a; b");
    expect(localStorage.getItem("loci.codeFont")).toBeNull();
  });

  it("let the interface follow the code font", () => {
    saveUiFont(UI_FONT_FOLLOWS_CODE);
    expect(loadUiFont()).toBe(UI_FONT_FOLLOWS_CODE);
    saveUiFont("Inter");
    expect(loadUiFont()).toBe("Inter");
  });

  it("ignore bad stored values", () => {
    localStorage.setItem("loci.codeFont", "a; color: red");
    localStorage.setItem("loci.uiFont", "@other");
    expect(loadCodeFont()).toBeNull();
    expect(loadUiFont()).toBeNull();
  });

  it("tell subscribers", () => {
    const listener = vi.fn();
    const stop = subscribeFonts(listener);
    saveCodeFont("Iosevka");
    expect(listener).toHaveBeenCalledTimes(1);
    window.dispatchEvent(new StorageEvent("storage", { key: "loci.uiFont" }));
    window.dispatchEvent(new StorageEvent("storage", { key: "loci.other" }));
    expect(listener).toHaveBeenCalledTimes(2);
    stop();
    saveUiFont("Inter");
    expect(listener).toHaveBeenCalledTimes(2);
    expect(FONT_CHANGE_EVENT).toBe("loci:fontchange");
  });
});

describe("applyFonts", () => {
  it("leaves the system stacks alone when nothing is chosen", () => {
    applyFonts();
    expect(prop("--font-mono-user")).toBe("");
    expect(prop("--font-sans-user")).toBe("");
    expect(root().classList.contains("has-ui-font")).toBe(false);
  });

  it("puts the code font in front of the system monospace stack only", () => {
    saveCodeFont("JetBrainsMono Nerd Font");
    applyFonts();
    expect(prop("--font-mono-user")).toBe(
      '"JetBrainsMono Nerd Font", var(--font-mono-system)',
    );
    expect(prop("--font-sans-user")).toBe("");
    expect(root().classList.contains("has-ui-font")).toBe(false);
  });

  it("applies a chosen interface font on every platform", () => {
    saveUiFont("Inter, sans-serif");
    applyFonts();
    expect(prop("--font-sans-user")).toBe('"Inter", sans-serif, var(--font-sans-system)');
    expect(root().classList.contains("has-ui-font")).toBe(true);
  });

  it("uses the code font for the interface when asked", () => {
    saveCodeFont("Iosevka Nerd Font Mono");
    saveUiFont(UI_FONT_FOLLOWS_CODE);
    applyFonts();
    expect(prop("--font-sans-user")).toBe(
      '"Iosevka Nerd Font Mono", var(--font-sans-system)',
    );
    expect(root().classList.contains("has-ui-font")).toBe(true);
  });

  it("keeps the system interface font when it follows a code font that is not set", () => {
    saveUiFont(UI_FONT_FOLLOWS_CODE);
    applyFonts();
    expect(prop("--font-sans-user")).toBe("");
    expect(root().classList.contains("has-ui-font")).toBe(false);
  });

  it("uses the interface sans for reader body text by default", () => {
    expect(READING_FONT_DEFAULT).toBe("sans");
    expect(loadReadingFont()).toBe("sans");
    applyFonts();
    expect(prop("--font-reading")).toBe("");
  });

  it("sets the reader body face to a system serif when asked, and clears it again", () => {
    saveReadingFont("serif");
    expect(loadReadingFont()).toBe("serif");
    applyFonts();
    expect(prop("--font-reading")).toBe(READING_FONT_SERIF);
    expect(READING_FONT_SERIF).toContain("Songti SC");
    expect(READING_FONT_SERIF).toContain("Noto Serif CJK SC");

    saveReadingFont("sans");
    applyFonts();
    expect(prop("--font-reading")).toBe("");
  });

  it("goes back to the system fonts when the choices are cleared", () => {
    saveCodeFont("Iosevka");
    saveUiFont("Inter");
    applyFonts();
    saveCodeFont(null);
    saveUiFont(null);
    applyFonts();
    expect(prop("--font-mono-user")).toBe("");
    expect(prop("--font-sans-user")).toBe("");
    expect(root().classList.contains("has-ui-font")).toBe(false);
  });
});

describe("Omarchy's fonts", () => {
  it("are the families its font menu installs", () => {
    expect(OMARCHY_FONTS.map((font) => font.family)).toEqual([
      "JetBrainsMono Nerd Font",
      "CaskaydiaMono Nerd Font",
      "MesloLGL Nerd Font",
      "FiraCode Nerd Font",
      "VictorMono Nerd Font",
      "BitstromWera Nerd Font",
      "Iosevka Nerd Font Mono",
    ]);
    for (const font of OMARCHY_FONTS) {
      expect(normalizeFontFamily(font.family)).toBe(font.family);
    }
  });
});

/**
 * A canvas whose fonts are decided by the test: the named families are
 * monospace and everything else is proportional, as fontconfig can make it.
 */
function fakeCanvas(monospaceFamilies: string[]) {
  return vi
    .spyOn(HTMLCanvasElement.prototype, "getContext")
    .mockImplementation(function () {
      let font = "";
      return {
        set font(value: string) {
          font = value;
        },
        get font() {
          return font;
        },
        measureText: (text: string) => {
          const family = /"([^"]+)"/.exec(font)?.[1];
          const uniform = !!family && monospaceFamilies.includes(family);
          const advance = text.startsWith("W") && !uniform ? 12 : 8;
          return { width: advance * text.length };
        },
      } as unknown as CanvasRenderingContext2D;
    } as never);
}

describe("rendersMonospace", () => {
  it("tells a monospace font from one that comes out proportional", () => {
    fakeCanvas(["Present Mono"]);
    expect(rendersMonospace("Present Mono")).toBe(true);
    expect(rendersMonospace("Sans Substitute")).toBe(false);
  });

  it("measures a whole list the way the page would draw it", () => {
    fakeCanvas(["Present Mono"]);
    expect(rendersMonospace("Present Mono, monospace")).toBe(true);
  });

  it("does not guess about bad names or a canvas that cannot measure", () => {
    expect(rendersMonospace("a; b")).toBeNull();
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(null);
    expect(rendersMonospace("Unmeasurable Mono")).toBeNull();
  });
});

describe("the code font in use", () => {
  it("is the stored one when it renders as monospace", () => {
    fakeCanvas(["Fira Mono"]);
    saveCodeFont("Fira Mono");
    expect(usableCodeFont()).toBe("Fira Mono");
    applyFonts();
    expect(prop("--font-mono-user")).toBe('"Fira Mono", var(--font-mono-system)');
  });

  it("is dropped when it would come out proportional, and kept stored", () => {
    fakeCanvas(["Fira Mono"]);
    saveCodeFont("FiraCode Nerd Font");
    saveUiFont(UI_FONT_FOLLOWS_CODE);
    expect(usableCodeFont()).toBeNull();
    applyFonts();
    expect(prop("--font-mono-user")).toBe("");
    // Nothing for the interface to follow either.
    expect(prop("--font-sans-user")).toBe("");
    expect(root().classList.contains("has-ui-font")).toBe(false);
    expect(loadCodeFont()).toBe("FiraCode Nerd Font");
  });

  it("is used as stored when the page cannot measure", () => {
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(null);
    saveCodeFont("Anything Mono");
    expect(usableCodeFont()).toBe("Anything Mono");
  });
});
