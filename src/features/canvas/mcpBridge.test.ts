// @vitest-environment happy-dom
// The real stack below the UI: an MCP client talks JSON-RPC to the bridge
// process, which runs the vendored official Excalidraw server; its checkpoint
// store reaches the production canvas handler over the control socket's line
// protocol. Only the Tauri window and SQLite are replaced, by the store below.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createServer, type AddressInfo, type Server } from "node:net";
import path from "node:path";
import { createInterface } from "node:readline";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import type { Session } from "../sessions/model/session";
import { canvasSceneDrafts, invalidateCanvases, type Canvas, type CanvasUpsert } from "./canvas";
import { handleCanvasBridge } from "./checkpoints";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

type El = Record<string, any>;
const resources = path.resolve(__dirname, "../../../src-tauri/resources/excalidraw-mcp");
const TOKEN = "session-token";
const session = { id: "session-1", cwd: "/work/app" } as Session;

/** The canvas commands of `canvas.rs`, with the same checkpoint rules. */
function canvasStore() {
  const canvases = new Map<string, Canvas>();
  const checkpoints = new Map<string, { canvasId: string; baselineJson: string; createdAt: number }>();
  let clock = 0;
  const commands: Record<string, (args: any) => unknown> = {
    canvas_list: () => [...canvases.values()],
    canvas_get: ({ id }) => canvases.get(id) ?? null,
    canvas_upsert: ({ canvas }: { canvas: CanvasUpsert }) => {
      const { checkpoint, expectedUpdatedAt, ...fields } = canvas;
      const previous = canvases.get(fields.id);
      if (expectedUpdatedAt !== undefined && (!previous || previous.updatedAt !== expectedUpdatedAt))
        throw new Error("Canvas changed since it was read; retry the update.");
      const owner = checkpoint && checkpoints.get(checkpoint.id);
      if (owner && owner.canvasId !== fields.id) throw new Error("Checkpoint already belongs to another drawing");
      const saved: Canvas = { ...fields, createdAt: canvases.get(fields.id)?.createdAt ?? ++clock, updatedAt: ++clock };
      canvases.set(saved.id, saved);
      if (checkpoint) {
        for (const entry of checkpoints.values()) if (entry.canvasId === saved.id) entry.baselineJson = "";
        checkpoints.set(checkpoint.id, { canvasId: saved.id, baselineJson: checkpoint.baselineJson, createdAt: ++clock });
      }
      return saved;
    },
    canvas_delete: ({ id }) => { canvases.delete(id); for (const [key, entry] of checkpoints) if (entry.canvasId === id) checkpoints.delete(key); },
    canvas_checkpoint_canvas: ({ checkpointId }) => checkpoints.get(checkpointId)?.canvasId ?? (canvases.has(checkpointId) ? checkpointId : null),
    canvas_checkpoint_latest: ({ canvasId }) => {
      const [latest] = [...checkpoints].filter(([, entry]) => entry.canvasId === canvasId).sort((a, b) => b[1].createdAt - a[1].createdAt);
      return latest ? { checkpointId: latest[0], ...latest[1] } : null;
    },
  };
  return { canvases, checkpoints, run: async (command: string, args: unknown) => {
    if (!commands[command]) throw new Error(`Unexpected command ${command}`);
    return structuredClone(commands[command](args));
  } };
}

let store: ReturnType<typeof canvasStore>;
let control: Server;
let endpoint: string;
let source: Session = session;
const host = { isOpen: vi.fn((_: string) => false), reveal: vi.fn() };
const requests: Array<{ namespace: string; action: string; input: El }> = [];
/** Lets a test hold one request to prove calls are not mixed up. */
let gate: ((action: string, input: El) => Promise<void>) | undefined;

beforeAll(async () => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", font: "20px sans-serif",
    measureText(text: string) { return { width: text.length * (parseFloat(this.font) || 20) * 0.5 }; } } as never);
  // What `control.rs` does for the `canvas` namespace: one JSON line in, one out.
  control = createServer((socket) => {
    createInterface({ input: socket }).once("line", (line) => {
      const request = JSON.parse(line);
      const reply = (response: object) => socket.end(`${JSON.stringify(response)}\n`);
      if (request.token !== TOKEN) return reply({ ok: false, error: "Connection revoked or unauthorized" });
      requests.push({ namespace: request.namespace, action: request.action, input: request.input });
      void (gate?.(request.action, request.input) ?? Promise.resolve())
        .then(() => handleCanvasBridge(source, request.action, request.input, host))
        .then((result) => reply({ ok: true, result }), (error: Error) => reply({ ok: false, error: error.message }));
    });
  });
  await new Promise<void>((resolve) => control.listen(0, "127.0.0.1", resolve));
  endpoint = `127.0.0.1:${(control.address() as AddressInfo).port}`;
});
afterAll(() => { control.close(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const clients: ChildProcessWithoutNullStreams[] = [];
beforeEach(() => {
  store = canvasStore();
  source = session;
  gate = undefined;
  requests.length = 0;
  host.isOpen.mockReset().mockReturnValue(false);
  host.reveal.mockReset();
  invalidateCanvases();
  vi.mocked(invoke).mockImplementation((command, args) => store.run(command, args) as never);
});
afterEach(() => { for (const child of clients.splice(0)) child.kill(); canvasSceneDrafts.clear(); });

/** An agent CLI's MCP client, connected to a fresh bridge process. */
async function connect(env: Record<string, string> = { LOCI_APP_ENDPOINT: endpoint, LOCI_APP_TOKEN: TOKEN }) {
  const { LOCI_APP_ENDPOINT: _endpoint, LOCI_APP_TOKEN: _token, ...inherited } = process.env;
  const child = spawn(process.execPath, [path.join(resources, "loci-bridge.mjs")], { env: { ...inherited, ...env } });
  clients.push(child);
  const waiting = new Map<number, (message: El) => void>();
  let nextId = 0;
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  createInterface({ input: child.stdout }).on("line", (line) => {
    const message = JSON.parse(line);
    waiting.get(message.id)?.(message);
    waiting.delete(message.id);
  });
  const request = (method: string, params?: object) => new Promise<El>((resolve, reject) => {
    const id = ++nextId;
    const timer = setTimeout(() => reject(new Error(`${method} timed out. ${stderr}`)), 30_000);
    waiting.set(id, (message) => { clearTimeout(timer); message.error ? reject(new Error(message.error.message)) : resolve(message.result); });
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
  const initialized = await request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test-agent", version: "1" } });
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
  const tool = async (name: string, args: object = {}) => {
    const result = await request("tools/call", { name, arguments: args });
    return { text: result.content.filter((entry: El) => entry.type === "text").map((entry: El) => entry.text).join("\n") as string, isError: result.isError === true, checkpointId: result.structuredContent?.checkpointId as string | undefined, receipt: result.structuredContent as El | undefined };
  };
  return { initialized, request, tool, draw: (elements: object[]) => tool("create_view", { elements: JSON.stringify(elements) }) };
}

const drawing = () => { expect(store.canvases.size).toBe(1); return [...store.canvases.values()][0]; };
const scene = (canvas: Canvas) => JSON.parse(canvas.dataJson) as { elements: El[]; appState: El; files: El };
const byId = (elements: El[], id: string) => elements.find((element) => element.id === id)!;
const live = (elements: El[]) => elements.filter((element) => !element.isDeleted);

// The reference's own example: two labeled boxes joined by a bound arrow.
const firstCall = [
  { type: "cameraUpdate", width: 800, height: 600, x: 50, y: 50 },
  { type: "text", id: "title", x: 280, y: 40, text: "Checkout flow", fontSize: 28 },
  { type: "rectangle", id: "b1", x: 100, y: 100, width: 200, height: 100, roundness: { type: 3 }, backgroundColor: "#a5d8ff", fillStyle: "solid", label: { text: "Start", fontSize: 20 } },
  { type: "rectangle", id: "b2", x: 450, y: 100, width: 200, height: 100, roundness: { type: 3 }, backgroundColor: "#b2f2bb", fillStyle: "solid", label: { text: "End", fontSize: 20 } },
  { type: "arrow", id: "a1", x: 300, y: 150, width: 150, height: 0, points: [[0, 0], [150, 0]], endArrowhead: "arrow", startBinding: { elementId: "b1", fixedPoint: [1, 0.5] }, endBinding: { elementId: "b2", fixedPoint: [0, 0.5] } },
];

/** What saving from the canvas pane does after a person edits the drawing. */
async function editByHand(change: (data: { elements: El[]; appState: El; files: El }) => void) {
  const { restoreElements } = await import("@excalidraw/excalidraw");
  const canvas = drawing();
  const data = scene(canvas);
  change(data);
  // The editor keeps every element complete, with an order key.
  data.elements = restoreElements(data.elements as never, null) as El[];
  await store.run("canvas_upsert", { canvas: { ...canvas, dataJson: JSON.stringify(data) } });
}
const native = (element: El) => ({ version: 2, versionNonce: 9, seed: 3, updated: 1, isDeleted: false, groupIds: [], boundElements: null, link: null, locked: false, angle: 0, index: null,
  strokeColor: "#1e1e1e", backgroundColor: "transparent", fillStyle: "solid", strokeWidth: 2, strokeStyle: "solid", roughness: 1, opacity: 100, roundness: null, frameId: null, ...element });

describe("the vendored official server", () => {
  it("is byte-for-byte the pinned release", () => {
    const recorded = readFileSync(path.join(resources, "SOURCE"), "utf8");
    const files = [...recorded.matchAll(/^sha256 ([0-9a-f]{64}) {2}(official\/\S+)$/gm)];
    expect(files.map((match) => match[2]).sort()).toEqual(["official/manifest.json", "official/mcp-app.html", "official/server.js"]);
    for (const [, hash, file] of files)
      expect(createHash("sha256").update(readFileSync(path.join(resources, file))).digest("hex"), file).toBe(hash);
    expect(JSON.parse(readFileSync(path.join(resources, "official/manifest.json"), "utf8")).version).toBe(recorded.match(/^Version: (\S+)$/m)![1]);
  });

  it("describes local persistence in tools and results without initialization instructions", async () => {
    const agent = await connect();
    expect(agent.initialized.serverInfo).toEqual({ name: "Excalidraw", version: "1.0.0" });
    expect(agent.initialized.instructions).toBeUndefined();
    const { tools } = await agent.request("tools/list");
    expect(tools.map((tool: El) => tool.name)).toEqual(["read_me", "create_view", "save_checkpoint", "read_checkpoint", "get_elements", "update_elements", "read_widget_context"]);
    const createView = byId(tools.map((tool: El) => ({ ...tool, id: tool.name })), "create_view");
    expect(createView).toMatchObject({ title: "Draw and Save Loci Canvas", annotations: { readOnlyHint: false }, _meta: { ui: { resourceUri: "ui://excalidraw/mcp-app.html" } } });
    expect(createView.description).toContain("Every create_view call saves a drawing");
    expect(createView.description).toContain("get_elements returns exact native properties");
    for (const tool of tools) {
      expect(tool.description).not.toContain("Use this tool by default");
      expect(tool.description).not.toContain("preferred way");
      expect(tool.description).not.toContain("include the returned canvas link in your reply");
    }
    expect(Object.keys(createView.inputSchema.properties)).toEqual(["elements"]);
    // Tools the official widget calls stay hidden from models, as upstream marks them.
    for (const name of ["save_checkpoint", "read_checkpoint"])
      expect(tools.find((tool: El) => tool.name === name)._meta.ui.visibility).toEqual(["app"]);
    // Upstream's upload to excalidraw.com is not offered: drawings stay on this machine.
    const upload = await agent.tool("export_to_excalidraw", { json: '{"elements":[]}' });
    expect(upload).toMatchObject({ isError: true, text: "Loci does not upload drawings to excalidraw.com." });
    expect(tools.find((tool: El) => tool.name === "update_elements")).toMatchObject({ annotations: { readOnlyHint: false } });
    expect(tools.find((tool: El) => tool.name === "get_elements")).toMatchObject({ annotations: { readOnlyHint: true } });
    expect(tools.at(-1)).toMatchObject({ name: "read_widget_context", annotations: { readOnlyHint: true } });
    const reference = await agent.tool("read_me");
    expect(reference.text).toContain("# Excalidraw Element Format");
    expect(reference.text).toContain("restoreCheckpoint");
    expect(reference.text).toContain("get_elements");
    expect(reference.text).toContain("update_elements");
    expect(reference.text).not.toContain("Use this tool by default");
    expect(reference.text).not.toContain("include the returned canvas link in your reply");
    // The reference needs no Loci connection.
    expect(requests).toEqual([]);
    const widget = await agent.request("resources/read", { uri: "ui://excalidraw/mcp-app.html" });
    expect(widget.contents[0].text.length).toBeGreaterThan(100_000);
  });
});

describe("an agent drawing on Loci canvases through the official MCP", () => {
  it("preserves concept metadata through create_view, element edits and checkpoint continuation", async () => {
    const agent = await connect();
    const customData = { type: "concept", courseId: "kubernetes", conceptId: "pod", agentId: "teacher" };
    const first = await agent.draw([{ type: "rectangle", id: "pod", x: 20, y: 40, width: 160, height: 80,
      backgroundColor: "#f4f4f5", customData, label: { text: "Pod" } }]);
    expect(first.isError).toBe(false);
    expect(byId(scene(drawing()).elements, "pod").customData).toEqual(customData);
    const read = await agent.request("tools/call", { name: "get_elements", arguments: { checkpointId: first.checkpointId } });
    expect(byId(read.structuredContent.elements, "pod").customData).toEqual(customData);
    const updated = await agent.request("tools/call", { name: "update_elements", arguments: {
      checkpointId: first.checkpointId, expectedRevision: read.structuredContent.revision,
      updates: [{ id: "pod", changes: { backgroundColor: "#dcfce7" } }],
    } });
    expect(updated.isError).not.toBe(true);
    const next = await agent.draw([{ type: "restoreCheckpoint", id: first.checkpointId },
      { type: "rectangle", id: "service", x: 240, y: 40, width: 160, height: 80,
        customData: { ...customData, conceptId: "service" }, label: { text: "Service" } }]);
    expect(next.isError).toBe(false);
    expect(byId(scene(drawing()).elements, "pod")).toMatchObject({ customData, backgroundColor: "#dcfce7" });
    expect(byId(scene(drawing()).elements, "service").customData).toEqual({ ...customData, conceptId: "service" });
  });

  it("creates a canvas, sees the user's manual edits, continues from them, and resumes after a restart", async () => {
    const agent = await connect();
    const first = await agent.draw(firstCall);
    expect(first.isError).toBe(false);
    expect(first.text).toContain(`Checkpoint id: "${first.checkpointId}"`);
    const created = drawing();
    expect(created).toMatchObject({ title: "Checkout flow", cwd: "/work/app" });
    expect(first.receipt).toMatchObject({ canvasId: created.id, title: created.title, url: `loci://canvas/${created.id}`, saved: true });
    expect(first.text.startsWith(`Saved to Loci: [Checkout flow](loci://canvas/${created.id})`)).toBe(true);
    expect(first.text).not.toContain("Include this link in your reply");
    expect(host.reveal).toHaveBeenCalledWith(created.id, "session-1");
    expect(requests).toEqual([{ namespace: "canvas", action: "checkpoint.save", input: { id: first.checkpointId, elements: firstCall } }]);
    expect(byId(scene(created).elements, "a1")).toMatchObject({ startBinding: { elementId: "b1" }, endBinding: { elementId: "b2" } });
    expect(live(scene(created).elements).map((element) => element.type).sort()).toEqual(["arrow", "rectangle", "rectangle", "text", "text", "text"]);

    // The user moves a box, retypes a label in another font, and adds an image inside a frame.
    const photo = { id: "photo", dataURL: "data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png", created: 1 };
    let endLabel = "";
    await editByHand((data) => {
      Object.assign(byId(data.elements, "b2"), { x: 520, y: 260, version: 9 });
      const label = data.elements.find((element) => element.containerId === "b2")!;
      endLabel = label.id;
      Object.assign(label, { text: "Paid", originalText: "Paid", fontFamily: 3, version: 9 });
      data.elements.push(
        native({ id: "zone", type: "frame", x: 60, y: 380, width: 300, height: 200, name: "Assets" }),
        native({ id: "logo", type: "image", x: 80, y: 400, width: 64, height: 64, fileId: "photo", status: "saved", scale: [1, 1], crop: null, frameId: "zone" }),
        native({ id: "mine", type: "ellipse", x: 420, y: 420, width: 140, height: 90, backgroundColor: "#ffc9c9" }),
      );
      data.files.photo = photo;
      data.appState.viewBackgroundColor = "#fff9db";
    });

    const context = await agent.tool("read_widget_context", { checkpointId: first.checkpointId });
    expect(context.isError).toBe(false);
    expect(context.text).toContain(`User edited diagram (checkpoint: ${first.checkpointId}).`);
    expect(context.text).toContain('ellipse "" at (420,420) id mine');
    expect(context.text).toContain("Moved/resized: b2 → (520,260) 200x100");
    expect(context.text).toContain(`Text changed: ${endLabel} "Paid"`);
    expect(context.text).toContain(`{"type":"restoreCheckpoint","id":"${first.checkpointId}"}`);
    expect(context.text).toContain("1 image file(s)");
    const listed = JSON.parse(context.text.slice(context.text.indexOf("Current elements:\n") + 18)) as El[];
    expect(byId(listed, "mine")).toMatchObject({ type: "ellipse", x: 420, y: 420, backgroundColor: "#ffc9c9" });
    expect(byId(listed, "logo")).toMatchObject({ type: "image", fileId: "photo", frameId: "zone" });
    expect(context.text).not.toContain("base64");

    // The agent continues: it connects to the user's own shape and removes its old arrow.
    host.isOpen.mockReturnValue(true);
    host.reveal.mockClear();
    const before = scene(drawing());
    const second = await agent.draw([
      { type: "restoreCheckpoint", id: first.checkpointId },
      { type: "delete", ids: "a1" },
      { type: "rectangle", id: "b3", x: 100, y: 260, width: 200, height: 100, label: { text: "Review", fontSize: 20 } },
      { type: "arrow", id: "a2", x: 300, y: 310, width: 120, height: 150, points: [[0, 0], [120, 150]], startBinding: { elementId: "b3", fixedPoint: [1, 0.5] }, endBinding: { elementId: "mine", fixedPoint: [0, 0.5] } },
      { type: "cameraUpdate", width: 800, height: 600, x: 40, y: 40 },
    ]);
    expect(second.isError).toBe(false);
    expect(second.checkpointId).not.toBe(first.checkpointId);
    const after = scene(drawing());
    // The same canvas, patched: nothing the user did was rebuilt or lost.
    expect(drawing().id).toBe(created.id);
    // The window decides whether its pane needs to move beside this session.
    expect(host.reveal).toHaveBeenCalledWith(created.id, "session-1");
    for (const id of ["zone", "logo", endLabel, "title"]) expect(byId(after.elements, id)).toEqual(byId(before.elements, id));
    // The moved box only lost its link to the arrow the agent deleted.
    expect(byId(after.elements, "b2")).toMatchObject({ x: 520, y: 260, backgroundColor: "#b2f2bb" });
    expect(byId(after.elements, endLabel)).toMatchObject({ text: "Paid", fontFamily: 3, containerId: "b2" });
    expect(after.files).toEqual({ photo });
    expect(after.appState.viewBackgroundColor).toBe("#fff9db");
    expect(byId(after.elements, "a1").isDeleted).toBe(true);
    expect(byId(after.elements, "a2")).toMatchObject({ startBinding: { elementId: "b3" }, endBinding: { elementId: "mine" } });
    expect(byId(after.elements, "mine")).toMatchObject({ backgroundColor: "#ffc9c9", boundElements: [{ id: "a2", type: "arrow" }] });
    expect(byId(after.elements, "b2").boundElements.some((entry: El) => entry.id === "a1")).toBe(false);
    // Only the difference crossed the wire, so the patch applied to the live scene.
    expect(requests.at(-1)).toMatchObject({ action: "checkpoint.save", input: { id: second.checkpointId, baseId: first.checkpointId, deletedIds: ["a1"] } });
    expect(requests.at(-1)!.input.elements.map((element: El) => element.id ?? element.type)).toEqual(["b3", "a2", "cameraUpdate"]);
    expect((await agent.tool("read_widget_context", { checkpointId: second.checkpointId })).text).toContain("No changes detected in the saved edit baseline");

    // Loci and the agent CLI restart: a new server process, the same stored canvas.
    const resumed = await connect();
    const third = await resumed.draw([{ type: "restoreCheckpoint", id: second.checkpointId }, { type: "text", id: "footer", x: 100, y: 620, text: "v2", fontSize: 16 }]);
    expect(third.isError).toBe(false);
    expect(drawing().id).toBe(created.id);
    // An id from before the user's edits still means the drawing as it is now.
    const fourth = await resumed.draw([{ type: "restoreCheckpoint", id: first.checkpointId }, { type: "delete", ids: "footer" }]);
    expect(fourth.isError).toBe(false);
    const final = scene(drawing());
    expect(byId(final.elements, "footer").isDeleted).toBe(true);
    expect(live(final.elements).map((element) => element.id)).toEqual(expect.arrayContaining(["title", "b1", "b2", "b3", "a2", "mine", "logo", "zone"]));
    expect(final.files).toEqual({ photo });
    for (const id of [first.checkpointId, second.checkpointId, third.checkpointId, fourth.checkpointId, created.id])
      expect(await store.run("canvas_checkpoint_canvas", { checkpointId: id })).toBe(created.id);
  });

  it("continues a drawing the user made by hand, found through the host tool", async () => {
    await store.run("canvas_upsert", { canvas: { id: "hand-made", title: "Sketch", tags: [], cwd: "/work/app",
      dataJson: JSON.stringify({ elements: [native({ id: "box", type: "rectangle", x: 0, y: 0, width: 120, height: 60 })], appState: {}, files: {} }) } });
    await store.run("canvas_upsert", { canvas: { id: "elsewhere", title: "Other project", tags: [], cwd: "/work/other", dataJson: '{"elements":[]}' } });
    const agent = await connect();
    const list = await agent.tool("read_widget_context");
    expect(JSON.parse(list.text.slice(list.text.indexOf("\n") + 1))).toEqual([{ checkpointId: "hand-made", title: "Sketch", url: "loci://canvas/hand-made", updatedAt: expect.any(String), elements: 1, open: false }]);
    expect((await agent.tool("read_widget_context", { checkpointId: "hand-made" })).text).toContain("The user drew this by hand; no agent has edited it yet.");
    const result = await agent.draw([{ type: "restoreCheckpoint", id: "hand-made" }, { type: "ellipse", id: "dot", x: 200, y: 0, width: 40, height: 40 }]);
    expect(result.isError).toBe(false);
    expect(store.canvases.size).toBe(2);
    expect(live(scene(store.canvases.get("hand-made")!).elements).map((element) => element.id)).toEqual(["box", "dot"]);
    expect(store.canvases.get("hand-made")!.title).toBe("Sketch");
  });

  it("keeps simultaneous calls on different drawings apart", async () => {
    const agent = await connect();
    const one = await agent.draw([{ type: "rectangle", id: "one", x: 0, y: 0, width: 100, height: 60 }]);
    const two = await agent.draw([{ type: "rectangle", id: "two", x: 0, y: 0, width: 100, height: 60 }]);
    expect(store.canvases.size).toBe(2);
    // Hold the first call's load until the second call has finished completely.
    let release!: () => void;
    const held = new Promise<void>((resolve) => { release = resolve; });
    gate = (action, input) => action === "checkpoint.load" && input.id === one.checkpointId ? held : Promise.resolve();
    const slow = agent.draw([{ type: "restoreCheckpoint", id: one.checkpointId }, { type: "ellipse", id: "onto-one", x: 200, y: 0, width: 40, height: 40 }]);
    const fast = await agent.draw([{ type: "restoreCheckpoint", id: two.checkpointId }, { type: "ellipse", id: "onto-two", x: 200, y: 0, width: 40, height: 40 }]);
    release();
    const slowResult = await slow;
    expect([slowResult.isError, fast.isError]).toEqual([false, false]);
    expect(slowResult.receipt?.url).toBe(one.receipt?.url);
    expect(fast.receipt?.url).toBe(two.receipt?.url);
    expect(slowResult.receipt?.url).not.toBe(fast.receipt?.url);
    const ids = (checkpoint: string) => live(scene(store.canvases.get(store.checkpoints.get(checkpoint)!.canvasId)!).elements).map((element) => element.id);
    expect(ids(one.checkpointId!)).toEqual(["one", "onto-one"]);
    expect(ids(two.checkpointId!)).toEqual(["two", "onto-two"]);
  });

  it("applies simultaneous calls on one drawing in turn without losing either", async () => {
    const agent = await connect();
    const base = await agent.draw([{ type: "rectangle", id: "base", x: 0, y: 0, width: 100, height: 60 }]);
    const results = await Promise.all(["left", "right"].map((id, index) =>
      agent.draw([{ type: "restoreCheckpoint", id: base.checkpointId }, { type: "ellipse", id, x: 200 + index * 100, y: 0, width: 40, height: 40 }])));
    expect(results.map((result) => result.isError)).toEqual([false, false]);
    expect(live(scene(drawing()).elements).map((element) => element.id).sort()).toEqual(["base", "left", "right"]);
  });

  it("stores the official widget's edited scene on the checkpoint's canvas", async () => {
    const agent = await connect();
    const first = await agent.draw(firstCall);
    const loaded = JSON.parse((await agent.tool("read_checkpoint", { id: first.checkpointId })).text) as { elements: El[] };
    expect(loaded.elements.map((element) => element.id)).toEqual(live(scene(drawing()).elements).map((element) => element.id));
    const edited = loaded.elements.filter((element) => element.id !== "title").map((element) => element.id === "b1" ? { ...element, x: 40, version: element.version + 1 } : element);
    expect((await agent.tool("save_checkpoint", { id: first.checkpointId, data: JSON.stringify({ elements: edited }) })).text).toBe("ok");
    const after = scene(drawing());
    expect(byId(after.elements, "b1").x).toBe(40);
    expect(byId(after.elements, "title").isDeleted).toBe(true);
    expect(requests.at(-1)!.input.replace).toBe(true);
    expect((await agent.tool("save_checkpoint", { id: "never-issued", data: '{"elements":[]}' })).text).toContain("was not found");
  });

  it("reports problems to the agent and leaves the drawing as it was", async () => {
    const agent = await connect();
    const first = await agent.draw(firstCall);
    const saved = drawing().dataJson;
    // Upstream's own message for an unknown checkpoint.
    const unknown = await agent.draw([{ type: "restoreCheckpoint", id: "feedfacefeedfacefe" }, { type: "ellipse", id: "x", x: 0, y: 0, width: 10, height: 10 }]);
    expect(unknown).toMatchObject({ isError: true, text: expect.stringContaining('Checkpoint "feedfacefeedfacefe" not found') });
    const broken = await agent.draw([{ type: "restoreCheckpoint", id: first.checkpointId }, { type: "rectangle", id: "bad", x: "left", y: 0 }]);
    expect(broken).toMatchObject({ isError: true, text: expect.stringContaining("finite x/y") });
    const image = await agent.draw([{ type: "restoreCheckpoint", id: first.checkpointId }, { type: "image", id: "pic", x: 0, y: 0, width: 10, height: 10, fileId: "nope" }]);
    expect(image).toMatchObject({ isError: true, text: expect.stringContaining("cannot attach new image files") });
    for (const failed of [unknown, broken, image]) {
      expect(failed.receipt?.saved).toBeUndefined();
      expect(failed.text).not.toContain("Saved to Loci:");
    }
    expect(drawing().dataJson).toBe(saved);
    expect(store.checkpoints.size).toBe(1);
    // Another project's session cannot reach this drawing by its checkpoint.
    source = { id: "session-2", cwd: "/work/other" } as Session;
    const foreign = await agent.draw([{ type: "restoreCheckpoint", id: first.checkpointId }, { type: "ellipse", id: "x", x: 0, y: 0, width: 10, height: 10 }]);
    expect(foreign).toMatchObject({ isError: true, text: expect.stringContaining("not found") });
    expect((await agent.tool("read_widget_context", { checkpointId: first.checkpointId })).isError).toBe(true);
    expect((await agent.tool("read_widget_context")).text).toContain("no drawings yet");
    source = { id: "session-3", cwd: "~" } as Session;
    expect((await agent.draw(firstCall)).text).toContain("Choose a project folder");
    expect(drawing().dataJson).toBe(saved);
  });

  it("does not return a saved resource when persistence rejects the drawing", async () => {
    const agent = await connect();
    gate = async (action) => { if (action === "checkpoint.save") throw new Error("Disk is full"); };
    const result = await agent.draw(firstCall);
    expect(result.isError).toBe(true);
    expect(result.text).toContain("Disk is full");
    expect(result.receipt?.url).toBeUndefined();
    expect(result.receipt?.saved).toBeUndefined();
    expect(result.text).not.toContain("Saved to Loci:");
    expect(store.canvases.size).toBe(0);
    expect(store.checkpoints.size).toBe(0);
  });

  it("explains a missing or revoked Loci connection instead of hanging", async () => {
    const offline = await connect({});
    expect((await offline.tool("read_me")).text).toContain("# Excalidraw Element Format");
    expect(await offline.draw(firstCall)).toMatchObject({ isError: true, text: expect.stringContaining("not connected to Loci") });
    const revoked = await connect({ LOCI_APP_ENDPOINT: endpoint, LOCI_APP_TOKEN: "stale" });
    expect(await revoked.draw(firstCall)).toMatchObject({ isError: true, text: "Connection revoked or unauthorized" });
    const remote = await connect({ LOCI_APP_ENDPOINT: "10.0.0.1:80", LOCI_APP_TOKEN: TOKEN });
    expect(await remote.tool("read_widget_context")).toMatchObject({ isError: true, text: expect.stringContaining("localhost") });
    const closed = await connect({ LOCI_APP_ENDPOINT: "127.0.0.1:9", LOCI_APP_TOKEN: TOKEN });
    expect(await closed.draw(firstCall)).toMatchObject({ isError: true, text: expect.stringContaining("Cannot reach Loci") });
    expect(store.canvases.size).toBe(0);
  });
});


describe("editing existing canvas elements through MCP", () => {
  const read = (agent: Awaited<ReturnType<typeof connect>>, checkpointId: string) =>
    agent.request("tools/call", { name: "get_elements", arguments: { checkpointId } });
  const update = (agent: Awaited<ReturnType<typeof connect>>, checkpointId: string, revision: number, updates: El[]) =>
    agent.request("tools/call", { name: "update_elements", arguments: { checkpointId, expectedRevision: revision, updates } });

  it("updates 75 existing elements without losing image properties or adding IDs", async () => {
    const agent = await connect();
    const first = await agent.draw([{ type: "text", id: "heading", x: 20.125, y: 20.25, text: "Finalizers", fontSize: 24, fontFamily: 3 },
      { type: "rectangle", id: "border", x: 0, y: 0, width: 400, height: 160, strokeWidth: 3 },
      { type: "text", id: "example", x: 20, y: 90, text: "Example", fontSize: 18 }]);
    await editByHand(data => {
      for (let i = 0; i < 70; i++) data.elements.push(native({ type: "rectangle", id: `existing-${i}`, x: i * 10, y: 200, width: 20, height: 20 }));
      for (let i = 0; i < 2; i++) {
        const fileId = `photo-${i}`;
        data.files[fileId] = { id: fileId, dataURL: "data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png", created: 1 };
        data.elements.push(native({ type: "image", id: `image-${i}`, x: 30 + i * 100, y: 400, width: 64, height: 64, fileId, status: "saved", scale: [-1, 1], crop: null }));
      }
      byId(data.elements, "heading").lineHeight = 1.7;
    });
    const before = scene(drawing());
    const result = await read(agent, first.checkpointId!);
    expect(result.isError).not.toBe(true);
    const current = result.structuredContent;
    expect(current).toMatchObject({ elementCount: 75, imageCount: 2, revision: drawing().updatedAt });
    expect(byId(current.elements, "heading")).toMatchObject({ x: 20.125, y: 20.25, lineHeight: 1.7 });
    expect(byId(current.elements, "image-0")).toMatchObject({ scale: [-1, 1], fileId: "photo-0" });
    expect(JSON.stringify(current)).not.toContain("base64");
    const replaced = vi.fn();
    window.addEventListener("loci-canvas-scene-replaced", replaced);
    const edited = await update(agent, first.checkpointId!, current.revision, [
      { id: "heading", changes: { x: 130.5, fontSize: 32, strokeColor: "#1971c2" } },
      { id: "border", changes: { strokeWidth: 1, strokeStyle: "dashed" } },
      { id: "image-0", changes: { x: 260.5, y: 450.75 } },
    ]);
    window.removeEventListener("loci-canvas-scene-replaced", replaced);
    expect(replaced).toHaveBeenCalledOnce();
    expect(edited.isError).not.toBe(true);
    const after = scene(drawing());
    expect(live(after.elements).map(e => e.id).sort()).toEqual(live(before.elements).map(e => e.id).sort());
    expect(after.files).toEqual(before.files);
    expect(edited.structuredContent).toMatchObject({ elementCount: 75, imageCount: 2, canvasId: drawing().id });
    expect(byId(after.elements, "heading")).toMatchObject({ x: 130.5, fontSize: 32, strokeColor: "#1971c2", fontFamily: 3, lineHeight: 1.7 });
    expect(byId(after.elements, "image-0")).toMatchObject({ x: 260.5, y: 450.75, scale: [-1, 1], crop: null, fileId: "photo-0" });
    expect(byId(after.elements, "existing-50")).toEqual(byId(before.elements, "existing-50"));
    const again = await read(agent, edited.structuredContent.checkpointId);
    expect(again.structuredContent.revision).toBe(edited.structuredContent.revision);
  });

  it("rejects stale revisions and invalid batches without writing any elements", async () => {
    const agent = await connect();
    const first = await agent.draw([{ type: "rectangle", id: "box", x: 0, y: 0, width: 100, height: 60 }]);
    const current = (await read(agent, first.checkpointId!)).structuredContent;
    await editByHand(data => { byId(data.elements, "box").x = 99; });
    const before = drawing().dataJson;
    const stale = await update(agent, first.checkpointId!, current.revision, [{ id: "box", changes: { x: 30 } }]);
    expect(stale).toMatchObject({ isError: true });
    expect(stale.content[0].text).toContain("changed");
    expect(drawing().dataJson).toBe(before);
    const revision = drawing().updatedAt;
    for (const invalid of [
      [{ id: "box", changes: { x: 30 } }, { id: "missing", changes: { x: 1 } }],
      [{ id: "box", changes: { id: "replacement" } }],
      [{ id: "box", changes: { isDeleted: true } }],
      [{ id: "box", changes: { x: "30" } }],
    ]) {
      expect(await update(agent, first.checkpointId!, revision, invalid)).toMatchObject({ isError: true });
      expect(drawing().dataJson).toBe(before);
    }
  });
});


it.each([
  { edit: "moves", manual: { x: 80 }, expected: { x: 80, fontSize: 40, height: 48 } },
  { edit: "types into", manual: { text: "hello\nsecond line", originalText: "hello\nsecond line", width: 110, height: 48 },
    expected: { fontSize: 40, text: "hello\nsecond line", width: 220, height: 96 } },
])("keeps an MCP font update when the user $edit that same text during persistence", async ({ manual, expected }) => {
  const agent = await connect();
  const first = await agent.draw([{ type: "text", id: "text", x: 0, y: 0, text: "hello", fontSize: 20, fontFamily: 3 }]);
  const original = drawing();
  const current = (await agent.request("tools/call", { name: "get_elements", arguments: { checkpointId: first.checkpointId } })).structuredContent;
  let release!: () => void, started!: () => void;
  const held = new Promise<void>(resolve => { release = resolve; });
  const starting = new Promise<void>(resolve => { started = resolve; });
  let firstUpsert = true;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_upsert" && firstUpsert) { firstUpsert = false; started(); await held; }
    return store.run(command, args) as never;
  });
  const editing = agent.request("tools/call", { name: "update_elements", arguments: {
    checkpointId: first.checkpointId, expectedRevision: current.revision, updates: [{ id: "text", changes: { fontSize: 40 } }],
  } });
  await starting;
  const draft = scene(original);
  Object.assign(byId(draft.elements, "text"), { ...manual, version: 4, versionNonce: 9 });
  canvasSceneDrafts.set(original.id, { elements: draft.elements as never, appState: draft.appState as never, files: draft.files as never, baseDataJson: original.dataJson });
  release();
  const result = await editing;
  expect(result.isError).not.toBe(true);
  const final = byId(scene(drawing()).elements, "text");
  expect(final).toMatchObject(expected);
  expect(final.version).toBeGreaterThan(4);
  expect(result.structuredContent.revision).toBe(drawing().updatedAt);
  expect(result.structuredContent.updatedIds).toContain("text");
});

it("composes a concurrent manual move with an MCP resize of a labeled, bound shape", async () => {
  const agent = await connect();
  const first = await agent.draw([
    { type: "rectangle", id: "box", x: 0, y: 0, width: 200, height: 100, label: { text: "API", fontFamily: 3 } },
    { type: "rectangle", id: "other", x: 400, y: 0, width: 100, height: 100 },
    { type: "arrow", id: "arrow", x: 200, y: 50, width: 200, height: 0, points: [[0, 0], [200, 0]],
      startBinding: { elementId: "box" }, endBinding: { elementId: "other" } },
  ]);
  const original = drawing();
  const { applyElementUpdates } = await import("./elementUpdates");
  const manual = JSON.parse(applyElementUpdates(original.dataJson, [{ id: "box", changes: { x: 80 } }]).dataJson);
  let release!: () => void, started!: () => void;
  const held = new Promise<void>(resolve => { release = resolve; });
  const starting = new Promise<void>(resolve => { started = resolve; });
  let firstUpsert = true;
  vi.mocked(invoke).mockImplementation(async (command, args) => {
    if (command === "canvas_upsert" && firstUpsert) { firstUpsert = false; started(); await held; }
    return store.run(command, args) as never;
  });
  const editing = agent.request("tools/call", { name: "update_elements", arguments: {
    checkpointId: first.checkpointId, expectedRevision: original.updatedAt, updates: [{ id: "box", changes: { width: 300 } }],
  } });
  await starting;
  canvasSceneDrafts.set(original.id, { ...manual, baseDataJson: original.dataJson });
  release();
  const result = await editing;
  expect(result.isError).not.toBe(true);
  const elements = scene(drawing()).elements;
  expect(byId(elements, "box")).toMatchObject({ x: 80, width: 300 });
  const label = elements.find(element => element.type === "text" && element.containerId === "box")!;
  expect(label.x).toBeCloseTo(80 + (300 - label.width) / 2);
  const arrow = byId(elements, "arrow");
  expect(arrow.x + arrow.points[0][0]).toBeCloseTo(380.5);
  expect(arrow.startBinding.elementId).toBe("box");
  expect(elements.map(element => element.id)).toEqual(scene(original).elements.map(element => element.id));
});
