// @vitest-environment happy-dom
import { act, createElement, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { ask } from "@tauri-apps/plugin-dialog";
import { refreshHarnessCatalogs } from "../../../integrations/harness/core/registry";
import { isHarnessAvailable } from "../../../integrations/harness/core/availability";
import { hasLiveCatalog, modelsFor, resetHarnessModelOverlays, setHarnessModels } from "../../sessions/model/models";
import { SettingsView } from "./SettingsView";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { rememberNotificationProjects } from "../../notifications/model/notificationProjects";
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
vi.mock("@tauri-apps/plugin-dialog", () => ({ ask: vi.fn(async () => true) }));
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
        sessions: [],
        onClose: vi.fn(),
        onSelectSection,
        onOpenSession: vi.fn(),
        onArchiveSession: vi.fn(),
        onDeleteSession: vi.fn(),
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
    it("reopens, scrolls to, focuses and highlights the same project on a repeated notification settings request", async () => {
        vi.useFakeTimers();
        const scroll = vi.spyOn(HTMLElement.prototype, "scrollIntoView");
        rememberNotificationProjects([
            {
                id: "local:/work/app",
                name: "work/app",
                detail: "Local project",
                kind: "local",
                paths: ["/repo"],
            },
        ]);
        const shortcut = {
            anchor: "project-notifications" as const,
            notificationProjectPath: "/repo",
            notificationSettingsRequest: 1,
        };
        await render("general", shortcut);
        const project = container.querySelector<HTMLButtonElement>('button[aria-label="Notification categories for work/app"]')!;
        const card = project.closest("fieldset")!;
        const section = container.querySelector('[data-setting-id="project-notifications"]')!;
        const highlight = () => section.querySelector(".border-accent\\/60");
        expect(highlight()).not.toBeNull();
        expect(project.getAttribute("aria-expanded")).toBe("true");
        expect(document.activeElement).toBe(card);
        await act(async () => vi.advanceTimersByTimeAsync(1800));
        expect(highlight()).toBeNull();
        await act(async () => project.click());
        expect(project.getAttribute("aria-expanded")).toBe("false");
        const search = container.querySelector<HTMLInputElement>('[aria-label="Search settings"]')!;
        search.focus();
        expect(document.activeElement).toBe(search);
        scroll.mockClear();
        await render("general", { ...shortcut, notificationSettingsRequest: 2 });
        expect.soft(project.getAttribute("aria-expanded")).toBe("true");
        expect.soft(scroll).toHaveBeenCalledWith({ block: "nearest" });
        expect.soft(scroll.mock.contexts).toContain(card);
        expect.soft(document.activeElement === card).toBe(true);
        expect.soft(highlight()).not.toBeNull();
        await act(async () => vi.advanceTimersByTimeAsync(1800));
        expect(highlight()).toBeNull();
        expect(project.getAttribute("aria-expanded")).toBe("true");
        expect(document.activeElement).toBe(card);
    });
    it("clears the project shortcut highlight after 1.8 seconds while keeping its project open and focused", async () => {
        vi.useFakeTimers();
        rememberNotificationProjects([
            {
                id: "local:/work/app",
                name: "work/app",
                detail: "Local project",
                kind: "local",
                paths: ["/repo"],
            },
        ]);
        await render("general", {
            anchor: "project-notifications",
            notificationProjectPath: "/repo",
        });
        const section = container.querySelector('[data-setting-id="project-notifications"]')!;
        const project = section.querySelector('button[aria-label="Notification categories for work/app"]')!;
        expect(section.querySelector(".border-accent\\/60")).not.toBeNull();
        expect(project.getAttribute("aria-expanded")).toBe("true");
        expect(document.activeElement).toBe(project.closest("fieldset"));
        await act(async () => vi.advanceTimersByTimeAsync(1800));
        expect(section.querySelector(".border-accent\\/60")).toBeNull();
        expect(project.getAttribute("aria-expanded")).toBe("true");
        expect(document.activeElement).toBe(project.closest("fieldset"));
    });
    it("gives every section a rail group", () => {
        const groups = new Set(SETTINGS_SECTIONS.map((section) => section.group));
        expect([...groups]).toEqual(["app", "agents", "workspace"]);
    });
    it("indexes each setting once", () => {
        const ids = SETTINGS_INDEX.map((entry) => entry.id);
        expect(ids).toEqual([...new Set(ids)]);
    });
    it("offers tab animations as an opt-in", async () => {
        await render("general");
        const control = container.querySelector<HTMLButtonElement>('[role="switch"][aria-label="Tab animations"]')!;
        expect(control.getAttribute("aria-checked")).toBe("false");
        await act(async () => control.click());
        expect(control.getAttribute("aria-checked")).toBe("true");
        expect(localStorage.getItem("loci.tabAnimationsEnabled")).toBe("1");
    });
    it("defaults to the icon rail and lets users hide it", async () => {
        await render("appearance");
        let control = container.querySelector<HTMLElement>('[role="radiogroup"][aria-label="Collapsed project rail"]')!;
        let [iconRail, hidden] = Array.from(control.querySelectorAll<HTMLButtonElement>('[role="radio"]'));
        expect(iconRail?.getAttribute("aria-checked")).toBe("true");
        expect(hidden?.getAttribute("aria-checked")).toBe("false");
        await act(async () => hidden?.click());
        expect(hidden?.getAttribute("aria-checked")).toBe("true");
        expect(localStorage.getItem("loci.collapsedProjectRailMode")).toBe("hidden");
        await act(async () => root.unmount());
        root = createRoot(container);
        await render("appearance");
        control = container.querySelector<HTMLElement>('[role="radiogroup"][aria-label="Collapsed project rail"]')!;
        [iconRail, hidden] = Array.from(control.querySelectorAll<HTMLButtonElement>('[role="radio"]'));
        expect(iconRail?.getAttribute("aria-checked")).toBe("false");
        expect(hidden?.getAttribute("aria-checked")).toBe("true");
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
    it("reports collapsed project rail changes to the app shell", async () => {
        const onCollapsedProjectRailModeChange = vi.fn();
        await render("appearance", {
            collapsedProjectRailMode: "compact",
            onCollapsedProjectRailModeChange,
        });
        const control = container.querySelector<HTMLElement>('[role="radiogroup"][aria-label="Collapsed project rail"]')!;
        const hidden = control.querySelectorAll<HTMLButtonElement>('[role="radio"]')[1];
        await act(async () => hidden?.click());
        expect(onCollapsedProjectRailModeChange).toHaveBeenCalledWith("hidden");
    });
    // The search index is hand-maintained; this is what keeps it honest.
    it.each([...new Set(SETTINGS_INDEX.map((entry) => entry.section))].map((section) => ({ section })))("renders every indexed setting on the $section page", async ({ section }) => {
        await render(section);
        const expected = SETTINGS_INDEX.filter((entry) => entry.section === section).map((entry) => entry.id);
        expect(renderedSettingIds().sort()).toEqual(expected.sort());
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
    it("finds and reveals project notifications separately from global notifications", async () => {
        await render("general");
        await type("project notifications");
        expect(options().map((item) => item.textContent)).toEqual([
            "Project notificationsGeneral",
        ]);
        await act(async () => options()[0]!.click());
        expect(onSelectSection).not.toHaveBeenCalled();
        await render("general");
        const section = container.querySelector('[data-setting-id="project-notifications"]');
        expect(section?.querySelector('[aria-label="Project notifications"]')).not.toBeNull();
        expect(section?.querySelector(".border-accent\\/60")).not.toBeNull();
    });
    // A page whose name starts with the query beats a setting that merely
    // mentions it; anything weaker loses to the settings themselves.
    it("ranks a page against the settings that mention it", async () => {
        await render("general");
        await type("archive");
        expect(options().map((item) => item.querySelector("span")!.textContent)).toEqual(["Archive"]);
        await type("notification");
        expect(options().map((item) => item.querySelector("span")!.textContent)).toEqual([
            "Notifications",
            "Project notifications",
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
});
describe("providers scope inheritance", () => {
    async function selectScope(label: string) {
        const trigger = container.querySelector<HTMLButtonElement>('[aria-label^="Provider defaults scope"]')!;
        await act(async () => trigger.click());
        const option = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="option"]')).find((node) => node.textContent?.trim() === label);
        expect(option).toBeTruthy();
        await act(async () => option!.click());
    }
    it("inherits the global default provider and picker visibility in project scope", async () => {
        localStorage.setItem("loci.lastModel", JSON.stringify({ harness: "claude", model: "claude:opus-5" }));
        localStorage.setItem("loci.hiddenPickerProviders", JSON.stringify(["codex"]));
        await render("providers");
        await selectScope("repo");
        // A project with no overrides shows the inherited global default provider.
        const claudeRow = container
            .querySelector('[aria-label^="Claude Code model"]')!
            .closest(".settings-row")!;
        const claudeDefault = Array.from(claudeRow.querySelectorAll<HTMLButtonElement>("button")).find((node) => node.textContent?.trim() === "Default");
        expect(claudeDefault).toBeTruthy();
        // Picker visibility also inherits the global setting.
        expect(container
            .querySelector<HTMLButtonElement>('[aria-label="Show Claude Code in the model picker"]')!
            .getAttribute("aria-checked")).toBe("true");
        const codexToggle = container.querySelector<HTMLButtonElement>('[aria-label="Show Codex in the model picker"]')!;
        expect(codexToggle.getAttribute("aria-checked")).toBe("false");
        // Global precedence: the project toggle cannot turn a globally hidden
        // provider back on, so it is locked and explained.
        expect(codexToggle.hasAttribute("disabled")).toBe(true);
        expect(codexToggle.closest(".settings-row")?.textContent).toContain("Hidden globally");
    });
});
