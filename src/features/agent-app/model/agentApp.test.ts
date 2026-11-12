// @vitest-environment happy-dom
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Note } from "../../notes";
import {
resetHarnessModelOverlays,
setHarnessModels,
} from "../../sessions/model/models";
import { newSession } from "../../sessions/model/session";
import { handleAgentApp,notePreview,type AgentAppHost } from "./agentApp";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../../integrations/harness/core/availability", () => ({
  isHarnessAvailable: (id: string) => id === "codex",
}));

const note: Note = {
  id: "n1",
  slug: "plan",
  title: "Plan",
  body: "First paragraph.\n\nSecond paragraph.\n\nThird paragraph should stay out of list.",
  tags: ["work"],
  slugPending: false,
  createdAt: 1,
  updatedAt: 2,
};

const storedValues = new Map<string, string>();
vi.stubGlobal("localStorage", {
  clear: () => storedValues.clear(),
  getItem: (key: string) => storedValues.get(key) ?? null,
  setItem: (key: string, value: string) => storedValues.set(key, value),
  removeItem: (key: string) => storedValues.delete(key),
});

beforeEach(() => {
  vi.mocked(invoke).mockReset();
  localStorage.clear();
  setHarnessModels("codex", [
    {
      id: "codex:test",
      harness: "codex",
      name: "Test model",
      settings: [
        {
          id: "effort",
          label: "Effort",
          kind: "select",
          value: "medium",
          options: [
            { value: "medium", label: "Medium" },
            { value: "high", label: "High" },
          ],
        },
      ],
    },
  ]);
});

afterEach(() => {
  resetHarnessModelOverlays();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function fixture() {
  const source = newSession("codex", "/tmp/project", "codex:test");
  source.id = "lead";
  const host: AgentAppHost = {
    start: vi.fn(async () => {}),
    sessions: vi.fn(async () => [
      {
        id: "other",
        title: "Other",
        harness: "codex",
        model: "codex:test",
        busy: false,
        hasDraft: false,
      },
    ]),
    session: vi.fn(async (id) =>
      id === "other" ? { ...newSession("codex", source.cwd), id } : null,
    ),
    send: vi.fn(async () => ({ alreadySubmitted: false })),
    draft: vi.fn(async () => ({ alreadySaved: false, draft: true })),
    notes: vi.fn(async () => [note]),
    note: vi.fn(async (id) => (id === note.id ? note : null)),
    saveNote: vi.fn(async (input) => ({ ...note, ...input })),
  };
  return { source, host };
}

describe("agent app commands", () => {
  it("reads a listed project session in bounded pages", async () => {
    const { source, host } = fixture();
    const result = await handleAgentApp(
      source,
      "read-1",
      "sessions.read",
      { sessionId: "other" },
      host,
    );
    expect(result).toMatchObject({ sessionId: "other", turns: [] });
    await expect(
      handleAgentApp(
        source,
        "read-2",
        "sessions.read",
        { sessionId: "missing" },
        host,
      ),
    ).rejects.toThrow("not found in this project");
  });

  it("sends a follow-up only to a listed idle session", async () => {
    const { source, host } = fixture();
    expect(
      await handleAgentApp(
        source,
        "send-1",
        "sessions.send",
        { sessionId: "other", prompt: "Continue the review" },
        host,
      ),
    ).toMatchObject({ sessionId: "other", submitted: true });
    expect(host.send).toHaveBeenCalledWith(
      "other",
      "Continue the review",
      "app-lead-send-1",
    );
    await expect(
      handleAgentApp(
        source,
        "send-2",
        "sessions.send",
        { sessionId: "lead", prompt: "loop" },
        host,
      ),
    ).rejects.toThrow("current conversation");
    await expect(
      handleAgentApp(
        source,
        "send-3",
        "sessions.send",
        { sessionId: "missing", prompt: "hello" },
        host,
      ),
    ).rejects.toThrow("not found in this project");
    expect(host.send).toHaveBeenCalledTimes(1);
  });

  it("saves an unsent draft in another listed project session", async () => {
    const { source, host } = fixture();
    expect(
      await handleAgentApp(
        source,
        "draft-1",
        "sessions.draft",
        { sessionId: "other", prompt: "Review this idea later" },
        host,
      ),
    ).toMatchObject({ sessionId: "other", saved: true, draft: true });
    expect(host.draft).toHaveBeenCalledWith(
      "other",
      "Review this idea later",
      "app-lead-draft-1",
    );
    await expect(
      handleAgentApp(
        source,
        "draft-2",
        "sessions.draft",
        { sessionId: "lead", prompt: "Not here" },
        host,
      ),
    ).rejects.toThrow("composer");
    await expect(
      handleAgentApp(
        source,
        "draft-3",
        "sessions.draft",
        { sessionId: "missing", prompt: "Not there" },
        host,
      ),
    ).rejects.toThrow("not found in this project");
    expect(host.draft).toHaveBeenCalledTimes(1);
  });

  it("starts a submitted tab with explicit model, effort, permissions and project", async () => {
    const { source, host } = fixture();
    const result = await handleAgentApp(
      source,
      "request-1",
      "sessions.start",
      {
        prompt: "Inspect the API",
        model: "codex:test",
        effort: "high",
        runtimeMode: "auto-accept-edits",
        reveal: true,
      },
      host,
    );
    expect(host.start).toHaveBeenCalledWith(
      expect.objectContaining({
        prompt: "Inspect the API",
        cwd: "/tmp/project",
        model: "codex:test",
        modelSettings: { effort: "high" },
        runtimeMode: "auto-accept-edits",
        reveal: true,
      }),
      "app-lead-request-1",
    );
    expect(result).toMatchObject({ id: "app-lead-request-1", submitted: true });
  });

  it("starts a pane beside the caller or another session in either direction", async () => {
    const { source, host } = fixture();
    await handleAgentApp(
      source,
      "right",
      "sessions.start",
      { prompt: "Inspect the API", placement: "right", draft: true },
      host,
    );
    expect(host.start).toHaveBeenLastCalledWith(
      expect.objectContaining({ draft: true }),
      "app-lead-right",
      { direction: "right", besideSessionId: "lead" },
    );
    await handleAgentApp(
      source,
      "down",
      "sessions.start",
      {
        prompt: "Review the UI",
        placement: "down",
        besideSessionId: "app-lead-right",
      },
      host,
    );
    expect(host.start).toHaveBeenLastCalledWith(
      expect.anything(),
      "app-lead-down",
      { direction: "down", besideSessionId: "app-lead-right" },
    );
  });

  it("rejects invalid pane placement before starting", async () => {
    const { source, host } = fixture();
    for (const input of [
      { prompt: "A", placement: "left" },
      { prompt: "A", besideSessionId: "other" },
      { prompt: "A", placement: "down", besideSessionId: 42 },
    ]) {
      await expect(
        handleAgentApp(source, "invalid", "sessions.start", input, host),
      ).rejects.toThrow();
    }
    expect(host.start).not.toHaveBeenCalled();
  });

  it("inherits the caller's permission mode unless start overrides it", async () => {
    const { source, host } = fixture();
    source.runtimeMode = "auto";
    await handleAgentApp(
      source,
      "inherited-mode",
      "sessions.start",
      { prompt: "Review this" },
      host,
    );
    expect(host.start).toHaveBeenLastCalledWith(
      expect.objectContaining({ runtimeMode: "auto" }),
      "app-lead-inherited-mode",
    );
    await handleAgentApp(
      source,
      "explicit-mode",
      "sessions.start",
      { prompt: "Review this", runtimeMode: "full-access" },
      host,
    );
    expect(host.start).toHaveBeenLastCalledWith(
      expect.objectContaining({ runtimeMode: "full-access" }),
      "app-lead-explicit-mode",
    );
    // A mentor that itself runs in Full access passes that on, too.
    source.runtimeMode = "full-access";
    await handleAgentApp(
      source,
      "inherited-full-access",
      "sessions.start",
      { prompt: "Review this" },
      host,
    );
    expect(host.start).toHaveBeenLastCalledWith(
      expect.objectContaining({ runtimeMode: "full-access" }),
      "app-lead-inherited-full-access",
    );
  });

  it("starts with an unsent draft", async () => {
    const { source, host } = fixture();
    const result = (await handleAgentApp(
      source,
      "draft-launch",
      "sessions.start",
      {
        prompt: "Test prompt",
        model: "codex:test",
        draft: true,
      },
      host,
    )) as { id: string; submitted: boolean; draft: boolean };
    expect(result).toMatchObject({
      id: "app-lead-draft-launch",
      submitted: false,
      draft: true,
    });
    expect(host.start).toHaveBeenCalledWith(
      expect.objectContaining({ prompt: "Test prompt", draft: true }),
      result.id,
    );
  });

  it("rejects invalid model settings before starting a session", async () => {
    const { source, host } = fixture();
    await expect(
      handleAgentApp(
        source,
        "bad",
        "sessions.start",
        {
          prompt: "Hello",
          effort: "ultra",
        },
        host,
      ),
    ).rejects.toThrow("Invalid model setting effort");
    expect(host.start).not.toHaveBeenCalled();
    await expect(
      handleAgentApp(
        source,
        "bad-draft",
        "sessions.start",
        { prompt: "Hello", draft: "true" },
        host,
      ),
    ).rejects.toThrow("draft must be a boolean");
    await expect(
      handleAgentApp(source, "unexpected", "toString", {}, host),
    ).rejects.toThrow("Unknown app action");
  });

  it("lists short note previews and reads one full note on request", async () => {
    const { source, host } = fixture();
    const listed = (await handleAgentApp(
      source,
      "list",
      "notes.list",
      {},
      host,
    )) as {
      notes: Array<{ preview: string; body?: string; url: string }>;
    };
    expect(listed.notes[0]?.preview).toBe(
      "First paragraph.\n\nSecond paragraph.",
    );
    expect(listed.notes[0]).not.toHaveProperty("body");
    expect(listed.notes[0].url).toBe("loci://note/n1");
    expect(notePreview("A".repeat(500))).toHaveLength(400);
    expect(
      await handleAgentApp(source, "read", "notes.read", { id: "n1" }, host),
    ).toMatchObject({ body: note.body, url: "loci://note/n1" });
  });

  it("creates a note with source metadata and reuses the same request ID safely", async () => {
    const { source, host } = fixture();
    let created: Note | null = null;
    host.note = vi.fn(async (id) => (id === created?.id ? created : null));
    host.saveNote = vi.fn(async (input) => {
      created = { ...note, ...input };
      return created;
    });
    const input = { body: "# Work plan\n\nNext steps", tags: ["#Work"] };
    const saved = await handleAgentApp(
      source,
      "create-1",
      "notes.write",
      input,
      host,
    );
    expect(saved).toMatchObject({
      id: "app-lead-create-1",
      url: "loci://note/app-lead-create-1",
      saved: true,
      title: "Work plan",
      body: input.body,
      tags: ["work"],
      sourceSessionId: source.id,
      sourceCwd: source.cwd,
    });
    expect(
      await handleAgentApp(source, "create-1", "notes.write", input, host),
    ).toEqual(saved);
    expect(host.saveNote).toHaveBeenCalledTimes(1);
    await expect(
      handleAgentApp(
        source,
        "create-1",
        "notes.write",
        {
          body: "Different body",
        },
        host,
      ),
    ).rejects.toThrow("Request ID was already used");
  });

  it("files an agent's note under the agent, not the folder its chat runs in", async () => {
    const { source, host } = fixture();
    host.agentOf = () => ({ id: "a", projects: [source.cwd] });
    host.saveNote = vi.fn(async (input) => ({ ...note, ...input }));
    const saved = await handleAgentApp(source, "agent-note", "notes.write", { body: "# Lab log" }, host);
    expect(saved).toMatchObject({ agentId: "a", sourceSessionId: source.id });
    expect(saved).not.toHaveProperty("sourceCwd");
  });

  it("returns working resource URLs for compound session and note IDs without failing after persistence", async () => {
    const { source, host } = fixture();
    source.id = `app-5bed7012-c8bc-445d-b95d-ead0f88e36a7-${"s".repeat(128)}`;
    const requestId = "n".repeat(128);
    let created: Note | null = null;
    host.note = vi.fn(async (id) => id === created?.id ? created : null);
    host.saveNote = vi.fn(async (input) => { created = { ...note, ...input }; return created; });
    const input = { title: "Long ID note", body: "Saved content" };
    const result = await handleAgentApp(source, requestId, "notes.write", input, host) as Note & { url: string; saved: boolean };
    expect(result.id.length).toBeGreaterThan(256);
    expect(result).toMatchObject({ saved: true, url: `loci://note/${result.id}` });
    expect(await handleAgentApp(source, requestId, "notes.write", input, host)).toEqual(result);
    expect(host.saveNote).toHaveBeenCalledTimes(1);
    host.notes = vi.fn(async () => [created!]);
    expect(await handleAgentApp(source, "list", "notes.list", {}, host)).toMatchObject({ notes: [{ id: result.id, url: result.url }] });
  });

  it("edits only supplied note fields and refuses missing or malformed notes", async () => {
    const { source, host } = fixture();
    const changed = await handleAgentApp(
      source,
      "edit-1",
      "notes.write",
      {
        id: "n1",
        body: "Updated body",
      },
      host,
    );
    expect(changed).toMatchObject({
      id: "n1",
      title: note.title,
      body: "Updated body",
      tags: note.tags,
      url: "loci://note/n1",
      saved: true,
    });
    expect(host.saveNote).toHaveBeenCalledWith({
      id: "n1",
      title: note.title,
      body: "Updated body",
      tags: note.tags,
    });
    await expect(
      handleAgentApp(
        source,
        "edit-2",
        "notes.write",
        {
          id: "missing",
          body: "x",
        },
        host,
      ),
    ).rejects.toThrow("Note was not found");
    await expect(
      handleAgentApp(
        source,
        "edit-3",
        "notes.write",
        {
          id: "n1",
        },
        host,
      ),
    ).rejects.toThrow("Supply title, body or tags");
    await expect(
      handleAgentApp(
        source,
        "edit-4",
        "notes.write",
        {
          id: "n1",
          tags: "work",
        },
        host,
      ),
    ).rejects.toThrow("tags must be an array");
    await expect(
      handleAgentApp(
        source,
        "create-2",
        "notes.write",
        {
          title: "Empty",
        },
        host,
      ),
    ).rejects.toThrow("body is required");
  });

  it("lets an agent name which of its projects an action works in", async () => {
    const { source, host } = fixture();
    source.cwd = "/home/me";
    host.agentOf = () => ({ id: "a", projects: ["/code/app", "/code/site"] });
    await expect(
      handleAgentApp(source, "r1", "sessions.list", {}, host),
    ).rejects.toThrow(
      'Pass "project" to choose one. Yours: app (/code/app), site (/code/site)',
    );
    await expect(
      handleAgentApp(source, "r2", "sessions.list", { project: "/code/other" }, host),
    ).rejects.toThrow("Not one of your projects");
    expect(
      await handleAgentApp(source, "r3", "sessions.list", { project: "site" }, host),
    ).toMatchObject({ cwd: "/code/site" });
    expect(host.sessions).toHaveBeenLastCalledWith("/code/site");
    expect(
      await handleAgentApp(source, "r4", "sessions.list", { project: "/code/app/" }, host),
    ).toMatchObject({ cwd: "/code/app" });
  });

  it("uses an agent's only project, and tells one with none where they come from", async () => {
    const { source, host } = fixture();
    source.cwd = "/home/me";
    host.agentOf = () => ({ id: "a", projects: ["/code/app"] });
    expect(
      await handleAgentApp(source, "r1", "sessions.list", {}, host),
    ).toMatchObject({ cwd: "/code/app" });
    host.agentOf = () => ({ id: "a", projects: [] });
    await expect(
      handleAgentApp(source, "r2", "sessions.list", {}, host),
    ).rejects.toThrow("none yet; your workdir is made on first use");
  });

  it("keeps project for agents, and a session read inside the chosen project", async () => {
    const { source, host } = fixture();
    await expect(
      handleAgentApp(source, "r1", "sessions.list", { project: "/tmp/project" }, host),
    ).rejects.toThrow("project is only for an agent");
    source.cwd = "/home/me";
    host.agentOf = () => ({ id: "a", projects: ["/code/app", "/tmp/project"] });
    host.session = vi.fn(async (id) => ({ ...newSession("codex", "/tmp/project"), id }));
    await expect(
      handleAgentApp(source, "r2", "sessions.read", { sessionId: "other", project: "app" }, host),
    ).rejects.toThrow("Session was not found in this project");
    expect(
      await handleAgentApp(source, "r3", "sessions.read", { sessionId: "other", project: "project" }, host),
    ).toMatchObject({ turns: [] });
  });

  it("lets an agent read its own chat, which is in none of its projects", async () => {
    const { source, host } = fixture();
    source.cwd = "/home/me";
    host.agentOf = () => ({ id: "a", projects: ["/code/app"], chatId: source.id });
    host.readAgentChat = vi.fn(async (chatId) => ({ sessionId: chatId, title: "", busy: false, hasDraft: false, turns: [], nextBefore: null }));
    expect(
      await handleAgentApp(source, "r1", "sessions.read", { sessionId: source.id, before: "u9", limit: 2 }, host),
    ).toMatchObject({ sessionId: source.id });
    expect(host.readAgentChat).toHaveBeenCalledWith(source.id, { before: "u9", limit: 2, maxChars: undefined });
    // Any other session still has to be in the project it names.
    await expect(
      handleAgentApp(source, "r2", "sessions.read", { sessionId: "elsewhere" }, host),
    ).rejects.toThrow();
  });

  it("lets an agent take the name it settled on with the user, in its own chat only", async () => {
    const { source, host } = fixture();
    const renameAgent = vi.fn();
    host.renameAgent = renameAgent;
    await expect(
      handleAgentApp(source, "r1", "agent.rename", { name: "Scout" }, host),
    ).rejects.toThrow("Only an agent's own conversation can rename it");
    host.agentOf = () => ({ id: "a", projects: [] });
    expect(
      await handleAgentApp(source, "r2", "agent.rename", { name: "  CI   Scout " }, host),
    ).toEqual({ name: "CI Scout" });
    expect(renameAgent).toHaveBeenCalledWith("a", { name: "CI Scout" });
    expect(
      await handleAgentApp(source, "r2b", "agent.rename", { name: "Scout", role: " CI  watcher " }, host),
    ).toEqual({ name: "Scout", role: "CI watcher" });
    expect(renameAgent).toHaveBeenLastCalledWith("a", { name: "Scout", role: "CI watcher" });
    await expect(
      handleAgentApp(source, "r3", "agent.rename", { name: "x".repeat(41) }, host),
    ).rejects.toThrow();
    host.agentOf = () => ({ id: "a", hiddenRun: true });
    await expect(
      handleAgentApp(source, "r4", "agent.rename", { name: "Scout" }, host),
    ).rejects.toThrow("Only an agent's own conversation can rename it");
  });
});
