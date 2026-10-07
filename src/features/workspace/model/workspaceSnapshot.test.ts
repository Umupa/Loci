import { describe, expect, it } from "vitest";
import { appendUser } from "../../../integrations/harness/core/apply";
import { CONTINUE_PROMPT, INTERRUPT_MESSAGE, canAutoContinue, } from "../../sessions/model/inFlight";
import { canvasLeaf, leaf, leafIds, newTab, splitPane, } from "./layout";
import { newSession, type Session } from "../../sessions/model/session";
import { collectWorkspaceSnapshot, hydrateWorkspaceSnapshot, parseWorkspaceSnapshot, } from "./workspaceSnapshot";
import { filterTabsForProject } from "./workspaceTabGroups";
function chat(id: string, cwd: string): Session {
    const session = newSession("claude", cwd);
    session.id = id;
    session.blocks = [{ id: "u1", role: "user", text: "hello" }];
    session.providerSessionId = "p1";
    return session;
}
describe("project return snapshots", () => {
    function saved() {
        const sessions = [
            chat("a1", "/alpha"),
            chat("a2", "/alpha"),
            chat("b1", "/beta"),
            chat("b2", "/beta"),
        ];
        const tabs = sessions.map((session) => ({
            ...newTab(session.id),
            id: `tab-${session.id}`,
        }));
        return {
            ...collectWorkspaceSnapshot(tabs, sessions, "tab-b2", "/beta", new Map()),
            projectReturnTargets: [
                { projectPath: "/alpha", tabId: "a2" },
                { projectPath: "/beta", tabId: "b2" },
            ],
        };
    }
    it("collects and round-trips choices while rejecting stale references", () => {
        const sessions = [
            chat("a1", "/alpha"),
            chat("a2", "/alpha"),
            chat("b2", "/beta"),
        ];
        const tabs = sessions.map((session) => ({
            ...newTab(session.id),
            id: `tab-${session.id}`,
        }));
        const memory = new Map([
            ["/alpha", "a2"],
            ["/beta", "b2"],
            ["/gone", "missing"],
        ]);
        const snapshot = collectWorkspaceSnapshot(tabs, sessions, "tab-b2", "/beta", memory);
        const restored = hydrateWorkspaceSnapshot(snapshot, new Map());
        expect([...(restored?.projectReturnMemory ?? [])]).toEqual([
            ["/alpha", "a2"],
            ["/beta", "b2"],
        ]);
        expect(memory.size).toBe(3);
    });
    it("restores both project choices, not just the active tab", () => {
        const restored = hydrateWorkspaceSnapshot(saved(), new Map());
        expect(restored?.projectReturnMemory?.get("/alpha")).toBe("a2");
        expect(restored?.projectReturnMemory?.get("/beta")).toBe("b2");
    });
    it("loads old snapshots and seeds only the active project", () => {
        const { projectReturnTargets: _targets, ...old } = saved();
        const restored = hydrateWorkspaceSnapshot(old, new Map());
        expect([...(restored?.projectReturnMemory ?? [])]).toEqual([
            ["/beta", "b2"],
        ]);
    });
    it("prunes invalid entries and uses the last valid duplicate", () => {
        const raw = saved();
        const parsed = parseWorkspaceSnapshot({
            ...raw,
            projectReturnTargets: [
                null,
                42,
                {},
                { projectPath: "/alpha", tabId: 12 },
                { projectPath: "/alpha/", tabId: "a1" },
                { projectPath: "/alpha", tabId: "a2" },
                { projectPath: "/gone", tabId: "missing" },
                { projectPath: "/beta", tabId: "a1" },
            ],
        });
        expect(parsed?.projectReturnTargets).toEqual([
            { projectPath: "/alpha", tabId: "a2" },
        ]);
    });
    it("lets the restored active tab override inconsistent saved preference", () => {
        const raw = saved();
        raw.projectReturnTargets[1].tabId = "tab-b1";
        expect(hydrateWorkspaceSnapshot(raw, new Map())?.projectReturnMemory?.get("/beta")).toBe("b2");
    });
    it.each([null, "broken", {}])("ignores a malformed choice list: %j", (projectReturnTargets) => {
        const restored = hydrateWorkspaceSnapshot({ ...saved(), projectReturnTargets }, new Map());
        expect(restored?.tabs).toHaveLength(4);
        expect([...(restored?.projectReturnMemory ?? [])]).toEqual([
            ["/beta", "b2"],
        ]);
    });
    it("rechecks project membership against loaded sessions", () => {
        const restored = hydrateWorkspaceSnapshot(saved(), new Map([["a2", chat("a2", "/moved")]]));
        expect(restored?.projectReturnMemory?.has("/alpha")).toBe(false);
        expect(restored?.projectReturnMemory?.get("/beta")).toBe("b2");
    });
});
describe("collectWorkspaceSnapshot", () => {
    it("stores tabs, stubs, and the focused tab — not transcripts", () => {
        const session = chat("s1", "/tmp/a");
        session.blocks.push({ id: "a1", role: "assistant", text: "hi" });
        const tab = {
            ...newTab("s1"),
            id: "t1",
        };
        const snapshot = collectWorkspaceSnapshot([tab], [session], "t1", "/tmp/a", new Map());
        expect(snapshot.activeTabId).toBe("t1");
        expect(snapshot.sessions).toEqual([
            expect.objectContaining({
                id: "s1",
                cwd: "/tmp/a",
                providerSessionId: "p1",
            }),
        ]);
        expect("blocks" in snapshot.sessions[0]!).toBe(false);
    });
});
describe("parseWorkspaceSnapshot", () => {
    it("returns null for empty or invalid payloads", () => {
        expect(parseWorkspaceSnapshot(null)).toBeNull();
        expect(parseWorkspaceSnapshot({ tabs: [], activeTabId: "t1" })).toBeNull();
        expect(parseWorkspaceSnapshot({ tabs: [{}], activeTabId: "t1" })).toBeNull();
    });
    it("drops unknown fields and repairs a missing active tab", () => {
        const tab = { ...newTab("s1"), id: "t1" };
        const parsed = parseWorkspaceSnapshot({
            tabs: [{ ...tab, extra: true }],
            sessions: [
                {
                    id: "s1",
                    harness: "claude",
                    runtimeMode: "supervised",
                    cwd: "/tmp/a",
                },
            ],
            activeTabId: "missing",
            projectCwd: "/tmp/a",
        });
        expect(parsed?.activeTabId).toBe("t1");
        expect(parsed?.tabs[0] && "extra" in parsed.tabs[0]).toBe(false);
    });
    it("drops unsupported panes without hydrating them as conversations", () => {
        const session = chat("chat", "/project");
        const retired = { type: "leaf", id: "retired", leafKind: "retired" };
        const raw = {
            ...collectWorkspaceSnapshot([newTab("chat")], [session], "mixed", "/project", new Map()),
            tabs: [
                { ...newTab("retired"), id: "removed", layout: retired },
                {
                    ...newTab("chat"), id: "mixed", focusedId: "retired", cwd: "/project",
                    layout: {
                        type: "split", id: "outer", dir: "right",
                        children: [
                            { type: "split", id: "inner", dir: "down", children: [retired, leaf("chat")], sizes: [0.5, 0.5] },
                            canvasLeaf("drawing"),
                        ],
                        sizes: [0.4, 0.6],
                    },
                },
            ],
            activeTabId: "removed",
        };
        const parsed = parseWorkspaceSnapshot(raw)!;
        expect(parsed.tabs).toHaveLength(1);
        expect(parsed.activeTabId).toBe("mixed");
        expect(parsed.tabs[0].focusedId).toBe("chat");
        expect(parsed.tabs[0].layout).toEqual({
            type: "split", id: "outer", dir: "right",
            children: [leaf("chat"), canvasLeaf("drawing")], sizes: [0.4, 0.6],
        });
        const resumed = hydrateWorkspaceSnapshot(parsed, new Map())!;
        expect(resumed.sessions.map((entry) => entry.id)).toEqual(["chat"]);
    });
    it("returns null when all saved panes are unsupported", () => {
        expect(parseWorkspaceSnapshot({
            tabs: [{ ...newTab("retired"), id: "removed", layout: { type: "leaf", id: "retired", leafKind: "retired" } }],
            activeTabId: "removed",
        })).toBeNull();
    });
    it.each([
        { label: "keeps the current project when another tab survives", remaining: ["b", "a"], active: "a", cwd: "/a" },
        { label: "switches to the fallback conversation's project", remaining: ["b"], active: "b", cwd: "/b" },
        { label: "uses the fallback canvas's project", remaining: ["drawing"], active: "drawing", cwd: "/drawing" },
    ])("$label after removing the active pane", ({ remaining, active, cwd }) => {
        const sessions = [chat("a", "/a"), chat("b", "/b")];
        const tabs = remaining.map((id) => ({
            ...newTab(id), id: `tab-${id}`,
            ...(id === "drawing" ? { layout: canvasLeaf(id), cwd: "/drawing" } : {}),
        }));
        const raw = {
            ...collectWorkspaceSnapshot(tabs, sessions, "removed", "/a", new Map()),
            tabs: [...tabs, { ...newTab("retired"), id: "removed", cwd: "/a", layout: { type: "leaf", id: "retired", leafKind: "retired" } }],
            activeTabId: "removed",
        };
        const parsed = parseWorkspaceSnapshot(raw)!;
        const resumed = hydrateWorkspaceSnapshot(parsed, new Map())!;
        expect(resumed.activeTabId).toBe(`tab-${active}`);
        expect(resumed.projectCwd).toBe(cwd);
        expect(filterTabsForProject(resumed.tabs, resumed.sessions, resumed.projectCwd).some((tab) => tab.id === resumed.activeTabId)).toBe(true);
    });
});
describe("hydrateWorkspaceSnapshot", () => {
    it("reopens splits and stored transcripts", () => {
        const left = chat("s1", "/tmp/a");
        const right = chat("s2", "/tmp/a");
        const tab = {
            ...newTab("s1"),
            id: "t1",
            layout: {
                type: "split" as const,
                id: "split1",
                dir: "right" as const,
                children: [leaf("s1"), leaf("s2")],
                sizes: [0.5, 0.5],
            },
            focusedId: "s2",
        };
        const snapshot = collectWorkspaceSnapshot([tab], [left, right], "t1", "/tmp/a", new Map());
        const loaded = new Map([
            [
                "s1",
                {
                    ...left,
                    blocks: [
                        ...left.blocks,
                        { id: "a1", role: "assistant" as const, text: "stored" },
                    ],
                },
            ],
        ]);
        const workspace = hydrateWorkspaceSnapshot(snapshot, loaded);
        expect(workspace?.tabs).toHaveLength(1);
        expect(workspace?.tabs[0]?.layout).toEqual(tab.layout);
        expect(workspace?.sessions.find((session) => session.id === "s1")?.blocks).toEqual(loaded.get("s1")?.blocks);
        expect(workspace?.sessions.find((session) => session.id === "s2")?.blocks).toEqual([]);
    });
    it("marks in-flight chats interrupted and adds a tab if they were parked", () => {
        const open = chat("s1", "/tmp/a");
        const parked = chat("s2", "/tmp/a");
        parked.busy = true;
        const snapshot = collectWorkspaceSnapshot([{ ...newTab("s1"), id: "t1" }], [open, parked], "t1", "/tmp/a", new Map());
        const workspace = hydrateWorkspaceSnapshot(snapshot, new Map([
            ["s1", open],
            ["s2", parked],
        ]), new Set(["s2"]));
        expect(workspace?.tabs).toHaveLength(2);
        const resumed = workspace?.sessions.find((session) => session.id === "s2");
        expect(resumed?.busy).toBe(false);
        expect(resumed?.blocks.some((block) => block.text === INTERRUPT_MESSAGE)).toBe(true);
    });
    it("continues a Codex snapshot with its saved model and settings before discovery", () => {
        const session: Session = {
            ...chat("s1", "/tmp/a"),
            harness: "codex",
            model: "codex:gpt-5.6-sol",
            modelSettings: { reasoningEffort: "high", serviceTier: "priority" },
        };
        const tab = newTab(session.id);
        const snapshot = collectWorkspaceSnapshot([tab], [session], tab.id, session.cwd, new Map());
        const restored = hydrateWorkspaceSnapshot(snapshot, new Map(), new Set([session.id]))?.sessions[0];
        expect(restored).toBeDefined();
        expect(restored?.model).toBe("codex:gpt-5.6-sol");
        expect(restored?.modelSettings).toEqual(session.modelSettings);
        expect(canAutoContinue(restored!)).toBe(true);
        const continued = appendUser(restored!, CONTINUE_PROMPT);
        expect(continued.blocks.at(-1)?.turnModel).toEqual({
            harness: "codex",
            id: "codex:gpt-5.6-sol",
            name: "GPT-5.6-Sol",
        });
    });
});
