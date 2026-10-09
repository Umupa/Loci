// @vitest-environment happy-dom
import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import {
  CANVASES_CHANGED_EVENT,
  invalidateCanvases,
  loadCanvases,
  peekCanvases,
  type Canvas,
  type CanvasUpsert,
} from "../../canvas/canvas";
import type { Note } from "../../notes";
import {
resetHarnessModelOverlays,
setHarnessModels,
} from "../../sessions/model/models";
import { newSession } from "../../sessions/model/session";
import {
loadSessionFolders,
saveSessionFolders,
} from "../../sessions/model/sessionFolders";
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
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", measureText: (text: string) => ({ width: text.length * 10 }) } as never);
  vi.mocked(invoke).mockReset();
  invalidateCanvases();
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
  it("refreshes and lists only current project canvas metadata, newest first", async () => {
    const { source, host } = fixture();
    const canvas: Canvas = {
      id: "old", title: "Old", dataJson: "private scene", tags: ["private"],
      cwd: source.cwd, createdAt: 1, updatedAt: 2,
    };
    vi.mocked(invoke).mockResolvedValueOnce([]).mockResolvedValueOnce([
      canvas,
      { ...canvas, id: "other", cwd: "/tmp/other", updatedAt: 100 },
      { ...canvas, id: "global", cwd: undefined },
      { ...canvas, id: "new", cwd: `${source.cwd}/`, updatedAt: 10 },
    ]);
    await loadCanvases();
    const result = await handleAgentApp(source, "list", "canvas.list", {}, host);
    expect(result).toEqual({
      cwd: source.cwd,
      canvases: [
        { id: "new", title: "Old", cwd: `${source.cwd}/`, createdAt: 1, updatedAt: 10, url: "loci://canvas/new" },
        { id: "old", title: "Old", cwd: source.cwd, createdAt: 1, updatedAt: 2, url: "loci://canvas/old" },
      ],
    });
    expect(invoke).toHaveBeenCalledTimes(2);
    expect(invoke).toHaveBeenLastCalledWith("canvas_list");
  });

  it("reads only canvas metadata and reports missing IDs", async () => {
    const { source, host } = fixture();
    vi.mocked(invoke).mockResolvedValueOnce({
      id: "drawing", title: "Plan", cwd: source.cwd, createdAt: 1, updatedAt: 2,
      dataJson: "private scene", tags: ["private"],
    }).mockResolvedValueOnce(null);
    expect(await handleAgentApp(source, "get", "canvas.get", { id: "drawing" }, host))
      .toEqual({ id: "drawing", title: "Plan", cwd: source.cwd, createdAt: 1, updatedAt: 2, url: "loci://canvas/drawing" });
    expect(invoke).toHaveBeenCalledWith("canvas_get", { id: "drawing" });
    await expect(handleAgentApp(source, "missing", "canvas.get", { id: "missing" }, host))
      .rejects.toThrow("Canvas was not found");
  });

  it("creates an empty project canvas, renames it without changing the scene, and deletes it", async () => {
    const { source, host } = fixture();
    const stored = new Map<string, Canvas>();
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_list") return [...stored.values()];
      if (command === "canvas_get") return stored.get((args as { id: string }).id) ?? null;
      if (command === "canvas_upsert") {
        const input = (args as { canvas: CanvasUpsert }).canvas;
        const saved = { ...input, createdAt: 1, updatedAt: 2 };
        stored.set(saved.id, saved);
        return saved;
      }
      if (command === "canvas_delete") {
        stored.delete((args as { id: string }).id);
        return;
      }
      throw new Error(`Unexpected command: ${command}`);
    });
    await loadCanvases();
    const changed = vi.fn();
    window.addEventListener(CANVASES_CHANGED_EVENT, changed);
    try {
      const created = await handleAgentApp(source, "create", "canvas.create", { title: "测试画布" }, host) as { id: string; title: string };
      expect(created).toEqual({ id: expect.any(String), title: "测试画布", url: `loci://canvas/${created.id}`, saved: true });
      const canvas = stored.get(created.id)!;
      expect(canvas.cwd).toBe(source.cwd);
      expect(JSON.parse(canvas.dataJson)).toEqual({ elements: [], appState: {}, files: {} });
      expect(peekCanvases()).toEqual([canvas]);
      expect(await handleAgentApp(source, "create", "canvas.create", { title: "测试画布" }, host)).toEqual(created);
      expect(stored.size).toBe(1);
      // An existing drawing's scene must survive a management rename.
      canvas.dataJson = "existing scene";
      expect(await handleAgentApp(source, "rename", "canvas.rename", { id: created.id, title: "新标题" }, host))
        .toEqual({ title: "新标题", url: `loci://canvas/${created.id}`, saved: true });
      expect(stored.get(created.id)).toMatchObject({ title: "新标题", dataJson: "existing scene" });
      expect(peekCanvases()?.[0].title).toBe("新标题");
      expect(await handleAgentApp(source, "delete", "canvas.delete", { id: created.id }, host))
        .toEqual({ deleted: true });
      expect(stored.has(created.id)).toBe(false);
      expect(peekCanvases()).toEqual([]);
      expect(changed).toHaveBeenCalledTimes(3);
      expect(await handleAgentApp(source, "default", "canvas.create", {}, host))
        .toMatchObject({ id: expect.any(String), title: "Untitled drawing", url: expect.stringMatching(/^loci:\/\/canvas\//), saved: true });
      await expect(handleAgentApp(source, "missing", "canvas.rename", { id: "missing", title: "Title" }, host))
        .rejects.toThrow("Canvas was not found");
    } finally {
      window.removeEventListener(CANVASES_CHANGED_EVENT, changed);
    }
  });

  it("reads and writes canvas scene data", async () => {
    const { source, host } = fixture();
    const stored = new Map<string, Canvas>();
    vi.mocked(invoke).mockImplementation(async (command, args) => {
      if (command === "canvas_list") return [...stored.values()];
      if (command === "canvas_get") return stored.get((args as { id: string }).id) ?? null;
      if (command === "canvas_upsert") {
        const input = (args as { canvas: CanvasUpsert }).canvas;
        const saved = { ...input, createdAt: 1, updatedAt: 2 };
        stored.set(saved.id, saved);
        return saved;
      }
      throw new Error(`Unexpected command: ${command}`);
    });
    await loadCanvases();
    const changed = vi.fn();
    window.addEventListener(CANVASES_CHANGED_EVENT, changed);
    try {
      const created = await handleAgentApp(source, "create", "canvas.create", { title: "Scene test" }, host) as { id: string };
      const initialData = await handleAgentApp(source, "read", "canvas.read-data", { id: created.id }, host) as { id: string; title: string; dataJson: string };
      expect(initialData.id).toBe(created.id);
      expect(initialData.title).toBe("Scene test");
      expect(JSON.parse(initialData.dataJson)).toMatchObject({ elements: [] });

      const newScene = JSON.stringify({ elements: [{ type: "text", text: "Hello", x: 0, y: 0 }], appState: {}, files: {} });
      expect(await handleAgentApp(source, "write", "canvas.write-data", { id: created.id, dataJson: newScene }, host))
        .toEqual({ updated: true, url: `loci://canvas/${created.id}`, saved: true });
      const updated = await handleAgentApp(source, "read2", "canvas.read-data", { id: created.id }, host) as { dataJson: string };
      expect(JSON.parse(updated.dataJson)).toMatchObject({ elements: [{ type: "text", text: "Hello" }] });
      expect(changed).toHaveBeenCalledTimes(2);

      await expect(handleAgentApp(source, "missing", "canvas.read-data", { id: "missing" }, host))
        .rejects.toThrow("Canvas was not found");
      await expect(handleAgentApp(source, "missing", "canvas.write-data", { id: "missing", dataJson: newScene }, host))
        .rejects.toThrow("Canvas was not found");
      await expect(handleAgentApp(source, "bad-json", "canvas.write-data", { id: created.id, dataJson: "{invalid" }, host))
        .rejects.toThrow("valid JSON");
    } finally {
      window.removeEventListener(CANVASES_CHANGED_EVENT, changed);
    }
  });

  it.each(["canvas.get", "canvas.rename", "canvas.delete", "canvas.read-data", "canvas.write-data"])("rejects %s in another project", async (action) => {
    const { source, host } = fixture();
    vi.mocked(invoke).mockResolvedValue({ id: "other", cwd: "/tmp/other" });
    await expect(handleAgentApp(source, "other", action, { id: "other", ...(action === "canvas.rename" ? { title: "Changed" } : {}), ...(action === "canvas.write-data" ? { dataJson: '{"elements":[]}' } : {}) }, host))
      .rejects.toThrow("not found in this project");
    expect(vi.mocked(invoke).mock.calls.every(([command]) => command === "canvas_get")).toBe(true);
  });

  it.each(["null", "[]", "{}", '{"elements":{}}', '{"elements":[{"type":"cameraUpdate","x":0,"y":0}]}'])("rejects invalid scene %s before storage", async (dataJson) => {
    const { source, host } = fixture();
    await expect(handleAgentApp(source, "invalid", "canvas.write-data", { id: "drawing", dataJson }, host)).rejects.toThrow();
    expect(invoke).not.toHaveBeenCalled();
  });

  it("reports persistence failure without announcing a scene replacement", async () => {
    const { source, host } = fixture();
    const existing = { id: "drawing", title: "Plan", cwd: source.cwd, dataJson: '{"elements":[]}', tags: [] };
    vi.mocked(invoke).mockResolvedValueOnce(existing).mockResolvedValueOnce(existing).mockRejectedValueOnce(new Error("disk full"));
    const replaced = vi.fn();
    window.addEventListener("loci-canvas-scene-replaced", replaced);
    try {
      await expect(handleAgentApp(source, "failure", "canvas.write-data", { id: "drawing", dataJson: '{"elements":[]}' }, host)).rejects.toThrow("disk full");
      expect(replaced).not.toHaveBeenCalled();
    } finally { window.removeEventListener("loci-canvas-scene-replaced", replaced); }
  });

  it("rejects unsupported canvas fields and invalid metadata before invoking storage", async () => {
    const { source, host } = fixture();
    for (const [action, input] of [
      ["canvas.list", { cwd: "/tmp/other" }],
      ["canvas.get", {}],
      ["canvas.create", { dataJson: "scene" }],
      ["canvas.create", { title: " " }],
      ["canvas.rename", { id: "drawing", title: "x".repeat(201) }],
      ["canvas.rename", { id: "drawing" }],
      ["canvas.delete", { id: 42 }],
      ["canvas.read-data", {}],
      ["canvas.write-data", { id: "drawing" }],
      ["canvas.write-data", { id: "drawing", dataJson: 42 }],
    ] as Array<[string, Record<string, unknown>]>) {
      await expect(handleAgentApp(source, "invalid", action, input, host)).rejects.toThrow();
    }
    source.cwd = "";
    for (const action of ["canvas.list", "canvas.create"]) {
      await expect(handleAgentApp(source, "no-project", action, {}, host))
        .rejects.toThrow("Choose a project folder");
    }
    expect(invoke).not.toHaveBeenCalled();
  });

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

  it("does not let app-supplied prompts enable Operator in another session", async () => {
    const { source, host } = fixture();
    for (const action of [
      "sessions.send",
      "sessions.draft",
      "sessions.start",
    ]) {
      for (const prompt of [
        "/operator list notes",
        "  /OPERATOR list notes",
      ]) {
        await expect(
          handleAgentApp(
            source,
            "blocked",
            action,
            action === "sessions.start"
              ? { prompt }
              : { sessionId: "other", prompt },
            host,
          ),
        ).rejects.toThrow("cannot enable /operator");
      }
    }
    expect(host.send).not.toHaveBeenCalled();
    expect(host.draft).not.toHaveBeenCalled();
    expect(host.start).not.toHaveBeenCalled();

    await handleAgentApp(
      source,
      "ordinary",
      "sessions.send",
      { sessionId: "other", prompt: "Explain the /operator command" },
      host,
    );
    expect(host.send).toHaveBeenCalledOnce();
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
  });

  it("starts with an unsent draft and can immediately move the new session into a folder", async () => {
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
    host.sessions = vi.fn(async () => [
      {
        id: result.id,
        title: "Test prompt",
        harness: "codex",
        model: "codex:test",
        busy: false,
        hasDraft: true,
      },
    ]);
    const moved = await handleAgentApp(
      source,
      "folder",
      "folders.move",
      { sessionId: result.id, newFolderName: "test" },
      host,
    );
    expect(moved).toMatchObject({ sessionId: result.id, folderName: "test" });
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

  it("moves an existing project session into a sidebar folder", async () => {
    const { source, host } = fixture();
    saveSessionFolders(source.cwd, [
      {
        id: "folder-1",
        name: "Research",
        sessionIds: ["lead"],
        collapsed: false,
      },
    ]);
    expect(
      await handleAgentApp(
        source,
        "move",
        "folders.move",
        {
          sessionId: "other",
          folderId: "folder-1",
        },
        host,
      ),
    ).toMatchObject({ folderId: "folder-1", sessionId: "other" });
    expect(loadSessionFolders(source.cwd)[0]?.sessionIds).toEqual([
      "lead",
      "other",
    ]);
  });

  it("creates a folder during a move and rejects unknown sessions", async () => {
    const { source, host } = fixture();
    await expect(
      handleAgentApp(
        source,
        "bad-move",
        "folders.move",
        {
          sessionId: "missing",
          newFolderName: "Research",
        },
        host,
      ),
    ).rejects.toThrow("Session was not found");
    const moved = (await handleAgentApp(
      source,
      "new-folder",
      "folders.move",
      {
        sessionId: "other",
        newFolderName: "Research",
      },
      host,
    )) as { folderId: string; folderName: string };
    expect(moved.folderName).toBe("Research");
    expect(loadSessionFolders(source.cwd)[0]).toMatchObject({
      id: moved.folderId,
      sessionIds: ["other"],
    });
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
    ).rejects.toThrow("none yet; the user adds them from your details panel");
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
});
