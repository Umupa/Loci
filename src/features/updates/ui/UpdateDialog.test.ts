// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { openUrl } from "@tauri-apps/plugin-opener";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { SettingsLanguage } from "../../../shared/i18n/SettingsLanguage";
import type { InstallProgress, PendingUpdate } from "../model/updates";
import { UpdateDialog } from "./UpdateDialog";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined), convertFileSrc: (path: string) => path }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn(async () => undefined) }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({
  useCodePlugin: () => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }),
}));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "dark" }));

const UPDATE: PendingUpdate = {
  version: "0.3.0",
  currentVersion: "0.2.0",
  notes: "## Added\n\n- **Faster** opening\n\nRun `loci updates check`.\n\n### Fixed\n\n- A thing.",
};

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  document.documentElement.lang = "en";
  setLanguagePreference("en");
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(async () => {
  await act(async () => root.unmount());
  host.remove();
  document.body.replaceChildren();
  setLanguagePreference("system");
  vi.unstubAllGlobals();
  vi.clearAllMocks();
});

function mount(
  update: Partial<PendingUpdate> = {},
  progress: InstallProgress = { phase: "idle" },
) {
  const onLater = vi.fn();
  const onInstall = vi.fn();
  act(() => root.render(createElement(SettingsLanguage, null, createElement(UpdateDialog, {
    update: { ...UPDATE, ...update },
    progress,
    onLater,
    onInstall,
  }))));
  return {
    onLater,
    onInstall,
    dialog: () => document.querySelector<HTMLElement>('[role="dialog"]')!,
    button: (label: string) => [...document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')].find((button) => button.textContent?.trim() === label),
  };
}

describe("the update prompt", () => {
  it("shows the versions and the release notes as Markdown", () => {
    const { dialog } = mount();
    expect(dialog().textContent).toContain("Update Loci");
    expect(dialog().textContent).toContain("Loci 0.3.0 is available. You have 0.2.0.");

    const notes = dialog().querySelector("[data-update-notes]")!;
    expect(notes.querySelector("h2")?.textContent).toBe("Added");
    expect([...notes.querySelectorAll("h3")].map((heading) => heading.textContent)).toEqual(["Fixed"]);
    expect(notes.querySelector('[data-streamdown="strong"]')?.textContent).toBe("Faster");
    expect(notes.querySelector("code")?.textContent).toBe("loci updates check");
    expect([...notes.querySelectorAll("li")].map((item) => item.textContent)).toContain("A thing.");
  });

  it("keeps the footer out of the scrolling notes, even when they are very long", () => {
    const longNotes = Array.from({ length: 120 }, (_, index) => `## Section ${index}\n\nParagraph ${index} with **bold** words.`).join("\n\n");
    const { dialog } = mount({ notes: longNotes });
    const notes = dialog().querySelector("[data-update-notes]")!;
    const footer = dialog().querySelector("[data-update-footer]")!;

    expect(footer).not.toBeNull();
    expect(notes.contains(footer)).toBe(false);
    expect(notes.className).toContain("overflow-y-auto");
    expect(notes.className).toContain("max-h-[min(60vh,520px)]");
    expect(footer.textContent).toContain("Later");
    expect(footer.textContent).toContain("Install and Restart");
    expect(notes.compareDocumentPosition(footer) & Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
  });

  it("treats Esc and the close button as Later", () => {
    const { dialog, onLater } = mount();
    act(() => {
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });
    expect(onLater).toHaveBeenCalledTimes(1);

    act(() => dialog().querySelector<HTMLButtonElement>('[aria-label="Close"]')!.click());
    expect(onLater).toHaveBeenCalledTimes(2);
  });

  it("installs with Return, and leaves Return to a focused Later", () => {
    const { dialog, onLater, onInstall, button } = mount();
    const install = dialog().querySelector<HTMLButtonElement>("[data-update-footer] button:last-child")!;
    expect(document.activeElement).toBe(install);

    act(() => {
      install.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
    });
    expect(onInstall).toHaveBeenCalledTimes(1);
    expect(onLater).not.toHaveBeenCalled();

    act(() => {
      button("Later")!.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
    });
    expect(onInstall).toHaveBeenCalledTimes(1);
  });

  it("shows download progress, then installation, with the actions disabled", () => {
    const { dialog, onLater, onInstall, button } = mount({}, { phase: "downloading", percent: 42 });
    const bar = dialog().querySelector('[role="progressbar"]')!;
    expect(bar.getAttribute("aria-valuenow")).toBe("42");
    expect(dialog().textContent).toContain("Downloading… 42%");
    expect(button("Later")!.disabled).toBe(true);
    expect(button("Install and Restart")!.disabled).toBe(true);
    expect(onLater).not.toHaveBeenCalled();
    expect(onInstall).not.toHaveBeenCalled();

    act(() => root.render(createElement(SettingsLanguage, null, createElement(UpdateDialog, {
      update: UPDATE, progress: { phase: "installing" }, onLater, onInstall,
    }))));
    expect(dialog().textContent).toContain("Installing…");
    expect(dialog().querySelector('[role="progressbar"]')).toBeNull();
    expect(button("Later")!.disabled).toBe(true);
    expect(button("Install and Restart")!.disabled).toBe(true);
  });

  it("shows an unknown-size download as busy without a percentage", () => {
    const { dialog } = mount({}, { phase: "downloading", percent: null });
    expect(dialog().textContent).toContain("Downloading…");
    expect(dialog().textContent).not.toContain("%");
    expect(dialog().querySelector('[role="progressbar"]')!.hasAttribute("aria-valuenow")).toBe(false);
  });

  it("shows an install failure inline and offers Retry", () => {
    const { dialog, onInstall, button } = mount({}, { phase: "failed", error: "network down" });
    expect(dialog().querySelector('[data-update-error]')!.textContent).toContain("Could not install the update: network down");
    expect(button("Later")!.disabled).toBe(false);
    act(() => button("Retry")!.click());
    expect(onInstall).toHaveBeenCalledTimes(1);
  });

  it("opens the release notes on GitHub in the system browser", () => {
    const { button } = mount();
    act(() => button("Release notes on GitHub")!.click());
    expect(openUrl).toHaveBeenCalledWith("https://github.com/Umupa/Loci/releases/tag/v0.3.0");
  });

  it("speaks Settings' language when it is opened from Settings", () => {
    setLanguagePreference("zh-CN");
    const { dialog, button } = mount();
    expect(dialog().textContent).toContain("更新 Loci");
    expect(dialog().textContent).toContain("Loci 0.3.0 已可用，你当前使用 0.2.0。");
    expect(button("稍后")).toBeTruthy();
    expect(button("安装并重启")).toBeTruthy();
    expect(button("在 GitHub 查看发布说明")).toBeTruthy();
  });

  it("says so when a release has no notes", () => {
    const { dialog } = mount({ notes: "" });
    expect(dialog().textContent).toContain("This release has no notes.");
    expect(dialog().querySelector("[data-update-notes]")).toBeNull();
  });
});
