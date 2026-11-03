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
import { RemoteSettingsScopeContext, type RemoteSettingsScope } from "../model/settingsScope";
import { setHostSettingSink } from "../../../platform/hostSettings";
import { LOCAL_MODEL_SOURCE, ModelSourceContext, type ModelSource } from "../../sessions/ui/modelSource";
import { setLanguagePreference } from "../../../shared/i18n/locale";
import { SETTINGS_INDEX, SETTINGS_SECTIONS, type SettingsSectionId, } from "../model/settings";
import { HARNESSES, HARNESS_TITLE, } from "../../sessions/model/session";
const withHoverText = (root: Element | null | undefined) => root ? `${root.textContent ?? ""} ${[...root.querySelectorAll("[title]")].map((el) => el.getAttribute("title")).join(" ")}` : "";
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
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => { }) }));
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
let scope: RemoteSettingsScope | null;
let modelSource: ModelSource;
async function render(section: SettingsSectionId, options: Partial<ComponentProps<typeof SettingsView>> = {}) {
    const view = createElement(SettingsView, { section, cwd: "~", onClose: vi.fn(), onSelectSection, ...options });
    await act(async () => root.render(createElement(ModelSourceContext.Provider, { value: modelSource },
        createElement(RemoteSettingsScopeContext.Provider, { value: scope }, view))));
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
const written: string[] = [];
beforeEach(() => {
    scope = { host: "Mac mini", offline: false };
    modelSource = { ...LOCAL_MODEL_SOURCE, id: "remote", refresh: vi.fn(), inspectBinary: vi.fn(async () => ({ path: "/opt/homebrew/bin/claude", version: "2.1" })) };
    written.length = 0;
    // As a window connected to a host registers it: saved shared settings go to the host.
    setHostSettingSink((key) => written.push(key));
});
afterEach(() => setHostSettingSink(undefined));

const text = () => container.textContent ?? "";
const disabledFieldsets = () => [...container.querySelectorAll("fieldset")].filter((fieldset) => fieldset.disabled);

describe("settings in a window connected to another device", () => {
    it("says which settings are the host's, and leaves resetting the workspace to the host", async () => {
        await render("general");
        expect(withHoverText(container.querySelector('[data-setting-id="learning-language"]'))).toContain("Applies to Mac mini.");
        expect(withHoverText(container.querySelector('[data-setting-id="command-line"]'))).toContain("Runs on Mac mini.");
        expect(container.querySelector('[data-setting-id="sounds"]')?.textContent).not.toContain("Mac mini");
        expect(container.querySelector("[data-reset-unavailable]")?.textContent).toContain("only be done on Mac mini itself");
        expect([...container.querySelectorAll("button")].some((button) => /reset workspace/i.test(button.textContent ?? ""))).toBe(false);
        expect(disabledFieldsets()).toEqual([]);
    });

    it("hands a host-shared setting to the host, and keeps appearance on this device", async () => {
        await render("chat");
        const steer = [...container.querySelectorAll<HTMLButtonElement>('[aria-label="Follow-up behavior"] button')].find((button) => button.textContent === "Steer")!;
        await act(async () => steer.click());
        expect(written).toEqual(["loci.followUpBehavior"]);

        await render("appearance");
        await act(async () => container.querySelector<HTMLButtonElement>("#reading-font-serif")!.click());
        expect(localStorage.getItem("loci.readingFont")).toBe("serif");
        expect(written).toEqual(["loci.followUpBehavior"]);
        expect(text()).not.toContain("Mac mini");
    });

    it("marks the host's sections, and the remote-access section as this device's own", async () => {
        for (const [section, note] of [["providers", "Applies to Mac mini."], ["mcp", "Runs on Mac mini."]] as const) {
            await render(section);
            expect(container.querySelector("[data-host-note]")?.textContent).toBe(note);
        }
        await render("remote");
        expect(container.querySelector("[data-host-note]")?.textContent).toContain("this device's own remote-access settings, not Mac mini's");
    });

    it("asks the host about its agent CLIs instead of looking on this device", async () => {
        await render("providers");
        expect(modelSource.refresh).toHaveBeenCalledWith([]);
        expect(vi.mocked(refreshHarnessCatalogs)).not.toHaveBeenCalled();
    });

    it("locks the host's settings while it is offline, and leaves this device's own as they are", async () => {
        scope = { host: "Mac mini", offline: true };
        await render("providers");
        expect(container.querySelector("[data-host-note]")?.textContent).toBe("Mac mini is offline. This is read-only until it is back.");
        expect(disabledFieldsets()).toHaveLength(1);
        expect(disabledFieldsets()[0].querySelector("[data-setting-id]")).not.toBeNull();

        await render("general");
        const learning = container.querySelector('[data-setting-id="learning-language"]')!;
        expect(learning.querySelector("fieldset")?.disabled).toBe(true);
        expect(container.querySelector('[data-setting-id="sounds"] fieldset')).toBeNull();

        await render("appearance");
        expect(disabledFieldsets()).toEqual([]);
    });

    it("shows a window of this device exactly as before", async () => {
        scope = null;
        await render("general");
        expect(container.querySelector("[data-host-note], [data-reset-unavailable], fieldset")).toBeNull();
        expect(container.querySelector('[data-setting-id="learning-language"]')?.textContent).not.toContain("Applies to");
    });
});
