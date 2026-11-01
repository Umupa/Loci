// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { SettingsLanguage } from "../../../shared/i18n/SettingsLanguage";
import {
  checkForUpdate,
  openUpdatePrompt,
  resetUpdatesForTests,
  usePendingUpdateVersion,
} from "../model/updates";
import { UpdateBadge } from "./UpdateBadge";
import { UpdatePrompt } from "./UpdatePrompt";

const native = vi.hoisted(() => ({ identifier: "com.loci.desktop", current: "0.2.0", available: null as null | Record<string, unknown> }));
const update = vi.hoisted(() => ({
  value: {
    version: "0.3.0",
    currentVersion: "0.2.0",
    body: "## Added\n\n- A thing.",
    close: async () => undefined,
    downloadAndInstall: async () => undefined,
  },
}));

vi.mock("@tauri-apps/api/app", () => ({
  getIdentifier: vi.fn(async () => native.identifier),
  getVersion: vi.fn(async () => native.current),
}));
vi.mock("@tauri-apps/plugin-updater", () => ({ check: vi.fn(async () => native.available) }));
vi.mock("@tauri-apps/plugin-process", () => ({ relaunch: vi.fn(async () => undefined) }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined), convertFileSrc: (path: string) => path }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn(async () => undefined) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({
  useCodePlugin: () => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }),
}));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

/** The rail's badge and the prompt, wired the way the window wires them. */
function UpdateSurfaces() {
  const version = usePendingUpdateVersion();
  return createElement("div", null,
    version ? createElement(UpdateBadge, { version, onOpen: openUpdatePrompt }) : null,
    createElement(UpdatePrompt),
  );
}

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  setLanguagePreference("en");
  resetUpdatesForTests();
  native.identifier = "com.loci.desktop";
  native.current = "0.2.0";
  native.available = null;
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
  act(() => root.render(createElement(UpdateSurfaces)));
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  document.body.replaceChildren();
  resetUpdatesForTests();
  setLanguagePreference("system");
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

const dialog = () => document.querySelector<HTMLElement>('[role="dialog"]');
const badge = () => host.querySelector<HTMLButtonElement>("[data-update-indicator]");

describe("checking from the window", () => {
  it("leaves a quiet check as a badge instead of a modal", async () => {
    native.available = update.value;
    await act(async () => { await checkForUpdate({ interactive: false }); });

    expect(dialog()).toBeNull();
    expect(badge()).not.toBeNull();
    expect(badge()!.getAttribute("aria-label")).toBe("Update available: Loci 0.3.0");
  });

  it("opens the prompt from the badge", async () => {
    native.available = update.value;
    await act(async () => { await checkForUpdate({ interactive: false }); });
    act(() => badge()!.click());

    expect(dialog()).not.toBeNull();
    expect(dialog()!.textContent).toContain("Update Loci");
    expect(dialog()!.textContent).toContain("Loci 0.3.0 is available. You have 0.2.0.");
  });

  it("opens the prompt directly for an interactive check", async () => {
    native.available = update.value;
    await act(async () => { await checkForUpdate({ interactive: true }); });
    expect(dialog()).not.toBeNull();
  });

  it("removes the badge with Later", async () => {
    native.available = update.value;
    await act(async () => { await checkForUpdate({ interactive: false }); });
    act(() => badge()!.click());
    act(() => {
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });

    expect(dialog()).toBeNull();
    expect(badge()).toBeNull();
  });

  it("names the badge in Settings' language", async () => {
    setLanguagePreference("zh-CN");
    act(() => root.render(createElement(SettingsLanguage, null, createElement(UpdateBadge, { version: "0.3.0", onOpen: () => undefined }))));
    expect(badge()!.getAttribute("aria-label")).toBe("有可用更新：Loci 0.3.0");
  });
});
