import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { searchSettings, SETTINGS_INDEX, settingsSectionsByGroup, MODEL_CONTROLS_DEFAULT, FOLLOW_UP_BEHAVIOR_DEFAULT, KEYBINDINGS, loadModelControls, loadKeybindingOverrides, loadFollowUpBehavior, keybindingPressed, matchCustomKeybinding, saveModelControls, saveFollowUpBehavior, saveKeybindingOverride, type KeybindingOverride, } from "./settings";
import { IS_MAC, MOD, SHIFT } from "../../../platform/tauri/platform";
const KEY = "loci.composerRunner";
const MODEL_CONTROLS_KEY = "loci.modelControls";
const LEGACY_EFFORT_VISIBLE_KEY = "loci.composerEffortVisible";
const NOTES_KEY = "loci.notesEnabled";
const KEYBINDING_OVERRIDES_KEY = "loci.keybindingOverrides";
const LIVE_AGENTS_KEY = "loci.liveAgentsEnabled";
const FOLLOW_UP_BEHAVIOR_KEY = "loci.followUpBehavior";
const TAB_ANIMATIONS_KEY = "loci.tabAnimationsEnabled";
const COLLAPSED_PROJECT_RAIL_MODE_KEY = "loci.collapsedProjectRailMode";
describe("follow-up behavior setting", () => {
    beforeEach(mockLocalStorage);
    afterEach(() => {
        localStorage.removeItem(FOLLOW_UP_BEHAVIOR_KEY);
    });
    it("defaults to steer", () => {
        expect(FOLLOW_UP_BEHAVIOR_DEFAULT).toBe("steer");
        expect(loadFollowUpBehavior()).toBe("steer");
    });
    it("persists queue behavior", () => {
        saveFollowUpBehavior("queue");
        expect(loadFollowUpBehavior()).toBe("queue");
    });
    it("ignores unknown stored values", () => {
        localStorage.setItem(FOLLOW_UP_BEHAVIOR_KEY, "interrupt");
        expect(loadFollowUpBehavior()).toBe("steer");
    });
});
function mockLocalStorage() {
    const data = new Map<string, string>();
    const storage = {
        getItem: (key: string) => data.get(key) ?? null,
        setItem: (key: string, value: string) => {
            data.set(key, value);
        },
        removeItem: (key: string) => {
            data.delete(key);
        },
        clear: () => {
            data.clear();
        },
        key: (index: number) => [...data.keys()][index] ?? null,
        get length() {
            return data.size;
        },
    };
    Object.defineProperty(globalThis, "localStorage", {
        value: storage,
        configurable: true,
    });
}
describe("model controls setting", () => {
    beforeEach(mockLocalStorage);
    afterEach(() => {
        localStorage.removeItem(MODEL_CONTROLS_KEY);
        localStorage.removeItem(LEGACY_EFFORT_VISIBLE_KEY);
    });
    it("keeps options in the model menu by default", () => {
        expect(MODEL_CONTROLS_DEFAULT).toBe("menu");
        expect(loadModelControls()).toBe("menu");
    });
    it("persists the beside-picker preference", () => {
        saveModelControls("beside");
        expect(localStorage.getItem(MODEL_CONTROLS_KEY)).toBe("beside");
        expect(loadModelControls()).toBe("beside");
        saveModelControls("menu");
        expect(loadModelControls()).toBe("menu");
    });
    it("ignores unknown stored values", () => {
        localStorage.setItem(MODEL_CONTROLS_KEY, "everywhere");
        expect(loadModelControls()).toBe("menu");
    });
    it("migrates the previous effort-control toggle", () => {
        localStorage.setItem(LEGACY_EFFORT_VISIBLE_KEY, "1");
        expect(loadModelControls()).toBe("beside");
        localStorage.setItem(LEGACY_EFFORT_VISIBLE_KEY, "0");
        localStorage.removeItem(MODEL_CONTROLS_KEY);
        expect(loadModelControls()).toBe("menu");
    });
});
describe("keybinding overrides", () => {
    beforeEach(mockLocalStorage);
    const key = (code: string, modifiers: Partial<{
        metaKey: boolean;
        ctrlKey: boolean;
        altKey: boolean;
        shiftKey: boolean;
    }> = {}) => ({
        code,
        metaKey: false,
        ctrlKey: false,
        altKey: false,
        shiftKey: false,
        ...modifiers,
    });
    it("persists a custom shortcut and matches only that combination", () => {
        saveKeybindingOverride("App: Search", { shortcut: "Command+Shift+KeyM" });
        expect(localStorage.getItem(KEYBINDING_OVERRIDES_KEY)).toBe('{"App: Search":{"shortcut":"Command+Shift+KeyM"}}');
        expect(keybindingPressed("App: Search", key("KeyM", { metaKey: true, shiftKey: true }), true)).toBe(true);
        expect(keybindingPressed("App: Search", key("KeyK", { metaKey: true }), true)).toBe(false);
        expect(matchCustomKeybinding(key("KeyM", { metaKey: true, shiftKey: true }))).toBe("App: Search");
        saveKeybindingOverride("App: Search", {});
        expect(localStorage.getItem(KEYBINDING_OVERRIDES_KEY)).toBeNull();
    });
    it("matches real keyboard events whose modifiers are prototype accessors", () => {
        saveKeybindingOverride("App: Search", { shortcut: "Control+Shift+KeyM" });
        // Browsers define metaKey/ctrlKey/altKey/shiftKey on KeyboardEvent.prototype,
        // so they are not own properties and must be read, never spread.
        const prototyped = Object.create({
            code: "KeyM",
            metaKey: false,
            ctrlKey: true,
            altKey: false,
            shiftKey: true,
        }) as Parameters<typeof keybindingPressed>[1];
        expect(keybindingPressed("App: Search", prototyped, false)).toBe(true);
        expect(matchCustomKeybinding(prototyped)).toBe("App: Search");
    });
    it("serves a cached value without letting callers mutate it", () => {
        saveKeybindingOverride("App: Search", { shortcut: "Command+KeyY" });
        const first = loadKeybindingOverrides();
        (first as Record<string, KeybindingOverride>)["Session: Find"] = {
            disabled: true,
        };
        expect(loadKeybindingOverrides()["Session: Find"]).toBeUndefined();
    });
    it("disables a shortcut and restores the default", () => {
        saveKeybindingOverride("App: Search", { disabled: true });
        expect(loadKeybindingOverrides()).toEqual({
            "App: Search": { disabled: true },
        });
        expect(keybindingPressed("App: Search", key("KeyK", { metaKey: true }), true)).toBe(false);
    });
    it("rejects a shortcut already used by another command", () => {
        saveKeybindingOverride("App: Search", { shortcut: "Command+KeyY" });
        expect(() => saveKeybindingOverride("Session: Find", { shortcut: "Command+KeyY" })).toThrow("Already used by App: Search");
    });
    it("rejects a shortcut that shadows another command's default", () => {
        // `Session: Find` is bound to the platform modifier, so hardcoding
        // Control here clashes with nothing on macOS and the assertion passes
        // vacuously.
        const mod = IS_MAC ? "Command" : "Control";
        expect(() => saveKeybindingOverride("App: Search", { shortcut: `${mod}+KeyF` })).toThrow("Already used by Session: Find");
        expect(() => saveKeybindingOverride("Mentor: Next", { shortcut: `${mod}+KeyW` })).toThrow("Already used by Reader: Close");
    });
    it("protects every chord in the grouped mentor activation range", () => {
        const mod = IS_MAC ? "Command" : "Control";
        for (const digit of [1, 4, 9]) {
            expect(() => saveKeybindingOverride("App: Search", {
                shortcut: `${mod}+Digit${digit}`,
            })).toThrow("Already used by Mentor: Activate 1–9");
        }
    });
    it("rejects a chord the command cannot use and invalid chords", () => {
        expect(() => saveKeybindingOverride("Mentor: Activate 1–9", { shortcut: "Control+KeyM" })).toThrow("needs a number key");
        expect(() => saveKeybindingOverride("App: Search", { shortcut: "KeyK" })).toThrow("not a valid shortcut");
    });
    it("normalises modifier order when reading stored shortcuts", () => {
        localStorage.setItem(KEYBINDING_OVERRIDES_KEY, JSON.stringify({ "App: Search": { shortcut: "Shift+Command+KeyM" } }));
        expect(loadKeybindingOverrides()).toEqual({
            "App: Search": { shortcut: "Command+Shift+KeyM" },
        });
    });
    it("ignores malformed, unknown, and invalid stored overrides", () => {
        localStorage.setItem(KEYBINDING_OVERRIDES_KEY, JSON.stringify({
            "Unknown: Command": { disabled: true },
            "App: Search": { shortcut: "KeyK" },
            "Tab: New": { shortcut: "Command+KeyU" },
            "Mentor: New": { shortcut: "Command+KeyT" },
        }));
        // Commands that no longer exist, such as tab ones, are ignored.
        expect(loadKeybindingOverrides()).toEqual({
            "Mentor: New": { shortcut: "Command+KeyT" },
        });
        localStorage.setItem(KEYBINDING_OVERRIDES_KEY, "not-json");
        expect(loadKeybindingOverrides()).toEqual({});
    });
});
describe("workspace navigation keybindings", () => {
    it("keeps separate shortcuts for the library and the conversation", () => {
        expect(KEYBINDINGS.filter((row) => ["App: Toggle Library", "App: Toggle Conversation"].includes(row.command))).toEqual([
            { command: "App: Toggle Library", keys: `${MOD}B`, when: "Always" },
            { command: "App: Toggle Conversation", keys: `${MOD}${SHIFT}B`, when: "Always" },
        ]);
    });
    it("lists no tab, pane, session-list or project commands", () => {
        expect(KEYBINDINGS.filter((row) => /^(Tab|Pane|Project): /.test(row.command) || /^Session: (Previous|Next|Archive)/.test(row.command))).toEqual([]);
        expect(KEYBINDINGS.map((row) => row.command)).toEqual(expect.arrayContaining(["Mentor: New", "Mentor: Next", "Mentor: Previous", "Mentor: Activate 1–9", "Reader: Close"]));
    });
});
describe("settings navigation", () => {
    it("lists every section under exactly one rail group", () => {
        const groups = settingsSectionsByGroup();
        expect(groups.map((group) => group.label)).toEqual([
            "App",
            "Agents",
        ]);
        expect(groups.flatMap((group) => group.sections.map((s) => s.id))).toEqual([
            "general",
            "appearance",
            "keybindings",
            "agents",
            "chat",
            "providers",
            "mcp",
            "skills",
        ]);
    });
    it("points every indexed setting at a real section", () => {
        const sections = new Set(settingsSectionsByGroup().flatMap((group) => group.sections.map((section) => section.id)));
        for (const entry of SETTINGS_INDEX) {
            expect(sections.has(entry.section), entry.id).toBe(true);
        }
    });
});
describe("settings search", () => {
    it("returns nothing for an empty query", () => {
        expect(searchSettings("   ")).toEqual([]);
    });
    it("ranks label matches over keyword matches, and pages last", () => {
        expect(searchSettings("glass").map((result) => result.label)).toEqual([
            "Main pane glass",
            "Blur radius",
            "Sidebar opacity",
            "Appearance",
        ]);
    });
    it("finds a setting by a word that is not in its label", () => {
        expect(searchSettings("steer")[0]).toMatchObject({
            section: "chat",
            sectionLabel: "Chat",
            settingId: "follow-up",
            label: "Follow-up behavior",
        });
    });
    it("returns a whole page with no setting id", () => {
        expect(searchSettings("skills")).toEqual([
            {
                section: "skills",
                sectionLabel: "Skills",
                settingId: null,
                label: "Skills",
            },
        ]);
    });
    it("caps the result list", () => {
        expect(searchSettings("e", 4)).toHaveLength(4);
    });
});
