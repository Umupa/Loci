import { t } from "../../../shared/i18n/locale";
import { IS_MAC, IS_WIN, MOD, SHIFT } from "../../../platform/tauri/platform";
import { canonicalShortcut, shortcutLabel, shortcutFromKeyEvent, shortcutTokens } from "../../../shared/lib/shortcuts";
import { readFlag, writeFlag } from "./storageFlags";
const SECTION_KEY = "loci.settingsSection";
export type SettingsSectionId = "general" | "appearance" | "keybindings" | "agents" | "chat" | "providers" | "mcp" | "skills";
/** Rail buckets. Sections list in order under their group label. */
export type SettingsGroupId = "app" | "agents" | "workspace";
export const SETTINGS_GROUPS: {
    id: SettingsGroupId;
    label: string;
}[] = [
    { id: "app", get label() { return t("App"); } },
    { id: "agents", get label() { return t("Agents"); } },
    { id: "workspace", get label() { return t("Workspace"); } },
];
export type SettingsSection = {
    id: SettingsSectionId;
    group: SettingsGroupId;
    label: string;
    description: string;
    /** Extra words search matches the section on, beyond its label. */
    keywords?: string;
};
export const SETTINGS_SECTIONS: SettingsSection[] = [
    {
        id: "general",
        group: "app",
        get label() { return t("General"); },
        get description() { return t("The build you are running, how Loci reaches you, and the panels it shows."); },
        keywords: "sounds notifications notes rail",
    },
    {
        id: "appearance",
        group: "app",
        get label() { return t("Appearance"); },
        get description() { return t("Theme, tint, translucency, workspace layout, and conversation backgrounds."); },
        keywords: "theme dark light color accent glass blur zoom scale wallpaper rail sidebar",
    },
    {
        id: "keybindings",
        group: "app",
        get label() { return t("Keybindings"); },
        get description() { return t("Every shortcut the workspace handles, from the app menu and the key handler."); },
        keywords: "shortcut hotkey keyboard binding",
    },
    {
        id: "agents",
        group: "agents",
        get label() { return t("Your agents"); },
        get description() { return t("Long-lived agents on the project rail: whether they are shown, and the ones you have."); },
        keywords: "agent persistent memory soul habits schedule rail reset",
    },
    {
        id: "chat",
        group: "agents",
        get label() { return t("Chat"); },
        get description() { return t("How transcripts read and what the composer does with a follow-up."); },
        keywords: "transcript composer prompt message",
    },
    {
        id: "providers",
        group: "agents",
        get label() { return t("Providers"); },
        get description() { return t("Agent CLIs Loci can drive, and the model new sessions start with."); },
        keywords: "model harness claude codex cursor grok opencode pi omp fx hermes antigravity cli default hooks",
    },
    {
        id: "mcp",
        group: "agents",
        label: "MCP",
        get description() { return t("Manage Loci's built-in MCP servers and your provider connections."); },
        keywords: "tools servers connections oauth authenticate login claude codex built-in excalidraw canvas",
    },
    {
        id: "skills",
        group: "agents",
        get label() { return t("Skills"); },
        get description() { return t("Discover and manage file skills from project, personal, and harness folders."); },
        keywords: "skill instructions prompt",
    },
];
export function settingsSectionsByGroup(): {
    id: SettingsGroupId;
    label: string;
    sections: SettingsSection[];
}[] {
    return SETTINGS_GROUPS.map((group) => ({
        ...group,
        sections: SETTINGS_SECTIONS.filter((section) => section.group === group.id),
    })).filter((group) => group.sections.length > 0);
}
/**
 * One searchable control. `id` is the row's `data-setting-id` in SettingsView,
 * which is also what Settings scrolls to when it opens on an anchor.
 */
export type SettingsEntry = {
    id: string;
    section: SettingsSectionId;
    label: string;
    keywords?: string;
};
export const SETTINGS_INDEX: SettingsEntry[] = [
    {
        id: "language",
        section: "general",
        get label() { return t("Settings language"); },
        keywords: "language locale english chinese 中文 简体 语言 英文",
    },
{ id: "version", section: "general", get label() { return t("Version"); }, keywords: "build about update upgrade release" },
    {
        id: "builtin-excalidraw",
        section: "mcp",
        get label() { return t("Built-in Excalidraw MCP"); },
        keywords: "loci_excalidraw drawing canvas built-in enable disable claude codex",
    },
    {
        id: "mcp-servers",
        section: "mcp",
        get label() { return t("MCP servers"); },
        keywords: "claude tools connections oauth authenticate login add remove",
    },
    {
        id: "sounds",
        section: "general",
        get label() { return t("Sounds"); },
        keywords: "audio cue chime mute volume",
    },
    {
        id: "notifications",
        section: "general",
        get label() { return t("Notifications"); },
        keywords: "notify alert toast permission background",
    },
    {
        id: "agent-list",
        section: "agents",
        get label() { return t("Your agents"); },
        keywords: "agent mentor reset soul name folders",
    },
    ...(IS_WIN
        ? [
            {
                id: "close-to-tray",
                section: "general" as const,
                get label() { return t("Close to tray"); },
                keywords: "minimize background quit exit window taskbar windows",
            },
        ]
        : []),
    {
        id: "color-theme",
        section: "appearance",
        get label() { return t("Color theme"); },
        keywords: "omarchy palette wallpaper catppuccin gruvbox tokyo night nord rose pine everforest kanagawa matte black white dark light colors",
    },
    {
        id: "theme",
        section: "appearance",
        get label() { return t("Mode"); },
        keywords: "theme dark light system appearance",
    },
    {
        id: "accent-color",
        section: "appearance",
        get label() { return t("Accent color"); },
        keywords: "highlight bubble send button tint",
    },
    {
        id: "hue",
        section: "appearance",
        get label() { return t("Hue"); },
        keywords: "tint color chrome",
    },
    {
        id: "saturation",
        section: "appearance",
        get label() { return t("Saturation"); },
        keywords: "tint color neutral grey gray",
    },
    {
        id: "dark-lightness",
        section: "appearance",
        get label() { return t("Dark-mode lightness"); },
        keywords: "black brightness contrast background",
    },
    {
        id: "code-font",
        section: "appearance",
        get label() { return t("Code font"); },
        keywords: "monospace typeface jetbrains nerd font omarchy code blocks",
    },
    {
        id: "interface-font",
        section: "appearance",
        get label() { return t("Interface font"); },
        keywords: "typeface sans system font ui text",
    },
    {
        id: "sidebar-opacity",
        section: "appearance",
        get label() { return t("Sidebar opacity"); },
        keywords: "glass translucent transparency vibrancy",
    },
    {
        id: "blur",
        section: "appearance",
        get label() { return t("Blur radius"); },
        keywords: "glass translucent vibrancy backdrop",
    },
    {
        id: "main-pane-glass",
        section: "appearance",
        get label() { return t("Main pane glass"); },
        keywords: "translucent transparency body window",
    },
    {
        id: "interface-scale",
        section: "appearance",
        get label() { return t("Interface scale"); },
        keywords: "zoom font size bigger smaller ui",
    },
    {
        id: "chat-background",
        section: "appearance",
        get label() { return t("Chat background"); },
        keywords: "wallpaper image picture opacity backdrop",
    },
    {
        id: "transcript-layout",
        section: "chat",
        get label() { return t("Transcript layout"); },
        keywords: "full width chat bubble message",
    },
    {
        id: "anchor-prompts",
        section: "chat",
        get label() { return t("Anchor prompts to top"); },
        keywords: "scroll position sticky message",
    },
    {
        id: "follow-up",
        section: "chat",
        get label() { return t("Follow-up behavior"); },
        keywords: "queue steer interrupt send while running",
    },
    {
        id: "model-controls",
        section: "chat",
        get label() { return t("Model controls"); },
        keywords: "effort thinking reasoning fast service tier model picker composer",
    },
    {
        id: "composer-mascot",
        section: "chat",
        get label() { return t("Composer mascot"); },
        keywords: "runner animation coin pixel",
    },
    {
        id: "agent-clis",
        section: "providers",
        get label() { return t("Agent CLIs"); },
        keywords: "claude codex cursor grok opencode pi omp fx hermes antigravity binary path",
    },
    {
        id: "claude-hooks",
        section: "providers",
        get label() { return t("Claude Code hooks"); },
        keywords: "pretooluse settings.json block command notification",
    },
];
export type SettingsSearchResult = {
    section: SettingsSectionId;
    sectionLabel: string;
    /** Row to scroll to, or `null` when the whole section matched. */
    settingId: string | null;
    label: string;
};
/** Ranks a label/keyword pair against a lowercased needle; `null` means no match. */
function matchScore(needle: string, label: string, keywords?: string): number | null {
    const lower = label.toLowerCase();
    if (lower.startsWith(needle))
        return 0;
    if (lower.includes(needle))
        return 1;
    if (keywords?.toLowerCase().includes(needle))
        return 2;
    return null;
}
/** Individual settings first, then whole sections, so a row wins its own name. */
export function searchSettings(query: string, limit = 8): SettingsSearchResult[] {
    const needle = query.trim().toLowerCase();
    if (!needle)
        return [];
    const scored: {
        score: number;
        result: SettingsSearchResult;
    }[] = [];
    for (const entry of SETTINGS_INDEX) {
        const score = matchScore(needle, entry.label, entry.keywords);
        if (score == null)
            continue;
        scored.push({
            score,
            result: {
                section: entry.section,
                sectionLabel: settingsSectionLabel(entry.section),
                settingId: entry.id,
                label: entry.label,
            },
        });
    }
    for (const section of SETTINGS_SECTIONS) {
        const score = matchScore(needle, section.label, `${section.description} ${section.keywords ?? ""}`);
        if (score == null)
            continue;
        scored.push({
            score: score + 0.5,
            result: {
                section: section.id,
                sectionLabel: section.label,
                settingId: null,
                label: section.label,
            },
        });
    }
    return scored
        .sort((a, b) => a.score - b.score || a.result.label.localeCompare(b.result.label))
        .slice(0, limit)
        .map((item) => item.result);
}
export const SETTINGS_SECTION_DEFAULT: SettingsSectionId = "general";
export function isSettingsSectionId(value: unknown): value is SettingsSectionId {
    return SETTINGS_SECTIONS.some((section) => section.id === value);
}
export function settingsSectionLabel(id: SettingsSectionId): string {
    return (SETTINGS_SECTIONS.find((section) => section.id === id)?.label ?? "General");
}
export function settingsSectionDescription(id: SettingsSectionId): string {
    return (SETTINGS_SECTIONS.find((section) => section.id === id)?.description ?? "");
}
export function loadSettingsSection(): SettingsSectionId {
    try {
        const raw = localStorage.getItem(SECTION_KEY);
        return isSettingsSectionId(raw) ? raw : SETTINGS_SECTION_DEFAULT;
    }
    catch {
        return SETTINGS_SECTION_DEFAULT;
    }
}
export function saveSettingsSection(id: SettingsSectionId) {
    try {
        localStorage.setItem(SECTION_KEY, id);
    }
    catch {
        // private mode / quota
    }
}
const FOLLOW_UP_BEHAVIOR_KEY = "loci.followUpBehavior";
const COMPOSER_EFFORT_VISIBLE_KEY = "loci.composerEffortVisible";
const MODEL_CONTROLS_KEY = "loci.modelControls";
export type FollowUpBehavior = "steer" | "queue";
export const FOLLOW_UP_BEHAVIOR_DEFAULT: FollowUpBehavior = "steer";
export function loadFollowUpBehavior(): FollowUpBehavior {
    try {
        const raw = localStorage.getItem(FOLLOW_UP_BEHAVIOR_KEY);
        return raw === "queue" || raw === "steer"
            ? raw
            : FOLLOW_UP_BEHAVIOR_DEFAULT;
    }
    catch {
        return FOLLOW_UP_BEHAVIOR_DEFAULT;
    }
}
export function saveFollowUpBehavior(value: FollowUpBehavior) {
    try {
        localStorage.setItem(FOLLOW_UP_BEHAVIOR_KEY, value);
    }
    catch {
        // private mode / quota
    }
}
export type ModelControls = "menu" | "beside";
export const MODEL_CONTROLS_DEFAULT: ModelControls = "menu";
/** Fired on `window` when the composer model controls setting flips. */
export const MODEL_CONTROLS_CHANGE_EVENT = "loci:model-controls-change";
export function loadModelControls(): ModelControls {
    try {
        const raw = localStorage.getItem(MODEL_CONTROLS_KEY);
        if (raw === "menu" || raw === "beside")
            return raw;
        if (raw == null) {
            // Migrate the previous effort-control toggle: on means beside the picker.
            const legacy = localStorage.getItem(COMPOSER_EFFORT_VISIBLE_KEY);
            if (legacy === "1" || legacy === "true")
                return "beside";
        }
    }
    catch {
        // private mode / quota
    }
    return MODEL_CONTROLS_DEFAULT;
}
export function saveModelControls(value: ModelControls) {
    try {
        localStorage.setItem(MODEL_CONTROLS_KEY, value);
    }
    catch {
        // private mode / quota
    }
    if (typeof window === "undefined")
        return;
    window.dispatchEvent(new CustomEvent<ModelControls>(MODEL_CONTROLS_CHANGE_EVENT, {
        detail: value,
    }));
}
export function subscribeModelControls(onStoreChange: () => void) {
    if (typeof window === "undefined")
        return () => { };
    window.addEventListener(MODEL_CONTROLS_CHANGE_EVENT, onStoreChange);
    return () => window.removeEventListener(MODEL_CONTROLS_CHANGE_EVENT, onStoreChange);
}
const COMPOSER_RUNNER_KEY = "loci.composerRunner";
export const COMPOSER_RUNNER_DEFAULT = true;
export const COMPOSER_RUNNER_CHANGE_EVENT = "loci:composer-runner-change";
export function loadComposerRunner(): boolean {
    return readFlag(COMPOSER_RUNNER_KEY) ?? COMPOSER_RUNNER_DEFAULT;
}
export function saveComposerRunner(value: boolean) {
    writeFlag(COMPOSER_RUNNER_KEY, value);
    if (typeof window !== "undefined") window.dispatchEvent(new CustomEvent<boolean>(COMPOSER_RUNNER_CHANGE_EVENT, { detail: value }));
}
export function subscribeComposerRunner(onStoreChange: () => void) {
    if (typeof window === "undefined") return () => {};
    window.addEventListener(COMPOSER_RUNNER_CHANGE_EVENT, onStoreChange);
    return () => window.removeEventListener(COMPOSER_RUNNER_CHANGE_EVENT, onStoreChange);
}

/** Fired on `window` if notes are switched off; they no longer can be. */
export const NOTES_ENABLED_CHANGE_EVENT = "loci:notes-enabled-change";
/**
 * Notes are always on: they belong to mentors now. An off switch saved by an
 * earlier version (`loci.notesEnabled`) is ignored.
 */
export function loadNotesEnabled(): boolean {
    return true;
}
export function subscribeNotesEnabled(onStoreChange: () => void) {
    if (typeof window === "undefined")
        return () => { };
    window.addEventListener(NOTES_ENABLED_CHANGE_EVENT, onStoreChange);
    return () => window.removeEventListener(NOTES_ENABLED_CHANGE_EVENT, onStoreChange);
}
const CLOSE_TO_TRAY_KEY = "loci.closeToTray";
export const CLOSE_TO_TRAY_DEFAULT = true;
export function loadCloseToTray(): boolean {
    // Close to tray is Windows-only: nowhere else installs a tray icon.
    if (!IS_WIN)
        return false;
    return readFlag(CLOSE_TO_TRAY_KEY) ?? CLOSE_TO_TRAY_DEFAULT;
}
export function saveCloseToTray(value: boolean) {
    writeFlag(CLOSE_TO_TRAY_KEY, value);
}
const CLAUDE_HOOKS_KEY = "loci.claudeHooks";
export const CLAUDE_HOOKS_DEFAULT = true;
export function loadClaudeHooks(): boolean {
    return readFlag(CLAUDE_HOOKS_KEY) ?? CLAUDE_HOOKS_DEFAULT;
}
export function saveClaudeHooks(value: boolean) {
    writeFlag(CLAUDE_HOOKS_KEY, value);
}
export type KeybindingRow = {
    command: string;
    keys: string;
    when: string;
};
/**
 * Mirrors the bindings we actually handle: the native menu accelerators in
 * `src-tauri/src/menu.rs`, `appCommand`, the window key handler in App, and
 * focused surface handlers.
 */
export const KEYBINDINGS: KeybindingRow[] = [
    { command: "Session: Find", keys: `${MOD}F`, when: "sessionFocus" },
    { command: "App: Settings", keys: `${MOD},`, when: "Always" },
    { command: "App: Search", keys: `${MOD}K`, when: "Always" },
    { command: "App: New Window", keys: `${MOD}${SHIFT}N`, when: "Always" },
    { command: "App: Toggle Library", keys: `${MOD}B`, when: "Always" },
    { command: "App: Toggle Conversation", keys: `${MOD}${SHIFT}B`, when: "Always" },
    { command: "App: Switch Model", keys: `${MOD}.`, when: "Always" },
    { command: "View: Reload", keys: `${MOD}${SHIFT}R`, when: "Always" },
    { command: "View: Zoom In", keys: `${MOD}+`, when: "Always" },
    { command: "View: Zoom Out", keys: `${MOD}-`, when: "Always" },
    { command: "View: Reset Zoom", keys: `${MOD}0`, when: "Always" },
    { command: "Mentor: New", keys: `${MOD}T`, when: "Always" },
    { command: "Mentor: Next", keys: `${MOD}${SHIFT}]`, when: "Always" },
    { command: "Mentor: Previous", keys: `${MOD}${SHIFT}[`, when: "Always" },
    { command: "Mentor: Activate 1–9", keys: `${MOD}1 … ${MOD}9`, when: "Always" },
    { command: "Reader: Close", keys: `${MOD}W`, when: "Always" },
];
const KEYBINDING_OVERRIDES_KEY = "loci.keybindingOverrides";
const KEYBINDINGS_CHANGE_EVENT = "loci:keybindings-change";
export type KeybindingOverride = {
    disabled?: boolean;
    shortcut?: string;
};
export type KeybindingOverrides = Record<string, KeybindingOverride>;
const VALID_COMMANDS = new Set(KEYBINDINGS.map((row) => row.command));
const KEY_CODES: Record<string, string> = {
    " ": "Space",
    Enter: "Enter",
    Space: "Space",
    Tab: "Tab",
    "`": "Backquote",
    "[": "BracketLeft",
    "]": "BracketRight",
    ",": "Comma",
    ".": "Period",
    "+": "Equal",
    "-": "Minus",
    "\\": "Backslash",
    "↑": "ArrowUp",
    "↓": "ArrowDown",
    "←": "ArrowLeft",
    "→": "ArrowRight",
};
const DISPLAY_MODIFIERS: [
    string,
    string
][] = IS_MAC
    ? [
        ["⌘", "Command"],
        ["⌃", "Control"],
        ["⌥", "Option"],
        ["⇧", "Shift"],
    ]
    : [
        ["Ctrl+", "Control"],
        ["Alt+", "Option"],
        ["Shift+", "Shift"],
    ];
const ACTIVATE_RANGE_COMMAND = "Mentor: Activate 1–9";
/**
 * Every chord a command owns by default, in stored form. Grouped rows expand
 * to one chord per key so a rebind can never shadow a working shortcut.
 */
function defaultShortcutsFor(command: string): string[] {
    const row = KEYBINDINGS.find((entry) => entry.command === command);
    if (!row)
        return [];
    let rest = row.keys;
    const modifiers: string[] = [];
    for (const [display, modifier] of DISPLAY_MODIFIERS) {
        if (rest.startsWith(display)) {
            modifiers.push(modifier);
            rest = rest.slice(display.length);
        }
    }
    const chords = (code: string) => {
        const value = canonicalShortcut(modifiers.length ? [...modifiers, code].join("+") : code);
        return value ? [value] : [];
    };
    if (row.keys.includes("…")) {
        return [1, 2, 3, 4, 5, 6, 7, 8, 9].flatMap((digit) => chords(`Digit${digit}`));
    }
    if (/^[A-Za-z]$/.test(rest))
        return chords(`Key${rest.toUpperCase()}`);
    if (/^[0-9]$/.test(rest))
        return chords(`Digit${rest}`);
    if (KEY_CODES[rest])
        return chords(KEY_CODES[rest]);
    if (/^F(?:[1-9]|1[0-9]|2[0-4])$/.test(rest))
        return chords(rest);
    return [];
}
function shortcutOwners(): Map<string,string> {
 const owners = new Map<string,string>();
 for (const row of KEYBINDINGS) for (const chord of defaultShortcutsFor(row.command)) owners.set(chord,row.command);
 for (const [command,override] of Object.entries(loadKeybindingOverrides())) if(override.shortcut) owners.set(override.shortcut,command);
 return owners;
}

function validateShortcut(command: string, shortcut: string): string {
    const canonical = canonicalShortcut(shortcut);
    if (!canonical)
        throw new Error("That combination is not a valid shortcut");
    if (command === ACTIVATE_RANGE_COMMAND && !/Digit[1-9]$/.test(canonical)) {
        throw new Error("Mentor: Activate 1–9 needs a number key from 1 to 9");
    }
    return canonical;
}
/** Shared by both save paths so no chord can be claimed twice. */
export function validateKeybindingShortcut(command: string, shortcut: string): string {
    const canonical = validateShortcut(command, shortcut);
    const owner = shortcutOwners().get(canonical);
    if (owner && owner !== command) {
        throw new Error(`Already used by ${owner}`);
    }
    return canonical;
}
let cacheStorage: Storage | null = null;
let cacheRaw: string | null = null;
let cacheValue: KeybindingOverrides = {};
function parseKeybindingOverrides(raw: string | null): KeybindingOverrides {
    const value = JSON.parse(raw ?? "{}");
    if (!value || typeof value !== "object" || Array.isArray(value))
        return {};
    const next: KeybindingOverrides = {};
    for (const [command, entry] of Object.entries(value as Record<string, unknown>)) {
        if (!VALID_COMMANDS.has(command) || !entry || typeof entry !== "object")
            continue;
        const override = entry as {
            disabled?: unknown;
            shortcut?: unknown;
        };
        const disabled = override.disabled === true;
        const shortcut = typeof override.shortcut === "string"
            ? (canonicalShortcut(override.shortcut) ?? undefined)
            : undefined;
        if (shortcut)
            next[command] = { shortcut };
        else if (disabled)
            next[command] = { disabled: true };
    }
    return next;
}
/** Cached per raw value: this runs several times on every keydown. Returns a fresh object. */
export function loadKeybindingOverrides(): KeybindingOverrides {
    try {
        const storage = localStorage;
        const raw = storage.getItem(KEYBINDING_OVERRIDES_KEY);
        if (cacheStorage === storage && cacheRaw === raw)
            return { ...cacheValue };
        const next = parseKeybindingOverrides(raw);
        cacheStorage = storage;
        cacheRaw = raw;
        cacheValue = next;
        return { ...next };
    }
    catch {
        return {};
    }
}
export function saveKeybindingOverride(command: string, override: KeybindingOverride): KeybindingOverrides {
    const next = loadKeybindingOverrides();
    if (override.disabled)
        next[command] = { disabled: true };
    else if (override.shortcut) {
        const shortcut = validateKeybindingShortcut(command, override.shortcut);
        next[command] = { shortcut };
    }
    else
        delete next[command];
    try {
        if (Object.keys(next).length) {
            localStorage.setItem(KEYBINDING_OVERRIDES_KEY, JSON.stringify(next));
        }
        else {
            localStorage.removeItem(KEYBINDING_OVERRIDES_KEY);
        }
    }
    catch {
        throw new Error("Could not save shortcuts");
    }
    if (typeof window !== "undefined") {
        window.dispatchEvent(new CustomEvent(KEYBINDINGS_CHANGE_EVENT));
    }
    return next;
}
export type ShortcutEvent = Pick<KeyboardEvent, "code"> & Pick<KeyboardEvent, "metaKey" | "ctrlKey" | "altKey" | "shiftKey">;
export function shortcutMatches(shortcut: string, event: ShortcutEvent): boolean {
    // Copy the fields: real keyboard events expose modifiers as prototype
    // accessors, so spreading the event would silently drop all of them.
    return (shortcutFromKeyEvent({
        code: event.code,
        metaKey: event.metaKey,
        ctrlKey: event.ctrlKey,
        altKey: event.altKey,
        shiftKey: event.shiftKey,
    }) === shortcut);
}
export function matchCustomKeybinding(event: ShortcutEvent): string | null {
    for (const [command, override] of Object.entries(loadKeybindingOverrides())) {
        if (override.shortcut && shortcutMatches(override.shortcut, event)) {
            return command;
        }
    }
    return null;
}
export function keybindingPressed(command: string, event: ShortcutEvent, defaultMatch: boolean): boolean {
    const override = loadKeybindingOverrides()[command];
    if (override?.disabled)
        return false;
    if (override?.shortcut)
        return shortcutMatches(override.shortcut, event);
    return defaultMatch;
}
export function keybindingShortcutLabel(command: string, fallback: string): string | null {
    const override = loadKeybindingOverrides()[command];
    if (override?.disabled)
        return null;
    return override?.shortcut
        ? shortcutLabel(override.shortcut)
        : fallback;
}
export function keybindingShortcutTokens(command: string, fallback: string): string | null {
    const override = loadKeybindingOverrides()[command];
    if (override?.disabled)
        return null;
    return override?.shortcut
        ? shortcutTokens(override.shortcut)
        : fallback;
}
export function subscribeKeybindings(onStoreChange: () => void) {
    if (typeof window === "undefined")
        return () => { };
    const onStorage = (event: StorageEvent) => {
        if (event.key === KEYBINDING_OVERRIDES_KEY)
            onStoreChange();
    };
    window.addEventListener(KEYBINDINGS_CHANGE_EVENT, onStoreChange);
    window.addEventListener("storage", onStorage);
    return () => {
        window.removeEventListener(KEYBINDINGS_CHANGE_EVENT, onStoreChange);
        window.removeEventListener("storage", onStorage);
    };
}
export function currentKeybindings(): KeybindingRow[] {
    const overrides = loadKeybindingOverrides();
    return KEYBINDINGS.map((row) => {
        const override = overrides[row.command];
        return {
            ...row,
            keys: override?.disabled
                ? "Disabled"
                : override?.shortcut
                    ? shortcutLabel(override.shortcut)
                    : row.keys,
        };
    });
}
export function filterKeybindings(rows: KeybindingRow[], query: string): KeybindingRow[] {
    const needle = query.trim().toLowerCase();
    if (!needle)
        return rows;
    return rows.filter((row) => (row.command.toLowerCase().includes(needle) || t(row.command).toLowerCase().includes(needle)) ||
        row.keys.toLowerCase().includes(needle) ||
        (row.when.toLowerCase().includes(needle) || t(row.when).toLowerCase().includes(needle)));
}
