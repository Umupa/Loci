// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { SettingsView } from "./SettingsView";
import { applyFonts } from "../model/fonts";
import { findTheme, THEMES } from "../model/themes";
import { initAppearance } from "../model/appearance";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(async () => undefined),
  convertFileSrc: (path: string) => path,
}));
vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    isMaximized: async () => false,
    onResized: async () => () => {},
  }),
}));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: vi.fn(async () => true) }));
vi.mock("../../../integrations/harness/core/availability", () => ({
  isHarnessAvailable: () => false,
  hasProbedHarnessAvailability: () => true,
  getHarnessAvailabilitySnapshot: () => 0,
  subscribeHarnessAvailability: () => () => {},
  probeHarnessAvailability: async () => {},
  harnessUnavailableHint: () => "",
}));

let container: HTMLDivElement;
let root: Root;

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

async function render(section: "appearance" | "providers" = "appearance") {
  await act(async () =>
    root.render(
      createElement(SettingsView, {
        section,
        cwd: "/repo",
        sessions: [],
        onClose: vi.fn(),
        onSelectSection: vi.fn(),
        onOpenSession: vi.fn(),
        onArchiveSession: vi.fn(),
        onDeleteSession: vi.fn(),
      }),
    ),
  );
}

const html = () => document.documentElement;
const query = <T extends Element = HTMLElement>(selector: string) =>
  container.querySelector<T>(selector);
const group = (label: string) => query(`[role="radiogroup"][aria-label="${label}"]`);
const radios = (label: string) =>
  Array.from(group(label)?.querySelectorAll<HTMLButtonElement>('[role="radio"]') ?? []);
const radio = (label: string, name: string) =>
  radios(label).find((button) => button.getAttribute("aria-label") === name);
const click = (node: Element | null | undefined) =>
  act(async () => (node as HTMLElement).click());
const stored = (key: string) => localStorage.getItem(key);

function setValue(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
  setter.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

async function pick(row: string, option: string) {
  const trigger = query<HTMLButtonElement>(`[data-setting-id="${row}"] [aria-haspopup="listbox"]`)!;
  await click(trigger);
  const entry = Array.from(
    document.querySelectorAll<HTMLButtonElement>('[role="option"]'),
  ).find((node) => node.textContent?.trim() === option);
  expect(entry, option).toBeTruthy();
  await click(entry);
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  mockLocalStorage();
  html().removeAttribute("style");
  html().className = "";
  delete html().dataset.theme;
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  vi.mocked(invoke).mockReset().mockResolvedValue(undefined);
  // A background effect reads the image it reshapes; there is no server here.
  vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));
});

afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
  localStorage.clear();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("the color theme gallery", () => {
  it("offers Loci's own theme and every Omarchy theme, starting on Loci's", async () => {
    await render();
    const cards = radios("Color theme");
    expect(cards).toHaveLength(THEMES.length + 1);
    expect(cards[0].getAttribute("aria-label")).toBe("Default");
    expect(cards.filter((card) => card.getAttribute("aria-checked") === "true")).toEqual([cards[0]]);
    for (const theme of THEMES) {
      expect(radio("Color theme", theme.name), theme.id).toBeTruthy();
    }
  });

  it("applies a theme from its card and remembers it", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    expect(stored("loci.themeId")).toBe("tokyo-night");
    expect(html().dataset.theme).toBe("tokyo-night");
    expect(radio("Color theme", "Tokyo Night")!.getAttribute("aria-checked")).toBe("true");
    expect(radio("Color theme", "Default")!.getAttribute("aria-checked")).toBe("false");
    expect(container.textContent).toContain("Tokyo Night sets the colors");
  });

  it("hands the mode, the tint and the accent default over to the theme", async () => {
    await render();
    await click(radio("Color theme", "Rose Pine"));
    const mode = group("Mode")!;
    expect(mode.getAttribute("aria-disabled")).toBe("true");
    expect(
      Array.from(mode.querySelectorAll<HTMLButtonElement>("button")).every((button) => button.disabled),
    ).toBe(true);
    // Rose Pine is a light theme, and the mode control says so.
    expect(mode.querySelector('[aria-checked="true"]')!.textContent).toBe("Light");
    expect(html().classList.contains("theme-light")).toBe(true);
    for (const label of ["Hue", "Saturation", "Dark-mode lightness"]) {
      expect(query<HTMLInputElement>(`input[aria-label="${label}"]`)!.disabled, label).toBe(true);
    }
    expect(container.textContent).toContain("Set by the Rose Pine theme.");
    const accent = query('[data-setting-id="accent-color"]')!;
    expect(accent.querySelector('button[aria-label="Theme"]')).not.toBeNull();
  });

  it("gives the controls back with the default theme", async () => {
    await render();
    await click(radio("Color theme", "Nord"));
    await click(radio("Color theme", "Default"));
    expect(stored("loci.themeId")).toBeNull();
    expect(html().dataset.theme).toBeUndefined();
    expect(group("Mode")!.getAttribute("aria-disabled")).toBeNull();
    expect(query<HTMLInputElement>('input[aria-label="Hue"]')!.disabled).toBe(false);
    expect(query('[data-setting-id="accent-color"] button[aria-label="Default"]')).not.toBeNull();
  });

  it("opens on the saved theme after the page was left and reopened", async () => {
    await render();
    await click(radio("Color theme", "Gruvbox"));
    await render("providers");
    await render("appearance");
    expect(radio("Color theme", "Gruvbox")!.getAttribute("aria-checked")).toBe("true");
    expect(group("Mode")!.getAttribute("aria-disabled")).toBe("true");
  });

  it("restores a saved theme and the fonts at startup", async () => {
    localStorage.setItem("loci.themeId", "kanagawa");
    localStorage.setItem("loci.codeFont", "FiraCode Nerd Font");
    initAppearance();
    await render();
    expect(html().dataset.theme).toBe("kanagawa");
    expect(html().style.getPropertyValue("--font-mono-user")).toContain("FiraCode Nerd Font");
    expect(radio("Color theme", "Kanagawa")!.getAttribute("aria-checked")).toBe("true");
    expect(
      query<HTMLButtonElement>('[data-setting-id="code-font"] [aria-haspopup="listbox"]')!.getAttribute("aria-label"),
    ).toBe("Code font: Fira Code");
  });
});

describe("theme wallpapers", () => {
  const tokyo = () => findTheme("tokyo-night")!;

  it("puts the theme's wallpaper behind the chat and lists its siblings", async () => {
    await render();
    expect(group("Tokyo Night wallpapers")).toBeNull();
    await click(radio("Color theme", "Tokyo Night"));
    expect(stored("loci.chatBackgroundPath")).toBe(tokyo().wallpapers[0].path);
    const thumbs = radios("Tokyo Night wallpapers");
    expect(thumbs).toHaveLength(tokyo().wallpapers.length);
    expect(thumbs[0].getAttribute("aria-checked")).toBe("true");
    expect(thumbs[0].querySelector("img")!.getAttribute("src")).toBe(tokyo().wallpapers[0].thumb);
  });

  it("keeps the effect, scope and visibility controls for a theme wallpaper", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    expect(query('[aria-label="Background effect"]')).not.toBeNull();
    expect(query('[aria-label="Show background on"]')).not.toBeNull();
    expect(query('input[aria-label="Empty chat background visibility"]')).not.toBeNull();
    expect(query('input[aria-label="Session background visibility"]')).not.toBeNull();
    await click(query("#new-thread-background-effect-halftone"));
    expect(stored("loci.newThreadBackgroundEffect")).toBe("halftone");
    // Choosing another theme keeps the effect.
    await click(radio("Color theme", "Nord"));
    expect(stored("loci.newThreadBackgroundEffect")).toBe("halftone");
  });

  it("switches to another of the theme's wallpapers", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    await click(radio("Tokyo Night wallpapers", "Quattro"));
    expect(stored("loci.chatBackgroundPath")).toBe("theme:tokyo-night/1-quattro");
    expect(radio("Tokyo Night wallpapers", "Quattro")!.getAttribute("aria-checked")).toBe("true");
    expect(radio("Tokyo Night wallpapers", "Winding Road")!.getAttribute("aria-checked")).toBe("false");
  });

  it("follows the next theme, and stops following once it is removed", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    await click(radio("Color theme", "Nord"));
    expect(stored("loci.chatBackgroundPath")).toBe(findTheme("nord")!.wallpapers[0].path);
    const remove = Array.from(container.querySelectorAll<HTMLButtonElement>("button")).find(
      (button) => button.textContent?.trim() === "Remove",
    );
    await click(remove);
    expect(invoke).toHaveBeenCalledWith("remove_chat_background");
    expect(stored("loci.chatBackgroundPath")).toBeNull();
    expect(stored("loci.themeWallpaperAuto")).toBe("0");
    await click(radio("Color theme", "Gruvbox"));
    expect(stored("loci.chatBackgroundPath")).toBeNull();
    // Choosing a wallpaper by hand turns following back on.
    await click(radio("Gruvbox wallpapers", findTheme("gruvbox")!.wallpapers[1].name));
    expect(stored("loci.themeWallpaperAuto")).toBe("1");
    await click(radio("Color theme", "Nord"));
    expect(stored("loci.chatBackgroundPath")).toBe(findTheme("nord")!.wallpapers[0].path);
  });

  it("does not replace a picture of the person's own", async () => {
    localStorage.setItem("loci.chatBackgroundPath", "/app-data/backgrounds/chat-background.png");
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    expect(stored("loci.chatBackgroundPath")).toBe("/app-data/backgrounds/chat-background.png");
    // The theme's wallpapers are still on offer.
    await click(radio("Tokyo Night wallpapers", "Swirl Buck"));
    expect(stored("loci.chatBackgroundPath")).toBe("theme:tokyo-night/2-swirl-buck");
  });

  it("drops a theme wallpaper with the theme", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    await click(radio("Color theme", "Default"));
    expect(stored("loci.chatBackgroundPath")).toBeNull();
    expect(group("Tokyo Night wallpapers")).toBeNull();
  });
});

describe("restoring defaults", () => {
  it("returns to Loci's theme, drops the wallpaper and clears the fonts", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    await pick("code-font", "Fira Code");
    await pick("interface-font", "Same as code font");
    const restore = Array.from(container.querySelectorAll<HTMLButtonElement>("button")).find(
      (button) => button.textContent?.includes("Restore defaults"),
    );
    await click(restore);
    expect(stored("loci.themeId")).toBeNull();
    expect(stored("loci.chatBackgroundPath")).toBeNull();
    expect(stored("loci.themeWallpaperAuto")).toBe("1");
    expect(stored("loci.codeFont")).toBeNull();
    expect(stored("loci.uiFont")).toBeNull();
    expect(html().dataset.theme).toBeUndefined();
    expect(html().style.getPropertyValue("--font-mono-user")).toBe("");
    expect(html().classList.contains("has-ui-font")).toBe(false);
    expect(radio("Color theme", "Default")!.getAttribute("aria-checked")).toBe("true");
  });
});

describe("accent color with a theme", () => {
  it("shows the theme's accent until one is picked, and the pick wins", async () => {
    await render();
    await click(radio("Color theme", "Tokyo Night"));
    expect(html().style.getPropertyValue("--user-accent-color")).toBe("#7aa2f7");
    const row = query('[data-setting-id="accent-color"]')!;
    await click(row.querySelector('button[aria-label="Pink"]'));
    expect(stored("loci.accentColor")).toBe("#ec4899");
    expect(html().style.getPropertyValue("--user-accent-color")).toBe("#ec4899");
    await click(radio("Color theme", "Nord"));
    expect(html().style.getPropertyValue("--user-accent-color")).toBe("#ec4899");
    // Back to the theme's own accent.
    await click(row.querySelector('button[aria-label="Theme"]'));
    expect(stored("loci.accentColor")).toBeNull();
    expect(html().style.getPropertyValue("--user-accent-color")).toBe(
      findTheme("nord")!.palette.accent,
    );
  });
});

describe("font settings", () => {
  const trigger = (row: string) =>
    query<HTMLButtonElement>(`[data-setting-id="${row}"] [aria-haspopup="listbox"]`)!;

  it("start on the system fonts", async () => {
    await render();
    expect(trigger("code-font").getAttribute("aria-label")).toBe("Code font: System monospace");
    expect(trigger("interface-font").getAttribute("aria-label")).toBe("Interface font: System default");
  });

  it("offer the fonts Omarchy installs", async () => {
    await render();
    await click(trigger("code-font"));
    const options = Array.from(document.querySelectorAll('[role="option"]')).map(
      (option) => option.textContent?.trim(),
    );
    expect(options).toEqual([
      "System monospace",
      "JetBrains Mono",
      "Cascadia Mono",
      "Meslo LG Mono",
      "Fira Code",
      "Victor Mono",
      "Bitstream Vera Mono",
      "Iosevka",
      "Custom…",
    ]);
  });

  it("only offer 'same as code font' for the interface", async () => {
    await render();
    await click(trigger("interface-font"));
    const options = Array.from(document.querySelectorAll('[role="option"]')).map(
      (option) => option.textContent?.trim(),
    );
    expect(options).toContain("Same as code font");
  });

  it("apply a preset and remember it", async () => {
    await render();
    await pick("code-font", "Fira Code");
    expect(stored("loci.codeFont")).toBe("FiraCode Nerd Font");
    expect(html().style.getPropertyValue("--font-mono-user")).toBe(
      '"FiraCode Nerd Font", var(--font-mono-system)',
    );
    expect(trigger("code-font").getAttribute("aria-label")).toBe("Code font: Fira Code");
    await pick("code-font", "System monospace");
    expect(stored("loci.codeFont")).toBeNull();
    expect(html().style.getPropertyValue("--font-mono-user")).toBe("");
  });

  it("let the interface follow the code font", async () => {
    await render();
    await pick("interface-font", "Same as code font");
    expect(stored("loci.uiFont")).toBe("@code");
    // With no code font there is nothing to follow.
    expect(html().classList.contains("has-ui-font")).toBe(false);
    await pick("code-font", "Iosevka");
    applyFonts();
    expect(html().classList.contains("has-ui-font")).toBe(true);
    expect(html().style.getPropertyValue("--font-sans-user")).toContain("Iosevka Nerd Font Mono");
  });

  it("take a typed font name, and refuse one that is not a plain name", async () => {
    await render();
    await pick("code-font", "Custom…");
    const input = query<HTMLInputElement>('input[aria-label="Code font name"]')!;
    expect(input).not.toBeNull();
    await act(async () => setValue(input, "a; color: red"));
    // React reports a blur as `focusout`; the field was never focused here.
    await act(async () =>
      input.dispatchEvent(new FocusEvent("focusout", { bubbles: true })),
    );
    expect(query('[role="alert"]')!.textContent).toContain("plain font names");
    expect(input.getAttribute("aria-invalid")).toBe("true");
    expect(stored("loci.codeFont")).toBeNull();
    await act(async () => setValue(input, "Cascadia Code, monospace"));
    await act(async () =>
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })),
    );
    expect(query('[role="alert"]')).toBeNull();
    expect(stored("loci.codeFont")).toBe("Cascadia Code, monospace");
    expect(html().style.getPropertyValue("--font-mono-user")).toBe(
      '"Cascadia Code", monospace, var(--font-mono-system)',
    );
    expect(trigger("code-font").getAttribute("aria-label")).toBe("Code font: Custom…");
  });

  it("reopen on a typed font", async () => {
    localStorage.setItem("loci.codeFont", "Source Code Pro");
    await render();
    expect(query<HTMLInputElement>('input[aria-label="Code font name"]')!.value).toBe("Source Code Pro");
  });

  it("clears the custom font editor when defaults are restored", async () => {
    localStorage.setItem("loci.codeFont", "Source Code Pro");
    await render();
    const restore = Array.from(container.querySelectorAll("button")).find(
      (button) => button.textContent?.trim() === "Restore defaults",
    );
    await click(restore);
    expect(query('input[aria-label="Code font name"]')).toBeNull();
    expect(trigger("code-font").getAttribute("aria-label")).toBe("Code font: System monospace");
    expect(stored("loci.codeFont")).toBeNull();
  });

  it("say when a code font would not be monospace, and leave it unused", async () => {
    // Every font measures as proportional here, which is what fontconfig makes of one it lacks.
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation((() => ({
      font: "",
      measureText: (text: string) => ({ width: text.startsWith("W") ? 12 : 8 }),
    })) as never);
    await render();
    await pick("code-font", "Victor Mono");
    expect(container.textContent).toContain("Not installed, or not a monospace font");
    expect(stored("loci.codeFont")).toBe("VictorMono Nerd Font");
    expect(html().style.getPropertyValue("--font-mono-user")).toBe("");
  });

  it("apply a code font that does render as monospace", async () => {
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockImplementation((() => ({
      font: "",
      measureText: (text: string) => ({ width: 8 * text.length }),
    })) as never);
    await render();
    await pick("code-font", "Victor Mono");
    expect(container.textContent).not.toContain("not a monospace font");
    expect(html().style.getPropertyValue("--font-mono-user")).toContain("VictorMono Nerd Font");
  });
});
