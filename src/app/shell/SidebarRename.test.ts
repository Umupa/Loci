// @vitest-environment happy-dom
import { act, createElement, StrictMode, type ComponentProps } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { formatSessionTitle } from "../../features/sessions/model/session";
import { formatReminderTime } from "../../features/sessions/model/sessionReminders";
import { Sidebar } from "./Sidebar";
import { loadSessionFolders } from "../../features/sessions/model/sessionFolders";
import { copyText } from "../../platform/tauri/clipboard";
vi.mock("../../platform/tauri/clipboard", () => ({
    copyText: vi.fn().mockResolvedValue(undefined),
}));
let container: HTMLDivElement;
let root: Root;
let props: ComponentProps<typeof Sidebar>;
function render() {
    root.render(createElement(Sidebar, props));
}
function card(): HTMLElement {
    return container.querySelector('[data-session-card="session-1"]')!;
}
function renameInput(): HTMLInputElement {
    return container.querySelector("input:not([placeholder])")!;
}
function projectSearchInput(): HTMLInputElement | null {
    return document.querySelector('input[placeholder="Search projects..."]');
}
function pressKey(target: HTMLElement, key: string) {
    const event = new KeyboardEvent("keydown", {
        key,
        bubbles: true,
        cancelable: true,
    });
    act(() => target.dispatchEvent(event));
    return event;
}
function typeTitle(input: HTMLInputElement, title: string) {
    // Use the native setter so React sees a user change, not its own value write.
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    act(() => {
        setter.call(input, title);
        input.dispatchEvent(new Event("input", { bubbles: true }));
    });
}
function startRename() {
    act(() => {
        card().dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
    });
    const rename = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent?.startsWith("Rename"))!;
    expect(rename.disabled).toBe(false);
    act(() => rename.click());
    return renameInput();
}
beforeEach(() => {
    vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
    vi.mocked(copyText).mockReset().mockResolvedValue(undefined);
    const stored = new Map<string, string>();
    vi.stubGlobal("localStorage", {
        getItem: (key: string) => stored.get(key) ?? null,
        setItem: (key: string, value: string) => stored.set(key, value),
        removeItem: (key: string) => stored.delete(key),
        clear: () => stored.clear(),
    });
    props = {
        cwd: "/workspace/project",
        open: true,
        sessions: [
            {
                id: "session-1",
                cwd: "/workspace/project",
                harness: "codex",
                model: "",
                runtimeMode: "supervised",
                title: formatSessionTitle("codex", "Original conversation"),
                createdAt: Date.now(),
                updatedAt: Date.now(),
            },
        ],
        busySessionIds: new Set(["session-1"]),
        approvalSessionIds: new Set(),
        activeSessionId: "session-1",
        status: "idle",
        pending: false,
        onSelectSession: vi.fn(),
        onRenameSession: vi.fn((id: string, title: string) => {
            props = {
                ...props,
                sessions: props.sessions.map((session) => session.id === id
                    ? { ...session, title: formatSessionTitle(session.harness, title) }
                    : session),
            };
            render();
        }),
        onTabChange: vi.fn(),
    };
    container = document.createElement("div");
    document.body.append(container);
    root = createRoot(container);
});
afterEach(() => {
    act(() => root.unmount());
    container.remove();
    localStorage.clear();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
});
describe("project rail visibility", () => {
    it("keeps the mounted rail and its scroll state when collapsed", async () => {
        props = {
            ...props,
            recents: [{ path: "/workspace/project", openedAt: Date.now() }],
            projectRailOpen: true,
            compactProjectRail: false,
            onSelectProject: vi.fn(),
            onOpenProject: vi.fn(),
        };
        await act(async () => render());
        const rail = container.querySelector<HTMLElement>('nav[aria-label="Projects"]');
        expect(rail).not.toBeNull();
        rail!.scrollTop = 37;
        props = { ...props, projectRailOpen: false };
        await act(async () => render());
        expect(rail?.classList.contains("hidden")).toBe(true);
        props = { ...props, projectRailOpen: true };
        await act(async () => render());
        expect(container.querySelector('nav[aria-label="Projects"]')).toBe(rail);
        expect(rail?.scrollTop).toBe(37);
    });
});
describe("sidebar session multiselection", () => {
    it.each(["ctrlKey", "metaKey"] as const)("resets the %s anchor after acting on another session's context menu", (modifier) => {
        props.sessions = [1, 2, 3, 4].map((n) => ({
            ...props.sessions[0],
            id: `session-${n}`,
            updatedAt: 100 - n,
        }));
        props.onPinSession = vi.fn();
        act(() => render());
        act(() => container
            .querySelector('[data-session-card="session-3"]')!
            .dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            [modifier]: true,
        })));
        act(() => container
            .querySelector('[data-session-card="session-2"]')!
            .dispatchEvent(new MouseEvent("contextmenu", {
            bubbles: true,
            cancelable: true,
        })));
        const pin = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Pin")!;
        act(() => pin.click());
        expect(props.onPinSession).toHaveBeenCalledWith("session-2", true);
        expect(container.querySelectorAll('[data-session-selected="true"]')).toHaveLength(0);
        act(() => container
            .querySelector('[data-session-card="session-4"]')!
            .dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            shiftKey: true,
        })));
        expect(Array.from(container.querySelectorAll('[data-session-selected="true"]'), (el) => el.getAttribute("data-session-card"))).toEqual(["session-1", "session-2", "session-3", "session-4"]);
        expect(props.onSelectSession).not.toHaveBeenCalled();
    });
    it("starts a range at the active session when pagination hides the anchor", () => {
        props.sessions = Array.from({ length: 80 }, (_, index) => ({
            ...props.sessions[0],
            id: `session-${index + 1}`,
            updatedAt: 100 - index,
        }));
        props.activeSessionId = "session-80";
        act(() => render());
        act(() => container
            .querySelector<HTMLElement>('[data-session-card="session-40"]')!
            .click());
        // Switching panes does not discard the last plain-click anchor.
        props.activeSessionId = "session-1";
        act(() => render());
        const search = container.querySelector<HTMLInputElement>('input[placeholder="Search conversations..."]')!;
        // All sessions still match, but the list returns to its first page.
        typeTitle(search, "Original conversation");
        expect(container.querySelector('[data-session-card="session-40"]')).toBeNull();
        expect(container.querySelectorAll("[data-session-card]")).toHaveLength(32);
        act(() => container.querySelector('[data-session-card="session-3"]')!.dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            shiftKey: true,
        })));
        expect(Array.from(container.querySelectorAll('[data-session-selected="true"]'), (el) => el.getAttribute("data-session-card"))).toEqual(["session-1", "session-2", "session-3"]);
        expect(props.onSelectSession).toHaveBeenCalledTimes(1);
        expect(props.onSelectSession).toHaveBeenCalledWith("session-40");
    });
    it.each(["ctrlKey", "metaKey"] as const)("starts the next range at the active session after %s clears the last selection", (modifier) => {
        props.sessions = [1, 2, 3, 4].map((n) => ({
            ...props.sessions[0],
            id: `session-${n}`,
            updatedAt: 100 - n,
        }));
        act(() => render());
        const thirdCard = container.querySelector<HTMLElement>('[data-session-card="session-3"]')!;
        for (let click = 0; click < 2; click++) {
            act(() => thirdCard.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                [modifier]: true,
            })));
            expect(container.querySelectorAll('[data-session-selected="true"]')).toHaveLength(click === 0 ? 1 : 0);
        }
        act(() => container
            .querySelector('[data-session-card="session-4"]')!
            .dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            shiftKey: true,
        })));
        expect(Array.from(container.querySelectorAll('[data-session-selected="true"]'), (el) => el.getAttribute("data-session-card"))).toEqual(["session-1", "session-2", "session-3", "session-4"]);
        expect(props.onSelectSession).not.toHaveBeenCalled();
    });
    it("clears the previous session focus when Ctrl-clicking another session", () => {
        props.sessions = [1, 2].map((n) => ({
            ...props.sessions[0],
            id: `session-${n}`,
            updatedAt: 100 - n,
        }));
        props.onDeleteSession = vi.fn();
        act(() => render());
        const firstTitle = card().querySelector<HTMLElement>("[data-session-select]")!;
        const secondTitle = container.querySelector<HTMLElement>('[data-session-select="session-2"]')!;
        act(() => firstTitle.focus());
        act(() => {
            secondTitle.dispatchEvent(new MouseEvent("mousedown", {
                bubbles: true,
                cancelable: true,
                button: 0,
                ctrlKey: true,
            }));
            secondTitle.dispatchEvent(new MouseEvent("click", {
                bubbles: true,
                ctrlKey: true,
            }));
        });
        expect(card().getAttribute("data-session-selected")).toBeNull();
        expect(secondTitle
            .closest("[data-session-card]")!
            .getAttribute("data-session-selected")).toBe("true");
        expect(props.onSelectSession).not.toHaveBeenCalled();
        pressKey(document.activeElement as HTMLElement, "Delete");
        expect(props.onDeleteSession).not.toHaveBeenCalled();
        pressKey(document.activeElement as HTMLElement, "F2");
        expect(renameInput()).toBeNull();
        expect(document.activeElement).not.toBe(firstTitle);
        expect(document.activeElement).not.toBe(secondTitle);
    });
    it("keeps Shift-click selection free of title focus while preserving keyboard focus", () => {
        act(() => render());
        const title = card().querySelector<HTMLElement>("[data-session-select]")!;
        act(() => title.focus());
        expect(document.activeElement).toBe(title);
        const mouseDown = new MouseEvent("mousedown", {
            bubbles: true,
            cancelable: true,
            shiftKey: true,
            button: 0,
        });
        act(() => title.dispatchEvent(mouseDown));
        expect(mouseDown.defaultPrevented).toBe(true);
        expect(document.activeElement).not.toBe(title);
        act(() => title.dispatchEvent(new MouseEvent("click", {
            bubbles: true,
            shiftKey: true,
        })));
        expect(card().getAttribute("data-session-selected")).toBe("true");
        expect(props.onSelectSession).not.toHaveBeenCalled();
        act(() => title.focus());
        expect(document.activeElement).toBe(title);
        pressKey(title, "Enter");
        expect(props.onSelectSession).toHaveBeenCalledWith("session-1");
    });
    it("selects the visible range from a plain click with Shift-click", () => {
        props.sessions = [1, 2, 3, 4].map((n) => ({
            ...props.sessions[0],
            id: `session-${n}`,
            updatedAt: 100 - n,
        }));
        act(() => render());
        act(() => card().click());
        act(() => container
            .querySelector('[data-session-card="session-3"]')!
            .dispatchEvent(new MouseEvent("click", { bubbles: true, shiftKey: true })));
        expect(Array.from(container.querySelectorAll('[data-session-selected="true"]'), (el) => el.getAttribute("data-session-card"))).toEqual(["session-1", "session-2", "session-3"]);
        expect(props.onSelectSession).toHaveBeenCalledTimes(1);
    });
    it("creates a folder containing the Ctrl-clicked sessions without opening them", () => {
        props.sessions = [1, 2, 3].map((n) => ({
            ...props.sessions[0],
            id: `session-${n}`,
            updatedAt: 100 - n,
        }));
        act(() => render());
        for (const id of ["session-1", "session-3"]) {
            act(() => container
                .querySelector(`[data-session-card="${id}"]`)!
                .dispatchEvent(new MouseEvent("click", { bubbles: true, ctrlKey: true })));
        }
        expect(props.onSelectSession).not.toHaveBeenCalled();
        expect(container.querySelectorAll('[data-session-selected="true"]')).toHaveLength(2);
        act(() => card().dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true })));
        const newFolder = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "New folder")!;
        act(() => newFolder.click());
        expect(loadSessionFolders(props.cwd)[0].sessionIds).toEqual([
            "session-1",
            "session-3",
        ]);
    });
});
describe("sidebar session IDs", () => {
    function openCopyIdMenu(sessionId: string) {
        act(() => {
            container
                .querySelector(`[data-session-card="${sessionId}"]`)!
                .dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
        });
        const trigger = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Copy session ID")!;
        expect(trigger.getAttribute("aria-haspopup")).toBe("menu");
        act(() => trigger.click());
        return document.querySelector<HTMLElement>('[role="menu"][aria-label="Copy session ID"]')!;
    }
    it("copies either ID from the right-clicked session", async () => {
        props.sessions = [
            { ...props.sessions[0], providerSessionId: "harness-session-1" },
            {
                ...props.sessions[0],
                id: "session-2",
                providerSessionId: "harness-session-2",
                updatedAt: props.sessions[0].updatedAt - 1,
            },
        ];
        act(() => render());
        const harnessMenu = openCopyIdMenu("session-2");
        const copyHarnessId = Array.from(harnessMenu.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Harness session ID")!;
        expect(copyHarnessId.disabled).toBe(false);
        await act(async () => copyHarnessId.click());
        expect(copyText).toHaveBeenNthCalledWith(1, "harness-session-2");
        const lociMenu = openCopyIdMenu("session-2");
        const copyLociId = Array.from(lociMenu.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Loci session ID")!;
        expect(copyLociId.disabled).toBe(false);
        await act(async () => copyLociId.click());
        expect(copyText).toHaveBeenNthCalledWith(2, "session-2");
    });
    it("keeps the Loci ID available before the harness supplies an ID", async () => {
        act(() => render());
        const copyMenu = openCopyIdMenu("session-1");
        const copyHarnessId = Array.from(copyMenu.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Harness session ID")!;
        const copyLociId = Array.from(copyMenu.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Loci session ID")!;
        expect(copyHarnessId.disabled).toBe(true);
        expect(copyLociId.disabled).toBe(false);
        await act(async () => copyLociId.click());
        expect(copyText).toHaveBeenCalledExactlyOnceWith("session-1");
    });
});
describe("sidebar session rename", () => {
    it.each(["idle", "working", "needs approval"])("renames from the menu and restores navigation (status=%s)", (status) => {
        if (status === "idle")
            props.busySessionIds = new Set();
        if (status === "needs approval") {
            props.approvalSessionIds = new Set(["session-1"]);
        }
        act(() => render());
        const input = startRename();
        expect(input.disabled).toBe(false);
        expect(document.activeElement === input).toBe(true);
        expect(input.selectionStart).toBe(0);
        expect(input.selectionEnd).toBe(input.value.length);
        typeTitle(input, "  Renamed conversation  ");
        expect(pressKey(input, "Enter").defaultPrevented).toBe(true);
        expect(props.onRenameSession).toHaveBeenCalledExactlyOnceWith("session-1", "Renamed conversation");
        expect(renameInput()).toBeNull();
        expect(card().textContent).toContain("Renamed conversation");
        act(() => card().click());
        expect(props.onSelectSession).toHaveBeenCalledWith("session-1");
    });
    it("allows F2 to rename a working conversation", () => {
        act(() => render());
        pressKey(card().querySelector("[data-session-select]")!, "F2");
        const input = renameInput();
        expect(input.disabled).toBe(false);
        expect(document.activeElement === input).toBe(true);
        typeTitle(input, "Keyboard rename");
        pressKey(input, "Enter");
        expect(props.onRenameSession).toHaveBeenCalledExactlyOnceWith("session-1", "Keyboard rename");
    });
    it("prefetches after a deliberate hover and immediately on press", () => {
        vi.useFakeTimers();
        props.onPrefetchSession = vi.fn();
        act(() => render());
        act(() => {
            card().dispatchEvent(new MouseEvent("pointerover", { bubbles: true }));
            vi.advanceTimersByTime(119);
        });
        expect(props.onPrefetchSession).not.toHaveBeenCalled();
        act(() => vi.advanceTimersByTime(1));
        expect(props.onPrefetchSession).toHaveBeenCalledExactlyOnceWith("session-1");
        act(() => {
            card().dispatchEvent(new MouseEvent("pointerover", { bubbles: true }));
            card().dispatchEvent(new MouseEvent("pointerout", { bubbles: true }));
            vi.advanceTimersByTime(120);
        });
        expect(props.onPrefetchSession).toHaveBeenCalledTimes(1);
        act(() => {
            card().dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, button: 0 }));
        });
        expect(props.onPrefetchSession).toHaveBeenCalledTimes(2);
    });
    it("cancels with Escape while the agent is working", () => {
        act(() => render());
        const input = startRename();
        expect(document.activeElement === input).toBe(true);
        typeTitle(input, "Discard this name");
        expect(pressKey(input, "Escape").defaultPrevented).toBe(true);
        expect(props.onRenameSession).not.toHaveBeenCalled();
        expect(renameInput()).toBeNull();
        expect(card().textContent).toContain("Original conversation");
    });
    it("commits once on blur while the agent is working", () => {
        act(() => render());
        const input = startRename();
        expect(document.activeElement === input).toBe(true);
        typeTitle(input, "  Saved on blur  ");
        act(() => input.blur());
        expect(props.onRenameSession).toHaveBeenCalledExactlyOnceWith("session-1", "Saved on blur");
        expect(renameInput()).toBeNull();
    });
    it("cancels an empty name without trapping the conversation in the editor", () => {
        act(() => render());
        const input = startRename();
        expect(document.activeElement === input).toBe(true);
        typeTitle(input, "   ");
        pressKey(input, "Enter");
        expect(props.onRenameSession).not.toHaveBeenCalled();
        expect(renameInput()).toBeNull();
        expect(card().textContent).toContain("Original conversation");
    });
    it("keeps an in-progress rename editable when a turn starts", () => {
        props.busySessionIds = new Set();
        act(() => render());
        const input = startRename();
        typeTitle(input, "My draft title");
        props = { ...props, busySessionIds: new Set(["session-1"]) };
        act(() => render());
        expect(renameInput()).toBe(input);
        expect(input.disabled).toBe(false);
        expect(document.activeElement === input).toBe(true);
        expect(input.value).toBe("My draft title");
        pressKey(input, "Enter");
        expect(props.onRenameSession).toHaveBeenCalledExactlyOnceWith("session-1", "My draft title");
    });
});
describe("sidebar project picker", () => {
    it("focuses the project search input when opened", async () => {
        // Hold animation frames so the deferred focus retry runs on demand.
        const frames: FrameRequestCallback[] = [];
        vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
            frames.push(callback);
            return frames.length;
        });
        vi.stubGlobal("cancelAnimationFrame", vi.fn());
        props.onSelectProject = vi.fn();
        await act(async () => render());
        const trigger = container.querySelector<HTMLButtonElement>('[aria-label^="Switch project"]')!;
        act(() => trigger.click());
        const input = projectSearchInput();
        expect(input).not.toBeNull();
        expect(document.activeElement).toBe(input);
        // Focus lost before the next frame is restored by the retry.
        act(() => input!.blur());
        expect(document.activeElement).not.toBe(input);
        expect(frames).toHaveLength(1);
        act(() => frames.forEach((frame) => frame(0)));
        expect(document.activeElement).toBe(input);
    });
});
describe("sidebar reorder affordances", () => {
    it("keeps the default cursor on reorderable tabs and folders", () => {
        props.sessions = [
            props.sessions[0],
            {
                ...props.sessions[0],
                id: "session-2",
                title: formatSessionTitle("codex", "Second conversation"),
            },
        ];
        localStorage.setItem("loci.sessionFolders", JSON.stringify({
            "/workspace/project": [
                {
                    id: "folder-1",
                    name: "Folder one",
                    sessionIds: ["session-1"],
                    collapsed: false,
                },
                {
                    id: "folder-2",
                    name: "Folder two",
                    sessionIds: ["session-2"],
                    collapsed: false,
                },
            ],
        }));
        act(() => render());
        const tabs = container.querySelectorAll<HTMLElement>('.workspace-tab');
        expect(Array.from(tabs, (tab) => tab.textContent)).toEqual(["Sessions", "Files", "Canvas"]);
        for (const tab of tabs) {
            expect(tab.className).not.toContain("cursor-grab");
            expect(tab.parentElement?.className).not.toContain("cursor-grab");
        }
        for (const name of ["Folder one", "Folder two"]) {
            expect(container.querySelector<HTMLButtonElement>(`button[title="${name}"]`)!
                .className).not.toContain("cursor-grab");
        }
    });
});
describe("sidebar new session rows", () => {
    it("grows in only for a session that arrives after the list has rendered", () => {
        const animate = vi
            .spyOn(HTMLElement.prototype, "animate")
            .mockImplementation(() => ({ cancel: vi.fn() }) as unknown as Animation);
        const animated = (property: string) => animate.mock.calls.flatMap(([keyframes], index) => property in (keyframes as Keyframe[])[0]
            ? [animate.mock.contexts[index] as HTMLElement]
            : []);
        // Dev builds replay mount effects; the row must still animate, once.
        const render = () => root.render(createElement(StrictMode, null, createElement(Sidebar, props)));
        act(() => render());
        expect(animate).not.toHaveBeenCalled();
        props = {
            ...props,
            sessions: [
                {
                    ...props.sessions[0],
                    id: "session-2",
                    createdAt: Date.now(),
                    updatedAt: props.sessions[0].updatedAt + 1,
                },
                ...props.sessions,
            ],
        };
        act(() => render());
        // The new card fades in where it lands; the row below slides down.
        expect(animated("opacity")).toHaveLength(1);
        expect(animated("opacity")[0].closest("li")?.querySelector('[data-session-card="session-2"]')).not.toBeNull();
        expect(animated("transform")).toHaveLength(1);
        expect(animated("transform")[0].querySelector('[data-session-card="session-1"]')).not.toBeNull();
        const calls = animate.mock.calls.length;
        props = {
            ...props,
            sessions: [
                { ...props.sessions[0], id: "session-old", createdAt: 1 },
                ...props.sessions,
            ],
        };
        act(() => render());
        expect(animate).toHaveBeenCalledTimes(calls);
        // Reordering existing rows must not replay their entrance.
        props = { ...props, sessions: [...props.sessions].reverse() };
        act(() => render());
        expect(animate).toHaveBeenCalledTimes(calls);
    });
});
describe("sidebar pinned sessions", () => {
    it("renders them as a collapsible folder-style group without a divider", () => {
        props.sessions = [
            { ...props.sessions[0], pinned: true },
            {
                ...props.sessions[0],
                id: "session-2",
                title: formatSessionTitle("codex", "Unpinned conversation"),
                updatedAt: props.sessions[0].updatedAt - 1,
            },
        ];
        act(() => render());
        const group = container.querySelector<HTMLElement>("[data-pinned-sessions]")!;
        const toggle = group.querySelector<HTMLButtonElement>('button[title="Pinned"]')!;
        expect(toggle.getAttribute("aria-expanded")).toBe("true");
        expect(group.querySelector('[data-session-card="session-1"]')).not.toBeNull();
        expect(container.querySelector("li[aria-hidden]")).toBeNull();
        act(() => toggle.click());
        expect(toggle.getAttribute("aria-expanded")).toBe("false");
        expect(group.querySelector('[data-session-card="session-1"]')).toBeNull();
        expect(JSON.parse(localStorage.getItem("loci.pinnedSessionsCollapsed") ?? "{}")).toEqual({ "/workspace/project": true });
    });
});
describe("sidebar session reminders", () => {
    function openReminderMenu() {
        act(() => card().dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true })));
        const trigger = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent === "Remind me")!;
        act(() => trigger.dispatchEvent(new MouseEvent("mouseover", { bubbles: true })));
        return document.querySelector<HTMLElement>('[role="menu"][aria-label="Remind me"]')!;
    }
    it("schedules the selected session from the hover submenu", () => {
        props.onSetReminders = vi.fn();
        act(() => render());
        const submenu = openReminderMenu();
        const preset = Array.from(submenu.querySelectorAll<HTMLButtonElement>("button")).find((item) => item.textContent?.startsWith("In 3 hours"))!;
        const before = Date.now();
        act(() => preset.click());
        const [ids, dueAt] = vi.mocked(props.onSetReminders).mock.calls[0];
        expect(ids).toEqual(["session-1"]);
        expect(dueAt).toBeGreaterThanOrEqual(before + 3 * 60 * 60 * 1000);
        expect(dueAt).toBeLessThanOrEqual(Date.now() + 3 * 60 * 60 * 1000);
        expect(document.querySelector('[role="menu"]')).toBeNull();
    });
    it("groups reminders first without a card clock and offers cancellation first", () => {
        props.onSetReminders = vi.fn();
        props.onCancelReminders = vi.fn();
        props.reminders = [
            {
                sessionId: "session-1",
                dueAt: Date.now() + 3600000,
                firedAt: null,
                title: "Original conversation",
                harness: "codex",
                cwd: props.cwd,
            },
        ];
        props.sessions = [
            { ...props.sessions[0], pinned: true },
            { ...props.sessions[0], id: "session-2", pinned: true },
        ];
        act(() => render());
        const group = container.querySelector<HTMLElement>("[data-reminder-sessions]")!;
        expect(group.parentElement!.firstElementChild).toBe(group);
        expect(group.querySelector('[data-session-card="session-1"]')).toBe(card());
        expect(container.querySelectorAll('[data-session-card="session-1"]')).toHaveLength(1);
        expect(group.hasAttribute("data-session-folder")).toBe(false);
        expect(group.querySelector('button[title="Reminders"]')!.className).not.toContain("cursor-grab");
        expect(card().querySelector('[aria-label^="Reminder:"]')).toBeNull();
        act(() => card().dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true })));
        const cancel = document.querySelector<HTMLButtonElement>('[aria-label="Session actions"] [role="menuitem"]')!;
        expect(cancel.textContent).toBe(`Cancel reminder${formatReminderTime(props.reminders[0].dueAt)}`);
        act(() => cancel.click());
        expect(props.onCancelReminders).toHaveBeenCalledExactlyOnceWith([
            "session-1",
        ]);
        expect(props.onSetReminders).not.toHaveBeenCalled();
        props.reminders = [];
        act(() => render());
        expect(container.querySelector("[data-reminder-sessions]")).toBeNull();
        expect(container.querySelector('[data-pinned-sessions] [data-session-card="session-1"]')).toBe(card());
    });
});
describe("collapsed rail actions", () => {
    it("restores the hidden rail layout when compact mode is disabled", async () => {
        props.projectRailOpen = false;
        props.compactProjectRail = false;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onNew = vi.fn();
        props.onSearch = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onOpenSettings = vi.fn();
        props.onToggleProjectRail = vi.fn();
        await act(async () => render());
        const sidebar = container.querySelector("aside")!;
        expect(container.querySelector("[data-compact-project-rail]")).toBeNull();
        expect(sidebar.querySelector('button[aria-label^="Toggle Projects"]')).not.toBeNull();
        expect(sidebar.querySelector('button[aria-label^="Search"]')).not.toBeNull();
        expect(sidebar.querySelector('button[aria-label^="Settings"]')).not.toBeNull();
    });
    it("yields its local header to the full-width title bar", async () => {
        props.projectRailOpen = false;
        props.titleBarAbove = true;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onGoBack = vi.fn();
        await act(async () => render());
        const rail = container.querySelector<HTMLElement>("[data-compact-project-rail]")!;
        expect(rail.querySelector("[data-compact-rail-divider]")?.className).toContain("top-0");
        expect(rail.querySelector("[data-compact-rail-divider]")?.className).not.toContain("top-10");
        expect(container.textContent).not.toContain("Development");
        expect(container.querySelector('button[aria-label^="Back"]')).toBeNull();
    });
    it("has one way into drawings: the Canvas tab, which also reaches the page of all of them", async () => {
        props.projectRailOpen = false;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onOpenSettings = vi.fn();
        props.onToggleProjectRail = vi.fn();
        const openAll = vi.fn();
        props.onOpenCanvases = openAll;
        props.onOpenCanvas = vi.fn();
        props.onOpenCanvasInTab = vi.fn();
        props.onNewCanvas = vi.fn();
        props.onRenameCanvas = vi.fn();
        props.onDeleteCanvas = vi.fn();
        await act(async () => render());
        const rail = container.querySelector<HTMLElement>("[data-compact-project-rail]")!;
        const labels = Array.from(rail.querySelectorAll("button"), (button) => button.getAttribute("aria-label")?.replace(/ \(.+\)$/, ""));
        // The page of drawings is no longer a second icon beside the tab.
        expect(labels.filter((label) => label === "Excalidraw" || label === "Canvas")).toEqual(["Canvas"]);
        // The tab carries the Excalidraw mark rather than a generic pen.
        const canvasTab = rail.querySelector<HTMLElement>('button[aria-label="Canvas"]')!;
        expect(canvasTab.querySelector("svg")).not.toBeNull();
        await act(async () => canvasTab.click());
        const all = container.querySelector<HTMLElement>('button[aria-label="All Drawings"]');
        expect(all).not.toBeNull();
        await act(async () => all!.click());
        expect(openAll).toHaveBeenCalledOnce();
        // The chosen tab is remembered across mounts; leave it as other tests expect.
        await act(async () => rail.querySelector<HTMLElement>('button[aria-label="Sessions"]')!.click());
    });
    it("keeps project shortcuts in a compact vertical rail", async () => {
        props.projectRailOpen = false;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onNew = vi.fn();
        props.onSearch = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onOpenSettings = vi.fn();
        props.onToggleProjectRail = vi.fn();
        await act(async () => render());
        const rail = container.querySelector<HTMLElement>("[data-compact-project-rail]")!;
        expect(rail).not.toBeNull();
        expect(rail.className).toContain("w-12");
        expect(rail.className).not.toContain("border-r");
        expect(rail.querySelector("[data-compact-rail-divider]")?.className).toContain("top-10");
        expect(rail.querySelectorAll('[class*="border-b"], [class*="border-t"]')).toHaveLength(1);
        expect(rail.firstElementChild?.className).toContain("border-b");
        expect(rail.querySelector("[data-compact-rail-actions]")?.className).toContain("gap-1.5");
        expect(Array.from(rail.querySelectorAll("button"), (button) => button.getAttribute("aria-label")?.replace(/ \(.+\)$/, ""))).toEqual([
            "Expand projects",
            "Switch project, current project project",
            "Sessions",
            "Files",
            "Canvas",
            "Search",
            "Notes",
            "Settings",
        ]);
        const workspaceTabs = rail.querySelector<HTMLElement>('[role="tablist"][aria-label="Workspace"]')!;
        expect(workspaceTabs).not.toBeNull();
        expect(Array.from(workspaceTabs.querySelectorAll('[role="tab"]'), (button) => button.getAttribute("aria-label"))).toEqual(["Sessions", "Files", "Canvas"]);
        const sessionsTab = workspaceTabs.querySelector<HTMLButtonElement>('[aria-label="Sessions"]')!;
        expect(sessionsTab.getAttribute("aria-selected")).toBe("true");
        expect(sessionsTab.querySelector("span")).toBeNull();
        expect(container.querySelectorAll('[role="tablist"][aria-label="Workspace"]')).toHaveLength(1);
        act(() => workspaceTabs
            .querySelector<HTMLButtonElement>('[aria-label="Sessions"]')!
            .click());
        expect(props.onTabChange).toHaveBeenCalledWith("sessions");
        expect(container.querySelector('button[aria-label="Notes"]')?.closest("nav")).toBe(rail);
        const projectPicker = rail.querySelector<HTMLButtonElement>('button[aria-label^="Switch project"]')!;
        expect(projectPicker.className).toContain("size-8");
        expect(Array.from(rail.querySelectorAll("button")).every((button) => button.className.includes("size-8"))).toBe(true);
        expect(Array.from(rail.querySelectorAll("button")).every((button) => !button.className.includes("transition"))).toBe(true);
        expect(projectPicker.querySelector("svg, img")).not.toBeNull();
        expect(projectPicker.querySelector("span")).toBeNull();
        expect(container.querySelectorAll('button[aria-label^="Switch project"]')).toHaveLength(1);
        act(() => projectPicker.click());
        expect(projectSearchInput()).not.toBeNull();
        act(() => rail
            .querySelector<HTMLButtonElement>('button[aria-label="Expand projects"]')!
            .click());
        expect(props.onToggleProjectRail).toHaveBeenCalledOnce();
    });
    it("slides the collapsed sidebar open until dismissed from the compact tabs", async () => {
        // happy-dom animations never finish, so drive them by hand.
        const animations: {
            keyframes: Keyframe[];
            animation: Animation;
        }[] = [];
        vi.spyOn(HTMLElement.prototype, "animate").mockImplementation((keyframes) => {
            const animation = {
                cancel: vi.fn(),
                onfinish: null,
            } as unknown as Animation;
            animations.push({ keyframes: keyframes as Keyframe[], animation });
            return animation;
        });
        const finish = () => act(() => {
            const { animation } = animations.at(-1)!;
            animation.onfinish?.call(animation, new Event("finish") as never);
        });
        props.open = false;
        props.projectRailOpen = false;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onTabChange = vi.fn((tab) => {
            props = { ...props };
            render();
        });
        await act(async () => render());
        const drawer = () => container.querySelector<HTMLElement>("[data-sidebar-drawer]");
        const compactTab = (label: string) => container.querySelector<HTMLButtonElement>(`[data-compact-project-rail] [role="tab"][aria-label="${label}"]`)!;
        // A dismissed drawer slides shut before it unmounts.
        const expectDrawerDismissed = () => {
            expect(drawer()?.dataset.sidebarDrawer).toBe("closing");
            expect(drawer()?.inert).toBe(true);
            expect(animations.at(-1)!.keyframes.at(-1)).toEqual({ width: "0px" });
            finish();
            expect(drawer()).toBeNull();
        };
        expect(drawer()).toBeNull();
        expect(compactTab("Sessions").getAttribute("aria-selected")).toBe("false");
        act(() => compactTab("Sessions").click());
        expect(props.onTabChange).toHaveBeenLastCalledWith("sessions");
        expect(drawer()?.dataset.sidebarDrawer).toBe("open");
        // It pushes the workspace like the pinned sidebar, growing from nothing.
        expect(drawer()?.className).not.toContain("absolute");
        expect(drawer()?.querySelector("aside")?.className).toContain("body-glass");
        expect(animations).toHaveLength(1);
        expect(animations[0].keyframes[0]).toEqual({ width: "0px" });
        expect(compactTab("Sessions").getAttribute("aria-selected")).toBe("true");
        expect(drawer()?.contains(card())).toBe(true);
        // The session content stays mounted while the drawer is open.
        expect(animations).toHaveLength(1);
        act(() => compactTab("Sessions").click());
        expectDrawerDismissed();
        // Reopening mid-slide reverses the running animation.
        act(() => compactTab("Sessions").click());
        act(() => compactTab("Sessions").click());
        const closing = animations.at(-1)!.animation;
        act(() => compactTab("Sessions").click());
        expect(closing.cancel).toHaveBeenCalled();
        expect(drawer()?.dataset.sidebarDrawer).toBe("open");
        pressKey(document.body, "Escape");
        expectDrawerDismissed();
        act(() => compactTab("Sessions").click());
        act(() => {
            document.body.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
        });
        expectDrawerDismissed();
        act(() => compactTab("Sessions").click());
        act(() => card().click());
        expect(props.onSelectSession).toHaveBeenCalledWith("session-1");
        expectDrawerDismissed();
        // Pinning the sidebar open replaces the drawer at once.
        act(() => compactTab("Sessions").click());
        props.open = true;
        act(() => render());
        expect(drawer()).toBeNull();
    });
    it.each([
        ["compact rail", true],
        ["sidebar header", false],
    ])("deletes a project from the %s picker while the rail is hidden", async (_, compact) => {
        props.projectRailOpen = false;
        props.compactProjectRail = compact;
        props.recents = [{ path: "/workspace/other", openedAt: 1 }];
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onRemoveProject = vi.fn();
        await act(async () => render());
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-label^="Switch project"]')!
            .click());
        const row = document.querySelector<HTMLButtonElement>('button[title="/workspace/other"]')!;
        await act(async () => {
            row.dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
        });
        expect(projectSearchInput()).not.toBeNull();
        const remove = Array.from(document.querySelectorAll<HTMLButtonElement>('[role="menuitem"]')).find((item) => item.textContent?.startsWith("Delete"))!;
        act(() => {
            remove.dispatchEvent(new Event("pointerdown", { bubbles: true }));
            remove.click();
        });
        expect(projectSearchInput()).not.toBeNull();
        const dialog = document.querySelector('[aria-label="Delete other"]')!;
        const confirm = Array.from(dialog.querySelectorAll<HTMLButtonElement>("button")).find((button) => button.textContent === "Delete")!;
        act(() => confirm.click());
        expect(props.onRemoveProject).toHaveBeenCalledWith("/workspace/other", {
            purgeData: true,
        });
        expect(document.activeElement).toBe(projectSearchInput());
    });
    it("opens the active picker project's menu from the keyboard", async () => {
        props.projectRailOpen = false;
        props.recents = [{ path: "/workspace/other", openedAt: 1 }];
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onRemoveProject = vi.fn();
        await act(async () => render());
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-label^="Switch project"]')!
            .click());
        pressKey(projectSearchInput()!, "ArrowDown");
        await act(async () => {
            projectSearchInput()!.dispatchEvent(new KeyboardEvent("keydown", {
                key: "ContextMenu",
                bubbles: true,
                cancelable: true,
            }));
        });
        expect(document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')
            ?.value).toBe("other");
    });
    it("opens a Tab-focused picker row's menu rather than the highlighted one", async () => {
        props.projectRailOpen = false;
        props.recents = [{ path: "/workspace/other", openedAt: 1 }];
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        await act(async () => render());
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-label^="Switch project"]')!
            .click());
        const row = document.querySelector<HTMLButtonElement>('button[title="/workspace/other"]')!;
        row.focus();
        await act(async () => {
            row.dispatchEvent(new KeyboardEvent("keydown", {
                key: "F10",
                shiftKey: true,
                bubbles: true,
                cancelable: true,
            }));
        });
        expect(document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')
            ?.value).toBe("other");
    });
    it("shows a rename from the picker menu in the open picker", async () => {
        props.projectRailOpen = false;
        props.recents = [{ path: "/workspace/other", openedAt: 1 }];
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        await act(async () => render());
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-label^="Switch project"]')!
            .click());
        const row = () => document.querySelector<HTMLButtonElement>('button[title="/workspace/other"]')!;
        await act(async () => {
            row().dispatchEvent(new MouseEvent("contextmenu", { bubbles: true, cancelable: true }));
        });
        const name = document.querySelector<HTMLInputElement>('input[aria-label="Group name"]')!;
        typeTitle(name, "Client site");
        pressKey(name, "Enter");
        expect(document.querySelector('input[aria-label="Group name"]')).toBeNull();
        expect(row().textContent).toContain("Client site");
    });
    it("uses an active compact shortcut to return to the workspace", async () => {
        props.projectRailOpen = false;
        props.onSelectProject = vi.fn();
        props.onOpenProject = vi.fn();
        props.onOpenNotes = vi.fn();
        props.onGoBack = vi.fn();
        props.notesActive = true;
        await act(async () => render());
        const notes = container.querySelector<HTMLButtonElement>('button[aria-label="Notes"]')!;
        expect(notes.getAttribute("aria-pressed")).toBe("true");
        act(() => notes.click());
        expect(props.onGoBack).toHaveBeenCalledOnce();
        expect(props.onOpenNotes).not.toHaveBeenCalled();
        props.notesActive = false;
        act(() => render());
        act(() => container
            .querySelector<HTMLButtonElement>('button[aria-label="Notes"]')!
            .click());
        expect(props.onOpenNotes).toHaveBeenCalledOnce();
    });
});
describe("sidebar working agents", () => {
    it("shows the original working widget when the project rail is collapsed", () => {
        props.projectRailOpen = false;
        props.onSelectAgent = vi.fn();
        props.liveAgents = [
            {
                id: "agent-a",
                cwd: "/workspace/alpha",
                title: "Build settings",
                harness: "codex",
                activity: "Editing Settings.tsx",
                startedAt: Date.now() - 10000,
                needsApproval: false,
                done: false,
            },
            {
                id: "agent-b",
                cwd: "/workspace/beta",
                title: "Review tests",
                harness: "claude",
                activity: "Running tests",
                startedAt: Date.now() - 5000,
                needsApproval: false,
                done: false,
            },
        ];
        act(() => render());
        const preview = container.querySelector<HTMLElement>('[data-live-agents-preview="full"]')!;
        expect(preview.querySelectorAll("[data-live-agent-card]")).toHaveLength(2);
        expect(preview.querySelector('[data-live-agent-card="agent-a"]')!.textContent).toContain("alpha");
        expect(preview.querySelector('[data-live-agent-card="agent-b"]')!.textContent).toContain("beta");
        expect(preview.querySelector(".mascot-active")).not.toBeNull();
        act(() => preview
            .querySelector<HTMLButtonElement>('[data-live-agent-card="agent-b"]')!
            .click());
        expect(props.onSelectAgent).toHaveBeenCalledExactlyOnceWith("agent-b");
        props.projectRailOpen = true;
        act(() => render());
        expect(container.querySelector("[data-live-agents-preview]")).toBeNull();
    });
});
