import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
const mocks = vi.hoisted(() => ({
    discoverNativeCommands: vi.fn(),
    sessionScoped: false,
    subscribe: vi.fn(),
}));
vi.mock("../../../integrations/harness/core/registry", () => ({
    getHarness: (id: string) => id === "codex" ? { commands: { discover: ({cwd}: {cwd:string}) => mocks.discoverNativeCommands(cwd), ...(mocks.sessionScoped ? {subscribe: mocks.subscribe} : {}) } } : undefined,
}));
import { invalidateSkills, loadSkills, peekSkills, skillCatalogKey, subscribeSkills } from "./skills";
import type { NativeCommand } from "../../../integrations/harness/core/nativeCommands";
function nativeCommand(name: string): NativeCommand {
    return {
        name,
        description: `${name} description`,
        invocation: `skill:${name}`,
        source: "codex",
    };
}
function deferred<T>() {
    let resolve!: (value: T) => void;
    let reject!: (error: Error) => void;
    const promise = new Promise<T>((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}
beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-29T12:00:00Z"));
    invalidateSkills();
    mocks.discoverNativeCommands.mockReset();
    mocks.discoverNativeCommands.mockReset();
    mocks.discoverNativeCommands.mockResolvedValue([
        {
            name: "workflow",
            invocation: "workflow",
            description: "",
            source: "codex",
        },
    ]);
    mocks.subscribe.mockReset();
    mocks.discoverNativeCommands.mockResolvedValue([nativeCommand("architect")]);
});
describe("provider-aware skill catalog", () => {
    it("uses native discovery", async () => {
        const catalog = await loadSkills({ harness: "codex", cwd: "/repo/" });
        expect(mocks.discoverNativeCommands).toHaveBeenCalledWith("/repo");
        expect(catalog).toEqual([
            {
                kind: "native",
                ...nativeCommand("architect"),
            },
        ]);
    });
    it("a live command update supersedes an older probe and refreshes subscribers", async () => {
 mocks.sessionScoped = true;
        const context = {
            harness: "codex" as const,
            cwd: "/repo",
            sessionId: "thread",
        };
        const probe = deferred<unknown>();
        mocks.discoverNativeCommands.mockReturnValue(probe.promise);
        const pending = loadSkills(context);
        const onSkills = vi.fn();
        const unsubscribe = vi.fn();
        mocks.subscribe.mockReturnValue(unsubscribe);
        const stop = subscribeSkills(context, onSkills);
        mocks.subscribe.mock.calls[0]![1]([
            {
                name: "new-workflow",
                invocation: "new-workflow",
                source: "codex",
                description: "",
            },
        ]);
        probe.resolve([
            {
                name: "old-workflow",
                invocation: "old-workflow",
                source: "codex",
                description: "",
            },
        ]);
        await expect(pending).resolves.toMatchObject([{ name: "new-workflow" }]);
        expect(onSkills).toHaveBeenCalledWith(expect.arrayContaining([
            expect.objectContaining({ kind: "native", name: "new-workflow" }),
        ]));
        stop();
        expect(unsubscribe).toHaveBeenCalledOnce();
    });
    it("offers nothing for a provider without native commands: skill files are not read", async () => {
        await expect(loadSkills({ harness: "claude", cwd: "/repo" })).resolves.toEqual([]);
        expect(mocks.discoverNativeCommands).not.toHaveBeenCalled();
    });
    it("separates providers and coalesces equivalent native directories", async () => {
        const pending = deferred<NativeCommand[]>();
        mocks.discoverNativeCommands.mockReturnValue(pending.promise);
        const first = loadSkills({ harness: "codex", cwd: "/repo/" });
        const second = loadSkills({ harness: "codex", cwd: "/repo" });
        const claude = loadSkills({ harness: "claude", cwd: "/repo" });
        expect(mocks.discoverNativeCommands).toHaveBeenCalledTimes(1);
        expect(skillCatalogKey({ harness: "codex", cwd: "/repo/" })).toBe(skillCatalogKey({ harness: "codex", cwd: "/repo" }));
        expect(skillCatalogKey({ harness: "codex", cwd: "/repo" })).not.toBe(skillCatalogKey({ harness: "claude", cwd: "/repo" }));
        pending.resolve([nativeCommand("architect")]);
        await expect(first).resolves.toEqual(await second);
        await claude;
    });
    it("refreshes stale native data and retains it after a failed refresh", async () => {
        await loadSkills({ harness: "codex", cwd: "/repo" });
        vi.advanceTimersByTime(30001);
        const refresh = deferred<NativeCommand[]>();
        mocks.discoverNativeCommands.mockReturnValueOnce(refresh.promise);
        const loading = loadSkills({ harness: "codex", cwd: "/repo" });
        expect(peekSkills({ harness: "codex", cwd: "/repo" })?.[0]?.name).toBe("architect");
        refresh.resolve([nativeCommand("new-skill")]);
        await expect(loading).resolves.toMatchObject([{ name: "new-skill" }]);
        vi.advanceTimersByTime(30001);
        mocks.discoverNativeCommands.mockRejectedValueOnce(new Error("offline"));
        await expect(loadSkills({ harness: "codex", cwd: "/repo" })).resolves.toMatchObject([{ name: "new-skill" }]);
        await loadSkills({ harness: "codex", cwd: "/repo" });
        expect(mocks.discoverNativeCommands).toHaveBeenCalledTimes(3);
        vi.advanceTimersByTime(5001);
        await loadSkills({ harness: "codex", cwd: "/repo" });
        expect(mocks.discoverNativeCommands).toHaveBeenCalledTimes(4);
    });
    it("does not let an invalidated request replace a newer generation", async () => {
        const old = deferred<NativeCommand[]>();
        const current = deferred<NativeCommand[]>();
        mocks.discoverNativeCommands
            .mockReturnValueOnce(old.promise)
            .mockReturnValueOnce(current.promise);
        const oldLoad = loadSkills({ harness: "codex", cwd: "/repo" });
        invalidateSkills({ cwd: "/repo" });
        const currentLoad = loadSkills({ harness: "codex", cwd: "/repo" }, { refresh: true });
        current.resolve([nativeCommand("current")]);
        await currentLoad;
        old.resolve([nativeCommand("old")]);
        await expect(oldLoad).resolves.toMatchObject([{ name: "current" }]);
        expect(peekSkills({ harness: "codex", cwd: "/repo" })).toMatchObject([
            { name: "current" },
        ]);
    });
    it("rejects completions captured before a global reset", async () => {
        const old = deferred<NativeCommand[]>();
        mocks.discoverNativeCommands.mockReturnValueOnce(old.promise);
        const oldLoad = loadSkills({ harness: "codex", cwd: "/repo" });
        invalidateSkills();
        mocks.discoverNativeCommands.mockResolvedValueOnce([nativeCommand("current")]);
        await loadSkills({ harness: "codex", cwd: "/repo" });
        old.resolve([nativeCommand("old")]);
        await expect(oldLoad).resolves.toMatchObject([{ name: "current" }]);
        expect(peekSkills({ harness: "codex", cwd: "/repo" })).toMatchObject([
            { name: "current" },
        ]);
    });
});
