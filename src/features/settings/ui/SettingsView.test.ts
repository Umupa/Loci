// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { check } from "@tauri-apps/plugin-updater";
import { resetUpdatesForTests } from "../../updates/model/updates";
import { refreshHarnessCatalogs } from "../../../integrations/harness/core/registry";
import { isHarnessAvailable } from "../../../integrations/harness/core/availability";
import { hasLiveCatalog, modelsFor, resetHarnessModelOverlays, setHarnessModels } from "../../sessions/model/models";
import { SettingsView } from "./SettingsView";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { SETTINGS_INDEX, SETTINGS_SECTIONS, type SettingsSectionId, } from "../model/settings";
import { HARNESSES, HARNESS_TITLE, } from "../../sessions/model/session";
vi.mock("@tauri-apps/api/core", () => ({
    invoke: vi.fn(async () => undefined),
    convertFileSrc: (path: string) => path,
}));
vi.mock("@tauri-apps/api/window", () => ({
    getCurrentWindow: () => ({
        isMaximized: async () => false,
        onResized: async () => () => { },
    }),
}));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn() }));
vi.mock("../model/cliAccess", () => ({
    loadCliAccess: vi.fn(async () => ({ enabled: true, identifier: "com.loci.desktop.test", executable: "/Applications/Loci.app/Contents/MacOS/loci", tokenPath: "/data/control/cli-token", installPath: "/home/me/.local/bin/loci", installed: false })),
    setCliAccess: vi.fn(async (enabled: boolean) => ({ enabled, identifier: "com.loci.desktop.test", executable: null, tokenPath: null, installPath: null, installed: false })),
    rotateCliToken: vi.fn(async () => undefined),
    installCli: vi.fn(async () => ({ enabled: true, identifier: "com.loci.desktop.test", executable: null, tokenPath: null, installPath: "/home/me/.local/bin/loci", installed: true })),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: vi.fn(async () => true) }));
const appInfo = vi.hoisted(() => ({ identifier: "com.loci.desktop", version: "0.2.0", available: null as null | Record<string, unknown> }));
vi.mock("@tauri-apps/api/app", () => ({
    getIdentifier: vi.fn(async () => appInfo.identifier),
    getVersion: vi.fn(async () => appInfo.version),
    getName: vi.fn(async () => "Loci"),
}));
vi.mock("@tauri-apps/plugin-updater", () => ({ check: vi.fn(async () => appInfo.available) }));
vi.mock("@tauri-apps/plugin-process", () => ({ relaunch: vi.fn(async () => undefined) }));
vi.mock("../../../integrations/harness/core/availability", () => ({
    isHarnessAvailable: vi.fn((id: string) => id === "claude" || id === "codex"),
    hasProbedHarnessAvailability: () => true,
    getHarnessAvailabilitySnapshot: () => 0,
    subscribeHarnessAvailability: () => () => { },
    probeHarnessAvailability: async () => { },
    harnessUnavailableHint: () => "",
}));
vi.mock("../../../integrations/harness/core/registry", () => ({ refreshHarnessCatalogs: vi.fn(async () => {}) }));
let container: HTMLDivElement;
let root: Root;
let onSelectSection: ReturnType<typeof vi.fn>;
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
async function render(section: SettingsSectionId, options: Partial<ComponentProps<typeof SettingsView>> = {}) {
    await act(async () => root.render(createElement(SettingsView, {
        section,
        cwd: "/repo",
        onClose: vi.fn(),
        onSelectSection,
        ...options,
    })));
}
function renderedSettingIds(): string[] {
    return Array.from(container.querySelectorAll<HTMLElement>("[data-setting-id]"), (node) => node.dataset.settingId!);
}
beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    mockLocalStorage();
    resetHarnessModelOverlays();
    vi.mocked(refreshHarnessCatalogs).mockClear();
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
    onSelectSection = vi.fn();
    vi.mocked(invoke).mockReset().mockResolvedValue(undefined);
    resetUpdatesForTests();
    appInfo.identifier = "com.loci.desktop";
    appInfo.version = "0.2.0";
    appInfo.available = null;
    vi.mocked(check).mockClear();
});
afterEach(async () => {
    await act(async () => root.unmount());
    container.remove();
    localStorage.clear();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    vi.useRealTimers();
});
describe("settings pages", () => {
    it.each(["pi", "antigravity"] as const)("refreshes %s despite built-in fallback models", async (harness) => {
        vi.mocked(isHarnessAvailable).mockImplementation((id) => id === harness);
        expect(modelsFor(harness).length).toBeGreaterThan(0);
        expect(hasLiveCatalog(harness)).toBe(false);
        await render("providers");
        expect(refreshHarnessCatalogs).toHaveBeenCalledWith([harness]);
    });
    it("skips live catalogs and unavailable harnesses", async () => {
        vi.mocked(isHarnessAvailable).mockImplementation((id) => id === "pi");
        setHarnessModels("pi", modelsFor("pi"));
        await render("providers");
        expect(refreshHarnessCatalogs).not.toHaveBeenCalled();
    });
    it("shows background effect choices above scope when artwork is available", async () => {
        localStorage.setItem("loci.chatBackgroundPath", "/app-data/backgrounds/chat-background.png");
        await render("appearance");
        const effect = container.querySelector("#new-thread-background-effect-dither")!;
        const effectRow = effect.closest(".settings-row")!;
        const scopeRow = container
            .querySelector('[aria-label="Show background on"]')!
            .closest(".settings-row")!;
        expect(effect).not.toBeNull();
        expect(effectRow.compareDocumentPosition(scopeRow) &
            Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
        vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })));
        await act(async () => (effect as HTMLButtonElement).click());
        expect(localStorage.getItem("loci.newThreadBackgroundEffect")).toBe("dither");
        expect(effect.getAttribute("aria-checked")).toBe("true");
        expect(container.textContent).toContain("Rebuilds the artwork with a dithered color palette.");
    });
    it("previews and restores Haze with the existing empty-chat visibility", async () => {
        localStorage.setItem("loci.chatBackgroundPath", "/background.png");
        localStorage.setItem("loci.chatBackgroundEmptyOpacity", "0.4");
        await render("appearance");
        const option = container.querySelector<HTMLButtonElement>("#new-thread-background-effect-gradient-blur")!;
        expect(option.textContent).toBe("Haze");
        await act(async () => option.click());
        const preview = container.querySelector<HTMLElement>(".gradient-blur-background")!;
        expect(option.getAttribute("aria-checked")).toBe("true");
        expect(preview.style.opacity).toBe("0.4");
        expect(preview.querySelectorAll("span")).toHaveLength(2);
        expect(localStorage.getItem("loci.newThreadBackgroundEffect")).toBe("gradient-blur");
        await render("providers");
        await render("appearance");
        expect(container
            .querySelector("#new-thread-background-effect-gradient-blur")
            ?.getAttribute("aria-checked")).toBe("true");
        expect(container.querySelector(".gradient-blur-background")).not.toBeNull();
    });
    it("offers manual auto-detect retry when a CLI is missing", async () => {
        vi.mocked(invoke).mockImplementation(async (command) => {
            if (command === "harness_resolve_codex") {
                throw new Error("Codex CLI not found");
            }
            return undefined;
        });
        await render("providers");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Show Codex CLI details"]')!
            .click());
        const retry = document.querySelector<HTMLButtonElement>('[aria-label="Retry Codex auto-detect"]')!;
        expect(retry).not.toBeNull();
        await act(async () => retry.click());
        expect(invoke).toHaveBeenCalledWith("harness_resolve_codex");
    });
    it("gives every section a rail group", () => {
        const groups = new Set(SETTINGS_SECTIONS.map((section) => section.group));
        expect([...groups]).toEqual(["app", "agents"]);
    });
    it("indexes each setting once", () => {
        const ids = SETTINGS_INDEX.map((entry) => entry.id);
        expect(ids).toEqual([...new Set(ids)]);
    });
    it("starts new mentors with Full access and remembers another default", async () => {
        await render("agents");
        const row = container.querySelector('[data-setting-id="agent-access"]')!;
        const trigger = row.querySelector<HTMLButtonElement>("[data-access-picker-trigger]")!;
        expect(trigger.getAttribute("aria-label")).toBe("Full access");
        await act(async () => trigger.click());
        const option = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="option"]')).find((node) => node.textContent?.includes("Supervised"));
        await act(async () => option!.click());
        expect(localStorage.getItem("loci:agent-default-access")).toBe("supervised");
        expect(trigger.getAttribute("aria-label")).toBe("Supervised");
    });
    it("offers no project, tab, notes or agents switches", async () => {
        await render("general");
        for (const label of ["Projects", "Tab animations", "Tab limit", "Notes", "Working agents"]) {
            expect(container.querySelector(`[role="switch"][aria-label="${label}"]`)).toBeNull();
        }
        await act(async () => root.unmount());
        root = createRoot(container);
        await render("agents");
        expect(container.querySelector('[role="switch"][aria-label="Show agents"]')).toBeNull();
        await act(async () => root.unmount());
        root = createRoot(container);
        await render("appearance");
        expect(container.querySelector('[aria-label="Collapsed project rail"]')).toBeNull();
    });
    it("sets interface scale from a menu instead of a live slider", async () => {
        await render("appearance");
        const row = container.querySelector('[data-setting-id="interface-scale"]')!;
        expect(row.querySelector('input[type="range"]')).toBeNull();
        const trigger = row.querySelector<HTMLButtonElement>('[aria-haspopup="listbox"]')!;
        expect(trigger.getAttribute("aria-label")).toBe("Interface scale: 100%");
        await act(async () => trigger.click());
        const option = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="option"]')).find((node) => node.textContent?.includes("150%"));
        expect(option).toBeTruthy();
        await act(async () => option!.click());
        expect(localStorage.getItem("loci.uiScale")).toBe("1.5");
        expect(trigger.getAttribute("aria-label")).toBe("Interface scale: 150%");
        document.documentElement.style.removeProperty("zoom");
    });
    // The search index is hand-maintained; this is what keeps it honest.
    it.each([...new Set(SETTINGS_INDEX.map((entry) => entry.section))].map((section) => ({ section })))("renders every indexed setting on the $section page", async ({ section }) => {
        await render(section);
        const expected = SETTINGS_INDEX.filter((entry) => entry.section === section).map((entry) => entry.id);
        expect(renderedSettingIds().sort()).toEqual(expected.sort());
    });
    it("turns command-line access off, rotates its token and installs loci", async () => {
        const { setCliAccess, rotateCliToken, installCli } = await import("../model/cliAccess");
        await render("general");
        expect(container.textContent).toContain("/data/control/cli-token");
        const button = (label: string) => [...container.querySelectorAll("button")].find((entry) => entry.textContent === label)!;
        await act(async () => button("Rotate token").click());
        expect(rotateCliToken).toHaveBeenCalled();
        await act(async () => button("Install").click());
        expect(installCli).toHaveBeenCalled();
        expect(container.textContent).toContain("runs this build");
        await act(async () => container.querySelector<HTMLButtonElement>('[aria-label="Command-line access"]')!.click());
        expect(setCliAccess).toHaveBeenCalledWith(false);
        expect(container.textContent).toContain("Terminals cannot reach this Loci");
    });
    it("shows path details for every Agent CLI", async () => {
        await render("providers");
        expect(vi.mocked(invoke).mock.calls.some(([command]) => command === "harness_exec")).toBe(false);
        for (const harness of HARNESSES) {
            expect(container.querySelector(`[aria-label="Show ${HARNESS_TITLE[harness]} CLI details"]`)).not.toBeNull();
        }
    });
    it("returns focus to the CLI trigger when the details popover closes", async () => {
        await render("providers");
        const trigger = container.querySelector<HTMLButtonElement>('[aria-label="Show Codex CLI details"]')!;
        expect(trigger.getAttribute("aria-expanded")).toBe("false");
        await act(async () => trigger.click());
        expect(trigger.getAttribute("aria-expanded")).toBe("true");
        await act(async () => {
            window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
        });
        expect(trigger.getAttribute("aria-expanded")).toBe("false");
        expect(document.activeElement).toBe(trigger);
    });
    it("keeps location failures separate from CLI check failures", async () => {
        vi.mocked(invoke).mockImplementation(async (command) => {
            if (command === "harness_resolve_codex")
                return { path: "/auto/codex" };
            if (command === "harness_exec")
                return "codex-cli 0.156.1";
            if (command === "reveal_path")
                throw new Error("File manager unavailable");
            return undefined;
        });
        await render("providers");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Show Codex CLI details"]')!
            .click());
        await act(async () => document
            .querySelector<HTMLButtonElement>('[aria-label="Open Codex CLI location"]')!
            .click());
        expect(document.body.textContent).toContain("Could not open the CLI location: File manager unavailable");
    });
    it("only tags rows that search can find", async () => {
        for (const section of SETTINGS_SECTIONS.map((item) => item.id)) {
            if (section === "skills")
                continue;
            await render(section);
            for (const id of renderedSettingIds()) {
                expect(SETTINGS_INDEX.some((entry) => entry.id === id), `${section}: ${id}`).toBe(true);
            }
        }
    });
});
describe("settings search", () => {
    async function type(value: string) {
        const input = container.querySelector<HTMLInputElement>('[aria-label="Search settings"]')!;
        await act(async () => {
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
            input.dispatchEvent(new Event("input", { bubbles: true }));
        });
        return input;
    }
    function options(): HTMLButtonElement[] {
        return Array.from(document.querySelectorAll<HTMLButtonElement>('[role="option"]'));
    }
    it("finds a setting that lives on another page", async () => {
        await render("general");
        await type("steer");
        expect(options().map((item) => item.textContent)).toEqual([
            "Follow-up behaviorChat",
        ]);
        await act(async () => options()[0]!.click());
        expect(onSelectSection).toHaveBeenCalledWith("chat");
    });
    // A page whose name starts with the query beats a setting that merely
    // mentions it; anything weaker loses to the settings themselves.
    it("ranks a page against the settings that mention it", async () => {
        await render("general");
        await type("archive");
        expect(options()).toHaveLength(0);
        await type("notification");
        expect(options().map((item) => item.querySelector("span")!.textContent)).toEqual([
            "Notifications",
            "Claude Code hooks",
            "General",

        ]);
    });
    it("closes the results without touching the page when cleared", async () => {
        await render("general");
        const input = await type("sounds");
        expect(options().length).toBeGreaterThan(0);
        await act(async () => {
            container
                .querySelector<HTMLButtonElement>('[aria-label="Clear settings search"]')!
                .click();
        });
        expect(options()).toHaveLength(0);
        expect(input.value).toBe("");
        expect(onSelectSection).not.toHaveBeenCalled();
    });
    it("records a Chinese shortcut label under the original command ID", async () => {
        setLanguagePreference("zh-CN");
        try {
            await render("keybindings");
            const input = container.querySelector<HTMLInputElement>('[aria-label="更改“应用：搜索”的快捷键"]')!;
            expect(input).not.toBeNull();
            await act(async () => input.click());
            await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
                code: "KeyM", key: "m", ctrlKey: true, shiftKey: true,
                bubbles: true, cancelable: true,
            })));
            expect(JSON.parse(localStorage.getItem("loci.keybindingOverrides")!)).toEqual({
                "App: Search": { shortcut: "Control+Shift+KeyM" },
            });
            await act(async () => setLanguagePreference("en"));
            expect(container.querySelector('[aria-label="Change App: Search shortcut"]')).toBe(input);
        } finally {
            await act(async () => setLanguagePreference("en"));
        }
    });
    it("records a custom keybinding from the key cell", async () => {
        await render("keybindings");
        const input = container.querySelector<HTMLInputElement>('[aria-label="Change App: Search shortcut"]')!;
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "KeyM",
            key: "m",
            ctrlKey: true,
            shiftKey: true,
            bubbles: true,
            cancelable: true,
        })));
        expect(localStorage.getItem("loci.keybindingOverrides")).toBe('{"App: Search":{"shortcut":"Control+Shift+KeyM"}}');
        expect(input.value).toBe("Ctrl+Shift+M");
    });
    it("lets Tab leave the recorder and keeps Cmd+Delete recordable", async () => {
        await render("keybindings");
        const input = container.querySelector<HTMLInputElement>('[aria-label="Change App: Search shortcut"]')!;
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "Tab",
            key: "Tab",
            bubbles: true,
            cancelable: true,
        })));
        expect(container.textContent).not.toContain("Del disables");
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "Delete",
            key: "Delete",
            metaKey: true,
            bubbles: true,
            cancelable: true,
        })));
        expect(localStorage.getItem("loci.keybindingOverrides")).toBe('{"App: Search":{"shortcut":"Command+Delete"}}');
    });
    it("surfaces a storage failure instead of silently dropping the change", async () => {
        await render("keybindings");
        (localStorage as unknown as {
            setItem: (key: string, value: string) => void;
        }).setItem = () => {
            throw new Error("quota exceeded");
        };
        const input = container.querySelector<HTMLInputElement>('[aria-label="Change App: Search shortcut"]')!;
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "KeyY",
            key: "y",
            ctrlKey: true,
            shiftKey: true,
            bubbles: true,
            cancelable: true,
        })));
        expect(container.textContent).toContain("Could not save shortcuts");
        // The message sits inside the card as a wrapping line, so the last
        // row's recorder cannot clip it.
        const alert = container.querySelector('[role="alert"]')!;
        expect(alert.className).toContain("break-words");
        expect(alert.closest(".overflow-hidden")).not.toBeNull();
    });
    it("records an Alt shortcut on a keybinding row", async () => {
        await render("keybindings");
        const input = container.querySelector<HTMLInputElement>('[aria-label="Change App: Search shortcut"]')!;
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "KeyM",
            key: "m",
            altKey: true,
            bubbles: true,
            cancelable: true,
        })));
        expect(localStorage.getItem("loci.keybindingOverrides")).toBe('{"App: Search":{"shortcut":"Option+KeyM"}}');
        expect(input.value).toBe("Alt+M");
    });
    it("disables and restores an individual keybinding", async () => {
        await render("keybindings");
        const input = container.querySelector<HTMLInputElement>('[aria-label="Change App: Search shortcut"]')!;
        await act(async () => input.click());
        await act(async () => document.body.dispatchEvent(new KeyboardEvent("keydown", {
            code: "Backspace",
            key: "Backspace",
            bubbles: true,
            cancelable: true,
        })));
        expect(localStorage.getItem("loci.keybindingOverrides")).toBe('{"App: Search":{"disabled":true}}');
        expect(input.value).toBe("Disabled");
        await act(async () => container
            .querySelector<HTMLButtonElement>('[aria-label="Reset App: Search shortcut"]')!
            .click());
        expect(localStorage.getItem("loci.keybindingOverrides")).toBeNull();
    });
    it("reveals a setting on the current page", async () => {
        await render("general");
        await type("sounds");
        await act(async () => options()[0]!.click());
        expect(onSelectSection).not.toHaveBeenCalled();
        const row = container.querySelector('[data-setting-id="sounds"]')!;
        expect(row.className).toContain("bg-accent/10");
    });
    it.each([
        ["fonts", "Fonts", "appearance"],
        ["shortcuts", "Shortcuts", "keybindings"],
        ["themes", "Color theme", "appearance"],
        ["token", "Token", "general"],
        ["reset workspace", "Reset workspace", "general"],
    ])("finds %s through search", async (query, label, section) => {
        await render("general");
        await type(query);
        const match = options().find((node) => node.textContent?.includes(label));
        expect(match, query).toBeTruthy();
        await act(async () => match!.click());
        if (section === "general") {
            const id = query === "token" ? "token" : "reset-workspace";
            const revealed = container.querySelector(`[data-setting-id="${id}"]`)!;
            // A row flashes its background; a card outline flashes its border.
            if (id === "reset-workspace")
                expect(revealed.innerHTML).toContain("border-accent/60");
            else
                expect(revealed.className).toContain("bg-accent/10");
        }
        else {
            expect(onSelectSection).toHaveBeenCalledWith(section);
        }
    });
});
describe("mentor rows and global providers", () => {
    it("opens a mentor's own settings from its row", async () => {
        localStorage.setItem("loci:agent-roster", JSON.stringify([
            { id: "ada", name: "Ada", avatar: "ember", color: "#fff", projects: [] },
        ]));
        const onOpenMentorSettings = vi.fn();
        await render("agents", { onOpenMentorSettings });
        // The page points at the settings that exist and stops promising habits.
        expect(container.textContent).not.toContain("habits");
        const open = container.querySelector<HTMLButtonElement>('[aria-label="Open Ada settings"]')!;
        expect(open).not.toBeNull();
        await act(async () => open.click());
        expect(onOpenMentorSettings).toHaveBeenCalledWith("ada");
    });
    it("offers global provider defaults with no project scope", async () => {
        await render("providers");
        expect(container.querySelector('[aria-label^="Provider defaults scope"]')).toBeNull();
        expect(container.textContent).not.toContain("this project");
        const codexToggle = container.querySelector<HTMLButtonElement>('[aria-label="Show Codex in the model picker"]')!;
        await act(async () => codexToggle.click());
        expect(JSON.parse(localStorage.getItem("loci.hiddenPickerProviders")!)).toEqual(["codex"]);
        expect(codexToggle.getAttribute("aria-checked")).toBe("false");
    });
});
describe("updates in About", () => {
    function buttonByText(label: string) {
        return [...container.querySelectorAll<HTMLButtonElement>("button")].find((node) => node.textContent?.trim() === label);
    }
    it("says the version is current beside it instead of in a dialog", async () => {
        await render("general");
        const checkButton = buttonByText("Check for Updates");
        expect(checkButton).toBeTruthy();
        await act(async () => { checkButton!.click(); });
        await act(async () => {});
        expect(container.textContent).toContain("You have the latest version.");
        expect(document.querySelector('[role="dialog"]')).toBeNull();
    });
    it("shows a check failure beside the version", async () => {
        vi.mocked(check).mockRejectedValueOnce(new Error("offline"));
        await render("general");
        await act(async () => { buttonByText("Check for Updates")!.click(); });
        await act(async () => {});
        expect(container.textContent).toContain("Could not check for updates: offline");
        expect(document.querySelector('[role="dialog"]')).toBeNull();
    });
    it("offers a release a quiet check found", async () => {
        appInfo.available = { version: "0.3.0", currentVersion: "0.2.0", body: "## Added\n\n- A thing.", close: async () => undefined, downloadAndInstall: async () => undefined };
        await render("general");
        const { checkForUpdate } = await import("../../updates/model/updates");
        await act(async () => { await checkForUpdate({ interactive: false }); });
        expect(container.textContent).toContain("Loci 0.3.0 is available.");
        expect(buttonByText("View update")).toBeTruthy();
        expect(document.querySelector('[role="dialog"]')).toBeNull();
    });
});
