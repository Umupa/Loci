// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));
vi.mock("@tauri-apps/api/event", () => ({ listen: vi.fn(async () => () => undefined) }));

import { contentChangeEvents, hydrateMentors, mergeRoster, queueMentorRemoval, queueRosterSync, resetMentorStoreForTests, rosterSettled } from "./mentorStore";

const ROSTER = "loci:agent-roster";

describe("mentorStore", () => {
  beforeEach(() => {
    localStorage.clear();
    invoke.mockReset();
    resetMentorStoreForTests();
    (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {};
  });
  afterEach(() => {
    delete (window as unknown as Record<string, unknown>).__TAURI_INTERNALS__;
  });

  it("keeps entries this window has not sent yet and drops ones being removed", () => {
    const merged = mergeRoster(
      [{ id: "a", workdir: "/L/a" }, { id: "gone" }],
      [{ id: "a" }, { id: "new" }, { id: "other" }],
      new Set(["new"]),
      new Set(["gone"]),
    );
    expect(merged.map((entry) => entry.id)).toEqual(["a", "new"]);
  });

  it("hands the 0.3 roster to the migration, then loads the registry's roster", async () => {
    localStorage.setItem(ROSTER, JSON.stringify([{ id: "m1", name: "Old" }]));
    localStorage.setItem("loci:agent-overviews.v1", JSON.stringify({ m1: { chat: true } }));
    invoke.mockImplementation(async (command: string) => {
      if (command === "storage_migrate") return { mentors: [], done: true };
      if (command === "storage_status") return { ready: true };
      if (command === "mentors_load") return [{ id: "m1", name: "Old", workdir: "/L/old", folder: "/L/old", projects: [] }];
      if (command === "mentor_state_all") return { m2: { chat: false } };
      return undefined;
    });
    await hydrateMentors();
    expect(invoke).toHaveBeenCalledWith("storage_migrate", { input: { roster: [{ id: "m1", name: "Old" }], overviews: { m1: { chat: true } } } });
    expect(JSON.parse(localStorage.getItem(ROSTER)!)[0].folder).toBe("/L/old");
    expect(JSON.parse(localStorage.getItem("loci:agent-overviews.v1")!)).toEqual({ m1: { chat: true }, m2: { chat: false } });
  });

  it("leaves the saved roster in charge when the migration has not finished", async () => {
    localStorage.setItem(ROSTER, JSON.stringify([{ id: "m1" }]));
    invoke.mockImplementation(async (command: string) => {
      if (command === "storage_migrate") return { mentors: [{ id: "m1", error: "disk full" }], done: false };
      if (command === "storage_status") return { ready: false };
      if (command === "mentor_state_all") return {};
      throw new Error(`unexpected ${command}`);
    });
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    await hydrateMentors();
    expect(localStorage.getItem(ROSTER)).toBe(JSON.stringify([{ id: "m1" }]));
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it("coalesces roster changes into one call and takes back the new mentor's folder", async () => {
    invoke.mockImplementation(async (command: string, args: { roster?: { id: string }[] }) => {
      if (command === "storage_migrate") return { mentors: [], done: true };
      if (command === "storage_status") return { ready: true };
      if (command === "mentors_load") return [];
      if (command === "mentor_state_all") return {};
      if (command === "mentors_sync") return args.roster!.map((entry) => ({ ...entry, workdir: `/L/${entry.id}`, folder: `/L/${entry.id}` }));
      return undefined;
    });
    await hydrateMentors();
    invoke.mockClear();
    localStorage.setItem(ROSTER, JSON.stringify([{ id: "n1" }, { id: "n2" }]));
    queueRosterSync([{ id: "n1" }]);
    queueRosterSync([{ id: "n1" }, { id: "n2" }]);
    await rosterSettled();
    expect(invoke.mock.calls.filter(([command]) => command === "mentors_sync")).toHaveLength(1);
    expect(JSON.parse(localStorage.getItem(ROSTER)!).map((entry: { workdir: string }) => entry.workdir)).toEqual(["/L/n1", "/L/n2"]);
  });

  it("asks Rust to forget a removed mentor", async () => {
    invoke.mockResolvedValue(undefined);
    queueMentorRemoval("m1");
    await rosterSettled();
    expect(invoke).toHaveBeenCalledWith("mentors_remove", { id: "m1" });
  });

  it("turns a changed file into the refresh event the window already uses", () => {
    expect(contentChangeEvents({ agentId: "m", kind: "documents", id: "g" }).map((e) => e.type)).toEqual(["loci:agent-documents-changed"]);
    const [course] = contentChangeEvents({ agentId: "m", kind: "courses", id: "c" }) as CustomEvent[];
    expect([course.type, course.detail]).toEqual(["loci:courses-changed", { agentId: "m", courseId: "c" }]);
    expect(contentChangeEvents({ agentId: "m", kind: "notes" })[0].type).toBe("loci:notes-changed");
    expect(contentChangeEvents({ agentId: "m", kind: "canvases" })[0].type).toBe("loci-canvases-changed");
    expect(contentChangeEvents({ agentId: "m", kind: "files" })[0].type).toBe("loci:agent-files-changed");
    expect(contentChangeEvents({ agentId: null })).toHaveLength(4);
  });
});
