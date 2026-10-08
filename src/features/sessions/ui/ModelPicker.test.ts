// @vitest-environment happy-dom
import { act, createElement, type CSSProperties, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
vi.mock("../../../integrations/harness/core/availability", () => ({
    getHarnessAvailabilitySnapshot: () => 0,
    hasProbedHarnessAvailability: () => true,
    isHarnessAvailable: () => true,
    probeHarnessAvailability: () => Promise.resolve(),
    subscribeHarnessAvailability: () => () => undefined,
}));
vi.mock("../../../integrations/harness/core/registry", () => ({
    refreshHarnessCatalogs: () => Promise.resolve(),
}));
vi.mock("../../../shared/ui/Popover", () => ({
    Popover: ({ children, role, className, tabIndex, onKeyDown, ...props }: {
        children: ReactNode;
        role?: string;
        className?: string;
        tabIndex?: number;
        onKeyDown?: React.KeyboardEventHandler<HTMLDivElement>;
        minHeight?: number;
        maxHeight?: number;
        style?: CSSProperties;
        anchor?: unknown;
        side?: string;
        "aria-label"?: string;
        "data-model-picker"?: boolean;
    }) => createElement("div", {
        role,
        className,
        tabIndex,
        onKeyDown,
        style: props.style,
        "data-min-height": props.minHeight,
        "data-max-height": props.maxHeight,
        "data-anchor-element": props.anchor instanceof HTMLElement ||
            (typeof props.anchor === "object" &&
                props.anchor != null &&
                "current" in props.anchor &&
                props.anchor.current instanceof HTMLElement)
            ? "true"
            : "false",
        "data-side": props.side,
        "aria-label": props["aria-label"],
        "data-model-picker": props["data-model-picker"] ? "" : undefined,
    }, children),
}));
import { ModelControlPills, ModelPicker } from "./ModelPicker";
import { resetHarnessModelOverlays, saveRecentModelChoice, setHarnessModels, modelsFor, } from "../model/models";
import type { ModelSetting } from "../model/models";
let container: HTMLDivElement;
let root: Root;

describe("fast mode indicator", () => {
    const cases = [
        { harness: "codex" as const, id: "serviceTier", kind: "select" as const, enabled: "priority", disabled: "default" },
        { harness: "codex" as const, id: "serviceTier", kind: "select" as const, enabled: "fast", disabled: "default" },
        { harness: "claude" as const, id: "fast", kind: "toggle" as const, enabled: "true", disabled: "false" },
        { harness: "omp" as const, id: "fast", kind: "toggle" as const, enabled: "true", disabled: "false" },
    ];
    it.each(cases)("follows $harness $id=$enabled when toggled, defaulted, or unsupported", ({ harness, id, kind, enabled, disabled }) => {
        const model = `${harness}:fast-indicator`;
        const plainModel = `${harness}:plain-model`;
        const setting: ModelSetting = { id, kind, label: "Fast", value: disabled,
            options: [{ value: enabled, label: "On" }, { value: disabled, label: "Off" }] };
        const catalog = (value = disabled) => act(() => setHarnessModels(harness, [
            { id: model, harness, name: "Fast indicator", nativeId: "fast-indicator", settings: [{ ...setting, value }] },
            { id: plainModel, harness, name: "Plain model", nativeId: "plain-model" },
        ]));
        const render = (values: Record<string, string>, selected = model) => act(() => root.render(createElement(ModelPicker, {
            harness, model: selected, values, hideSettings: true, onChange: vi.fn(), onSettingsChange: vi.fn(),
        })));
        const lightning = () => container.querySelector('button[aria-haspopup] svg.text-accent');
        catalog();
        render({ [id]: enabled });
        expect(lightning()).not.toBeNull();
        expect(container.querySelector('button[aria-haspopup]')?.getAttribute("aria-label")).toContain("fast mode");
        render({ [id]: disabled });
        expect(lightning()).toBeNull();
        catalog(enabled);
        render({});
        expect(lightning()).not.toBeNull();
        render({ [id]: disabled });
        expect(lightning()).toBeNull();
        render({ [id]: enabled }, plainModel);
        expect(lightning()).toBeNull();
    });
});
beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    localStorage.clear();
    resetHarnessModelOverlays();
    setHarnessModels("codex", [{id:"codex:test-model",harness:"codex",name:"Test Model",nativeId:"test-model",settings:[{id:"effort",label:"Effort",kind:"select",value:"high",options:[{value:"xhigh",label:"Extra High"},{value:"high",label:"High"},{value:"low",label:"Low"}]}]},{id:"codex:other-model",harness:"codex",name:"Other model",nativeId:"other-model"}]);
    setHarnessModels("claude",[...modelsFor("claude"),{id:"claude:second-model",harness:"claude",name:"Second Model",nativeId:"second-model"}]);
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
});
afterEach(() => {
    act(() => root.unmount());
    resetHarnessModelOverlays();
    container.remove();
    vi.unstubAllGlobals();
});
function hover(element: Element) {
    act(() => {
        element.dispatchEvent(new MouseEvent("mouseover", { bubbles: true }));
    });
}
function contextMenu(element: Element) {
    act(() => {
        element.dispatchEvent(new MouseEvent("contextmenu", {
            bubbles: true,
            cancelable: true,
            clientX: 120,
            clientY: 80,
        }));
    });
}
function keyDown(target: EventTarget, key: string) {
    act(() => {
        target.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
    });
}
function inputText(input: HTMLInputElement, value: string) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    act(() => {
        setter.call(input, value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
    });
}
describe("model picker", () => {
    it("shows the model name and effort in the combined picker", () => {
        const onChange = vi.fn();
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness: "codex",
            model: "codex:test-model",
            values: { effort: "high" },
            onChange,
            onSettingsChange,
        })));
        const trigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        expect(trigger.textContent).toBe("Test ModelHigh");
        expect(trigger.getAttribute("aria-label")).toBe("Codex Test Model, effort High");
        expect(trigger.querySelector(".text-content\\/50")?.textContent).toBe("High");
        expect(trigger.querySelector("svg")).not.toBeNull();
        act(() => trigger.click());
        const modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"))!;
        expect(modelRow.textContent).toContain("Test Model");
        expect(modelRow.querySelectorAll("svg, img")).toHaveLength(2);
        hover(modelRow);
        const modelFlyout = container.querySelector<HTMLElement>('[role="dialog"][aria-label="Models"]')!;
        expect(modelFlyout.style.height).toBe("404px");
        expect(modelFlyout.dataset.minHeight).toBe("406");
        expect(modelFlyout.dataset.maxHeight).toBe("406");
        expect(container.querySelector('[role="tablist"][aria-orientation="vertical"]')).not.toBeNull();
        expect(container.querySelector('[role="tab"][aria-label="Favorites"]')).not.toBeNull();
        const providerTab = container.querySelector<HTMLButtonElement>('[role="tab"][aria-label="Codex"]')!;
        expect(providerTab.className).toContain("rounded-md");
        expect(providerTab.className).not.toContain("transition");
        hover(providerTab);
        expect(providerTab.getAttribute("aria-selected")).toBe("true");
        expect([...container.querySelectorAll('[role="option"]')].some((option) => option.textContent === "Test Model")).toBe(true);
        const selectedOption = container.querySelector<HTMLButtonElement>('[role="option"][aria-selected="true"]')!;
        const selectedRow = selectedOption.parentElement!;
        const favoriteButton = selectedRow.querySelector<HTMLButtonElement>('button[aria-label="Add to favorites"]')!;
        expect(favoriteButton.className).toContain("opacity-0");
        expect(favoriteButton.className).toContain("group-hover:opacity-100");
        expect(selectedRow.lastElementChild?.querySelector("svg")).not.toBeNull();
        const unselectedOption = container.querySelector<HTMLButtonElement>('[role="option"][aria-selected="false"]')!;
        const unselectedRow = unselectedOption.parentElement!;
        expect(unselectedRow.lastElementChild?.getAttribute("aria-label")).toBe("Add to favorites");
        expect(container.querySelector('input[aria-label="Search models"]')).not.toBeNull();
        const effortRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Effort"))!;
        hover(effortRow);
        const extraHigh = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent === "Extra High")!;
        act(() => extraHigh.click());
        expect(onSettingsChange).toHaveBeenCalledWith({ effort: "xhigh" });
        expect(onChange).not.toHaveBeenCalled();
    });
    it("lists Claude Opus 5.5 after Opus 5 in the built-in Claude catalog", () => {
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:opus-5-5",
            values: {},
            onChange: vi.fn(),
            onSettingsChange: vi.fn(),
        })));
        const trigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        expect(trigger.textContent).toContain("Claude Opus 5.5");
        act(() => trigger.click());
        const modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"));
        if (modelRow)
            hover(modelRow);
        const options = [...container.querySelectorAll('[role="option"]')].map((option) => option.textContent);
        expect(options).toContain("Claude Opus 5.5");
        expect(options.indexOf("Claude Opus 5.5")).toBe(options.indexOf("Claude Opus 5") + 1);
    });
    it("names the source of same-name favorites from different providers", () => {
        setHarnessModels("claude", [
            {
                id: "claude:auto",
                harness: "claude",
                name: "Auto",
                nativeId: "auto",
            },
            {
                id: "claude:muse-spark-1.3",
                harness: "claude",
                name: "Muse Spark 1.3",
                nativeId: "muse-spark-1.3",
            },
        ]);
        setHarnessModels("codex", [
            {
                id: "codex:muse-spark-1.3",
                harness: "codex",
                name: "Muse Spark 1.3",
                nativeId: "opencode-go/muse-spark-1.3",
                provider: { id: "codex", name: "Codex" },
            },
        ]);
        localStorage.setItem("loci.favoriteModels", JSON.stringify([
            "claude:auto",
            "claude:muse-spark-1.3",
            "codex:muse-spark-1.3",
        ]));
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:auto",
            values: {},
            onChange: vi.fn(),
            onSettingsChange: vi.fn(),
        })));
        const trigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        act(() => trigger.click());
        const modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"))!;
        hover(modelRow);
        const favoritesTab = container.querySelector<HTMLButtonElement>('[role="tab"][aria-label="Favorites"]')!;
        act(() => favoritesTab.click());
        const options = [...container.querySelectorAll('[role="option"]')].map((option) => option.getAttribute("aria-label"));
        expect(options).toEqual([
            "Auto, Claude Code",
            "Muse Spark 1.3, Claude Code",
            "Muse Spark 1.3, Codex",
        ]);
    });
    it("can move effort into a dedicated composer control", () => {
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement("div", null, createElement(ModelPicker, {
            harness: "codex",
            model: "codex:test-model",
            values: { effort: "high" },
            hideSettings: true,
            onChange: vi.fn(),
            onSettingsChange,
        }), createElement(ModelControlPills, {
            harness: "codex",
            model: "codex:test-model",
            values: { effort: "high" },
            onSettingsChange,
        }))));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-label="Codex Test Model"]')!;
        expect(modelTrigger.textContent).toBe("Test Model");
        act(() => modelTrigger.click());
        expect([...container.querySelectorAll<HTMLButtonElement>("button")].some((button) => button.textContent?.startsWith("Effort"))).toBe(false);
        const effortTrigger = container.querySelector<HTMLButtonElement>('button[aria-label="Effort: High"]')!;
        expect(effortTrigger.textContent).toBe("High");
        expect(effortTrigger.querySelector("svg")).not.toBeNull();
        act(() => effortTrigger.click());
        const effortMenu = container.querySelector<HTMLElement>('[role="menu"][aria-label="Effort"]')!;
        expect(effortMenu).not.toBeNull();
        keyDown(effortMenu, "ArrowUp");
        keyDown(effortMenu, "Enter");
        expect(onSettingsChange).toHaveBeenCalledWith({ effort: "xhigh" });
    });
    it("opens the model list with no intermediate menu when settings live beside the picker", () => {
        setHarnessModels("claude", [
            {
                id: "claude:second-model",
                harness: "claude",
                name: "Second Model",
                nativeId: "composer-2.5",
                settings: [
                    {
                        id: "fast",
                        label: "Fast",
                        kind: "toggle",
                        value: "false",
                        options: [
                            { value: "false", label: "Off" },
                            { value: "true", label: "On" },
                        ],
                    },
                ],
            },
        ]);
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement("div", null, createElement(ModelPicker, {
            harness: "claude",
            model: "claude:second-model",
            values: { fast: "false" },
            hideSettings: true,
            onChange: vi.fn(),
            onSettingsChange,
        }), createElement(ModelControlPills, {
            harness: "claude",
            model: "claude:second-model",
            values: { fast: "false" },
            onSettingsChange,
        }))));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')!;
        act(() => modelTrigger.click());
        expect(container.querySelector('[role="menu"]')).toBeNull();
        expect(container.querySelector('[role="dialog"][aria-label="Models"]')).not.toBeNull();
        const fastPill = container.querySelector<HTMLButtonElement>('button[aria-label="Fast: Off"]')!;
        expect(fastPill.getAttribute("aria-pressed")).toBe("false");
        act(() => fastPill.click());
        expect(onSettingsChange).toHaveBeenCalledWith({ fast: "true" });
    });
    it("focuses the model search when the models submenu opens", async () => {
        setHarnessModels("claude", [
            {
                id: "claude:second-model",
                harness: "claude",
                name: "Second Model",
                nativeId: "composer-2.5",
                settings: [],
            },
        ]);
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:second-model",
            values: {},
            onChange: vi.fn(),
            onSettingsChange: vi.fn(),
        })));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        act(() => modelTrigger.click());
        const modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"))!;
        hover(modelRow);
        // Focus is deferred one frame so the popover is on screen first.
        await act(() => new Promise((resolve) => requestAnimationFrame(resolve)));
        const search = container.querySelector<HTMLInputElement>('input[aria-label="Search models"]')!;
        expect(document.activeElement).toBe(search);
    });
    it("shows a speed icon on the service-tier pill", () => {
        setHarnessModels("codex", [
            {
                id: "codex:gpt-5.6-luna",
                harness: "codex",
                name: "GPT-5.6 Luna",
                nativeId: "gpt-5.6-luna",
                settings: [
                    {
                        id: "serviceTier",
                        label: "Service Tier",
                        kind: "select",
                        value: "default",
                        options: [
                            { value: "default", label: "Standard" },
                            { value: "fast", label: "Fast" },
                        ],
                    },
                ],
            },
        ]);
        act(() => root.render(createElement(ModelControlPills, {
            harness: "codex",
            model: "codex:gpt-5.6-luna",
            values: { serviceTier: "default" },
            onSettingsChange: vi.fn(),
        })));
        const serviceTierPill = container.querySelector<HTMLButtonElement>('button[aria-label="Service Tier: Standard"]')!;
        expect(serviceTierPill.textContent).toBe("Standard");
        expect(serviceTierPill.querySelectorAll("svg")).toHaveLength(2);
    });
    it.each([
        ["codex", "reasoningEffort", "Reasoning"],
        ["opencode", "variant", "Variant"],
        ["claude", "effort", "Effort"],
        ["cursor", "effort", "Effort"],
    ] as const)("shimmers max and ultra effort options for %s", (harness, settingId, settingLabel) => {
        setHarnessModels(harness, [
            {
                id: `${harness}:test-model`,
                harness,
                name: "GPT-5.6",
                nativeId: "gpt-5.6",
                settings: [
                    {
                        id: settingId,
                        label: settingLabel,
                        kind: "select",
                        value: "high",
                        options: [
                            { value: "low", label: "Low" },
                            { value: "high", label: "High" },
                            { value: "max", label: "Max" },
                            { value: "ultra", label: "Ultra" },
                        ],
                    },
                ],
            },
        ]);
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness,
            model: `${harness}:test-model`,
            values: { [settingId]: "high" },
            onChange: vi.fn(),
            onSettingsChange,
        })));
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')
            ?.click());
        const effortRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith(settingLabel))!;
        hover(effortRow);
        expect(container.querySelectorAll('[data-effort-tone="max"]')).toHaveLength(1);
        expect(container.querySelectorAll('[data-effort-tone="ultra"]')).toHaveLength(1);
        expect(container.querySelector('[data-effort-tone="max"] .codex-effort-tile')).not.toBeNull();
        expect(container.querySelectorAll('[data-effort-tone="max"] .codex-effort-tile')).toHaveLength(160);
        const filledTiles = container.querySelectorAll('[data-effort-tone="max"] .codex-effort-tile--filled');
        expect(filledTiles.length).toBeGreaterThanOrEqual(96);
        expect(filledTiles.length).toBeLessThanOrEqual(112);
        const high = [
            ...container.querySelectorAll<HTMLButtonElement>('[role="menuitemradio"]'),
        ].find((button) => button.textContent === "High")!;
        expect(high.classList.contains("codex-effort-option")).toBe(false);
        expect(high.classList.contains("bg-selection")).toBe(true);
        const mainMenu = container.querySelector<HTMLElement>('[role="menu"][aria-label="Model and settings"]')!;
        act(() => mainMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
        const max = container.querySelector<HTMLButtonElement>('[data-effort-tone="max"]')!;
        expect(max.classList.contains("bg-selection")).toBe(true);
        expect(high.classList.contains("bg-selection")).toBe(false);
        act(() => mainMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })));
        expect(onSettingsChange).toHaveBeenCalledWith({ [settingId]: "max" });

        // The beside-composer control uses a separate popover path.
        act(() => root.render(createElement(ModelControlPills, {
            harness,
            model: `${harness}:test-model`,
            values: { [settingId]: "high" },
            onSettingsChange,
        })));
        act(() => container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!.click());
        const pillMenu = container.querySelector<HTMLElement>('[role="menu"]')!;
        const pillMax = pillMenu.querySelector<HTMLElement>('[data-effort-tone="max"]')!;
        const pillUltra = pillMenu.querySelector<HTMLElement>('[data-effort-tone="ultra"]')!;
        expect(pillMax.querySelectorAll(".codex-effort-tile")).toHaveLength(160);
        expect(pillUltra.querySelectorAll(".codex-effort-tile")).toHaveLength(160);
        act(() => pillMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
        expect(pillMax.classList.contains("bg-selection")).toBe(true);
        act(() => pillMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })));
        expect(pillUltra.classList.contains("bg-selection")).toBe(true);
        expect(pillMax.classList.contains("bg-selection")).toBe(false);
        act(() => pillMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true })));
        expect(onSettingsChange).toHaveBeenLastCalledWith({ [settingId]: "ultra" });
    });
    it("groups the service tier inside the effort popover", () => {
        setHarnessModels("codex", [
            {
                id: "codex:gpt-5.6-sol",
                harness: "codex",
                name: "GPT-5.6 Sol",
                nativeId: "gpt-5.6-sol",
                settings: [
                    {
                        id: "reasoningEffort",
                        label: "Reasoning",
                        kind: "select",
                        value: "high",
                        options: [
                            { value: "high", label: "High" },
                            { value: "xhigh", label: "Extra High" },
                        ],
                    },
                    {
                        id: "serviceTier",
                        label: "Service Tier",
                        kind: "select",
                        value: "default",
                        options: [
                            { value: "default", label: "Standard" },
                            { value: "fast", label: "Fast" },
                        ],
                    },
                ],
            },
        ]);
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement(ModelControlPills, {
            harness: "codex",
            model: "codex:gpt-5.6-sol",
            values: { reasoningEffort: "high", serviceTier: "default" },
            onSettingsChange,
        })));
        expect(container.querySelector('button[aria-label="Service Tier: Standard"]')).toBeNull();
        const effortPill = container.querySelector<HTMLButtonElement>('button[aria-label="Reasoning: High"]')!;
        act(() => effortPill.click());
        const menu = container.querySelector<HTMLElement>('[role="menu"][aria-label="Reasoning and Service Tier"]')!;
        expect(menu.querySelector('[role="separator"]')).not.toBeNull();
        expect(menu.querySelector('[role="group"][aria-label="Reasoning"]')).not.toBeNull();
        const serviceTierGroup = menu.querySelector<HTMLElement>('[role="group"][aria-label="Service Tier"]')!;
        expect(serviceTierGroup.textContent).toContain("Standard");
        expect(serviceTierGroup.textContent).toContain("Fast");
        const fast = [...serviceTierGroup.querySelectorAll("button")].find((button) => button.textContent === "Fast")!;
        act(() => fast.click());
        expect(onSettingsChange).toHaveBeenCalledWith({
            reasoningEffort: "high",
            serviceTier: "fast",
        });
    });
    it("groups fast mode inside the effort popover", () => {
        setHarnessModels("claude", [
            {
                id: "claude:opus-5",
                harness: "claude",
                name: "Opus 5",
                nativeId: "claude-opus-5",
                settings: [
                    {
                        id: "effort",
                        label: "Reasoning",
                        kind: "select",
                        value: "high",
                        options: [
                            { value: "medium", label: "Medium" },
                            { value: "high", label: "High" },
                        ],
                    },
                    {
                        id: "fast",
                        label: "Fast",
                        kind: "toggle",
                        value: "false",
                        options: [
                            { value: "false", label: "Off" },
                            { value: "true", label: "On" },
                        ],
                    },
                ],
            },
        ]);
        const onSettingsChange = vi.fn();
        act(() => root.render(createElement(ModelControlPills, {
            harness: "claude",
            model: "claude:opus-5",
            values: { effort: "high", fast: "false" },
            onSettingsChange,
        })));
        expect(container.querySelector('button[aria-label="Fast: Off"]')).toBeNull();
        const effortPill = container.querySelector<HTMLButtonElement>('button[aria-label="Effort: High"]')!;
        act(() => effortPill.click());
        const menu = container.querySelector<HTMLElement>('[role="menu"][aria-label="Effort and Fast"]')!;
        const fastGroup = menu.querySelector<HTMLElement>('[role="group"][aria-label="Fast"]')!;
        expect(fastGroup.textContent).toContain("Off");
        expect(fastGroup.textContent).toContain("On");
        const on = [...fastGroup.querySelectorAll("button")].find((button) => button.textContent === "On")!;
        act(() => on.click());
        expect(onSettingsChange).toHaveBeenCalledWith({
            effort: "high",
            fast: "true",
        });
    });
    it("opens the model list directly when settings live beside the picker", async () => {
        setHarnessModels("claude", [
            {
                id: "claude:second-model",
                harness: "claude",
                name: "Second Model",
                nativeId: "composer-2.5",
                settings: [
                    {
                        id: "fast",
                        label: "Fast",
                        kind: "toggle",
                        value: "false",
                        options: [
                            { value: "false", label: "Off" },
                            { value: "true", label: "On" },
                        ],
                    },
                ],
            },
        ]);
        const onChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:second-model",
            values: { fast: "false" },
            hideSettings: true,
            onChange,
            onSettingsChange: vi.fn(),
        })));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')!;
        act(() => modelTrigger.click());
        expect(container.querySelector('[role="menu"]')).toBeNull();
        const flyout = container.querySelector<HTMLElement>('[role="dialog"][aria-label="Models"]')!;
        expect(flyout).not.toBeNull();
        expect(flyout.textContent).toContain("Second Model");
        // Search takes focus once the flyout is on screen.
        await act(() => new Promise((resolve) => requestAnimationFrame(resolve)));
        expect(document.activeElement).toBe(flyout.querySelector('input[aria-label="Search models"]'));
        const selected = flyout.querySelector<HTMLButtonElement>('[role="option"][aria-selected="true"]')!;
        act(() => selected.click());
        expect(onChange).toHaveBeenCalledWith("claude", "claude:second-model");
    });
    it("picks the highlighted model on Enter even when focus sits on another row", () => {
        setHarnessModels("claude", [
            {
                id: "claude:first",
                harness: "claude",
                name: "First",
                nativeId: "first",
            },
            {
                id: "claude:second",
                harness: "claude",
                name: "Second",
                nativeId: "second",
            },
        ]);
        const onChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:first",
            values: {},
            hideSettings: true,
            onChange,
            onSettingsChange: vi.fn(),
        })));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')!;
        act(() => modelTrigger.click());
        const options = [
            ...container.querySelectorAll<HTMLButtonElement>('[role="option"]'),
        ];
        expect(options).toHaveLength(2);
        // Focus stays on the first row while arrows move the highlight.
        options[0].focus();
        keyDown(options[0], "ArrowDown");
        keyDown(options[0], "Enter");
        expect(onChange).toHaveBeenCalledTimes(1);
        expect(onChange).toHaveBeenCalledWith("claude", "claude:second");
    });
    it("leaves favorite toggles to native activation on Enter", () => {
        setHarnessModels("claude", [
            {
                id: "claude:first",
                harness: "claude",
                name: "First",
                nativeId: "first",
            },
            {
                id: "claude:second",
                harness: "claude",
                name: "Second",
                nativeId: "second",
            },
        ]);
        const onChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness: "claude",
            model: "claude:first",
            values: {},
            hideSettings: true,
            onChange,
            onSettingsChange: vi.fn(),
        })));
        const modelTrigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="dialog"]')!;
        act(() => modelTrigger.click());
        const star = container.querySelector<HTMLButtonElement>('button[aria-label="Add to favorites"]')!;
        star.focus();
        keyDown(star, "Enter");
        // No model pick hijacks the favorite toggle (native click owns it).
        expect(onChange).not.toHaveBeenCalled();
    });
    it("returns to the selected model's harness when reopened", () => {
        act(() => root.render(createElement(ModelPicker, {
            harness: "codex",
            model: "codex:test-model",
            values: { effort: "high" },
            onChange: vi.fn(),
            onSettingsChange: vi.fn(),
        })));
        const trigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        act(() => trigger.click());
        let modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"))!;
        hover(modelRow);
        const otherProviderTab = container.querySelector<HTMLButtonElement>('[role="tab"][aria-label="Claude Code"]')!;
        hover(otherProviderTab);
        expect(otherProviderTab.getAttribute("aria-selected")).toBe("true");
        act(() => trigger.click());
        act(() => trigger.click());
        modelRow = [
            ...container.querySelectorAll<HTMLButtonElement>("button"),
        ].find((button) => button.textContent?.startsWith("Model"))!;
        hover(modelRow);
        expect(container
            .querySelector('[role="tab"][aria-label="Codex"]')
            ?.getAttribute("aria-selected")).toBe("true");
    });
    it("quick-switches between recently used models on right-click", () => {
        saveRecentModelChoice("claude", "claude:opus-5");
        saveRecentModelChoice("claude", "claude:second-model");
        const onChange = vi.fn();
        act(() => root.render(createElement(ModelPicker, {
            harness: "codex",
            model: "codex:test-model",
            values: { effort: "high" },
            hotkeys: true,
            onChange,
            onSettingsChange: vi.fn(),
        })));
        const trigger = container.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')!;
        contextMenu(trigger);
        const recentMenu = container.querySelector<HTMLElement>('[role="menu"][aria-label="Recently used models"]')!;
        expect(recentMenu.dataset.anchorElement).toBe("true");
        expect(recentMenu.dataset.side).toBe("top");
        const recentItems = [
            ...recentMenu.querySelectorAll<HTMLButtonElement>('[role="menuitemradio"]'),
        ];
        expect(recentItems).toHaveLength(3);
        const currentModel = recentItems.find((item) => item.textContent?.includes("Test Model"))!;
        const claudeModel = recentItems.find((item) => item.textContent?.includes("Opus 5"))!;
        const secondModel = recentItems.find((item) => item.textContent?.includes("Second Model"))!;
        expect(secondModel.textContent).toContain("Claude Code");
        expect(secondModel.querySelector("svg, img")).not.toBeNull();
        // The composer can retain focus after opening its toolbar menu. Recent
        // model navigation still needs to own these keys in that state.
        trigger.focus();
        expect(currentModel.className).toContain("bg-selection");
        keyDown(trigger, "ArrowUp");
        expect(claudeModel.className).toContain("bg-selection");
        keyDown(trigger, "ArrowDown");
        expect(currentModel.className).toContain("bg-selection");
        keyDown(trigger, "ArrowDown");
        expect(secondModel.className).toContain("bg-selection");
        keyDown(trigger, "Enter");
        expect(onChange).toHaveBeenCalledWith("claude", "claude:second-model");
        expect(container.querySelector('[role="menu"][aria-label="Recently used models"]')).toBeNull();
        act(() => {
            window.dispatchEvent(new KeyboardEvent("keydown", {
                key: ".",
                code: "Period",
                metaKey: true,
                bubbles: true,
            }));
        });
        expect(container.querySelector('[role="menu"][aria-label="Recently used models"]')).not.toBeNull();
        expect(container.querySelector('[role="menu"][aria-label="Model and settings"]')).toBeNull();
    });
});
