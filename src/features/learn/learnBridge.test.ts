// @vitest-environment happy-dom
// The real stack below the UI: an MCP client talks JSON-RPC to the learning
// server process, whose calls reach the production bridge over the control
// socket's line protocol. Only the Tauri window and SQLite are replaced, by
// the store below.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createServer, type AddressInfo, type Server } from "node:net";
import path from "node:path";
import { createInterface } from "node:readline";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { handleAgentApp } from "../agent-app/model/agentApp";
import { canvasSceneDrafts, invalidateCanvases, type Canvas, type CanvasUpsert } from "../canvas/canvas";
import { handleCanvasBridge } from "../canvas/checkpoints";
import type { Note, NoteUpsert } from "../notes";
import type { Block, Session } from "../sessions/model/session";
import { handleLearnBridge, learnEditHint, liftRecallCover, recallCovered } from "./bridge";
import { DAY_MS, LEARN_MAP_TAG, LEARN_MAP_WRITE_REFUSED, readMap } from "./model/learnMap";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

type El = Record<string, any>;
const server = path.resolve(__dirname, "../../../src-tauri/resources/learn-mcp/loci-learn.mjs");
const TOKEN = "session-token";
const CWD = "/work/kubernetes";
const NOW = new Date(2026, 9, 8, 12).getTime();

/** The commands the bridge uses, with the storage rules of canvas.rs and notes.rs that matter here. */
function appStore() {
  const canvases = new Map<string, Canvas>();
  const notes = new Map<string, Note>();
  const files = new Set<string>();
  let clock = 0;
  const commands: Record<string, (args: any) => unknown> = {
    canvas_list: () => [...canvases.values()],
    canvas_get: ({ id }) => canvases.get(id) ?? null,
    canvas_upsert: ({ canvas }: { canvas: CanvasUpsert }) => {
      const { checkpoint: _checkpoint, expectedUpdatedAt, ...fields } = canvas;
      const previous = canvases.get(fields.id);
      if (expectedUpdatedAt !== undefined && (!previous || previous.updatedAt !== expectedUpdatedAt))
        throw new Error("Canvas changed since it was read; retry the update.");
      const saved: Canvas = { ...fields, createdAt: previous?.createdAt ?? ++clock, updatedAt: ++clock };
      canvases.set(saved.id, saved);
      return saved;
    },
    canvas_delete: ({ id }) => { canvases.delete(id); },
    canvas_checkpoint_canvas: ({ checkpointId }) => canvases.has(checkpointId) ? checkpointId : null,
    canvas_checkpoint_latest: () => null,
    notes_get: ({ id }) => notes.get(id) ?? null,
    notes_upsert: ({ note }: { note: NoteUpsert }) => {
      const previous = notes.get(note.id);
      const saved: Note = { ...previous, ...note, slug: note.id, createdAt: previous?.createdAt ?? ++clock, updatedAt: ++clock };
      notes.set(saved.id, saved);
      return saved;
    },
    stat_files: ({ paths }: { paths: string[] }) => paths.map((file) => ({ path: file, mtimeMs: files.has(file) ? 1 : null })),
  };
  return { canvases, notes, files, run: async (command: string, args: unknown) => {
    if (!commands[command]) throw new Error(`Unexpected command ${command}`);
    return structuredClone(commands[command](args));
  } };
}

let store: ReturnType<typeof appStore>;
let control: Server;
let endpoint: string;
let source: Session;
const host = { reveal: vi.fn() };
const requests: Array<{ namespace: string; action: string }> = [];

const said = (text: string): Block => ({ id: crypto.randomUUID(), role: "user", text });
const answered = (text: string): Block => ({ id: crypto.randomUUID(), role: "assistant", text });
/** The learner types a message; the agent's tool calls of that turn see it. */
const learnerSays = (text: string) => { source = { ...source, blocks: [...source.blocks, said(text)] }; };
const agentSays = (text: string) => { source = { ...source, blocks: [...source.blocks, answered(text)] }; };

beforeAll(async () => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", font: "20px sans-serif",
    measureText(text: string) { return { width: text.length * (parseFloat((this as { font: string }).font) || 20) * 0.5 }; } } as never);
  // What `control.rs` does for the `learn` namespace: one JSON line in, one out.
  control = createServer((socket) => {
    createInterface({ input: socket }).once("line", (line) => {
      const request = JSON.parse(line);
      const reply = (response: object) => socket.end(`${JSON.stringify(response)}\n`);
      if (request.token !== TOKEN) return reply({ ok: false, error: "Connection revoked or unauthorized" });
      requests.push({ namespace: request.namespace, action: request.action });
      void handleLearnBridge(source, request.action, request.input, host)
        .then((result) => reply({ ok: true, result }), (error: Error) => reply({ ok: false, error: error.message }));
    });
  });
  await new Promise<void>((resolve) => control.listen(0, "127.0.0.1", resolve));
  endpoint = `127.0.0.1:${(control.address() as AddressInfo).port}`;
});
afterAll(() => { control.close(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const clients: ChildProcessWithoutNullStreams[] = [];
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"], now: NOW });
  store = appStore();
  source = { id: "session-1", cwd: CWD, harness: "claude", title: "claude · Kubernetes", blocks: [] } as unknown as Session;
  requests.length = 0;
  host.reveal.mockReset();
  invalidateCanvases();
  vi.mocked(invoke).mockImplementation((command, args) => store.run(command, args) as never);
});
afterEach(() => { for (const child of clients.splice(0)) child.kill(); canvasSceneDrafts.clear(); vi.useRealTimers(); });

/** An agent CLI's MCP client, connected to a fresh learning server process. */
async function connect(env: Record<string, string> = { LOCI_APP_ENDPOINT: endpoint, LOCI_APP_TOKEN: TOKEN }) {
  const { LOCI_APP_ENDPOINT: _endpoint, LOCI_APP_TOKEN: _token, ...inherited } = process.env;
  const child = spawn(process.execPath, [server], { env: { ...inherited, ...env } });
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
    return { text: result.content.map((entry: El) => entry.text).join("\n") as string, isError: result.isError === true, data: result.structuredContent as El | undefined };
  };
  return { initialized, request, tool };
}

const map = () => { expect(store.canvases.size).toBe(1); return [...store.canvases.values()][0]; };
const view = () => readMap(map().dataJson, Date.now());
const node = (label: string) => view().nodes.find((entry) => entry.label === label)!;
const element = (id: string) => (JSON.parse(map().dataJson).elements as El[]).find((entry) => entry.id === id)!;

/** Orientation as a learner and an agent would go through it. */
async function oriented(agent: Awaited<ReturnType<typeof connect>>) {
  learnerSays("我想把自己的博客部署到一个三节点集群上，年底前做到。我知道 Pod 是最小的调度单位，Deployment 管理一组 Pod 的副本。");
  expect((await agent.tool("map_init", { subject: "Kubernetes", why: "我想把自己的博客部署到一个三节点集群上，年底前做到", success: [] })).isError).toBe(false);
  const recorded = await agent.tool("map_record", {
    nodes: [
      { label: "Pod", evidence: "prior", quote: "Pod 是最小的调度单位", verdict: "right" },
      { label: "Deployment", evidence: "prior", quote: "Deployment 管理一组 Pod 的副本", verdict: "right" },
    ],
    edges: [{ from: "Deployment", to: "Pod", label: "管理一组 Pod 的副本" }],
  });
  expect(recorded.isError, recorded.text).toBe(false);
  return recorded;
}

describe("the learning server", () => {
  it("offers five tools, marks only reading as read-only, and gives no initialization instructions", async () => {
    const agent = await connect();
    expect(agent.initialized).toMatchObject({ protocolVersion: "2025-06-18", serverInfo: { name: "loci_learn" }, capabilities: { tools: {} } });
    expect(agent.initialized.instructions).toBeUndefined();
    const { tools } = await agent.request("tools/list");
    expect(tools.map((tool: El) => [tool.name, tool.annotations.readOnlyHint])).toEqual([
      ["map_read", true], ["map_init", false], ["map_sketch", false], ["map_record", false], ["revisit", false]]);
    // Solid is not "mastered": the tool the agent records with says so.
    expect(tools.find((tool: El) => tool.name === "map_record").description).toContain("solid means explained, not mastered");
    // No tool takes coordinates: an agent cannot place or move anything.
    expect(JSON.stringify(tools)).not.toMatch(/"(x|y|width|height|points)"/);
    await expect(agent.request("resources/list")).rejects.toThrow(/Method not found/);
  });

  it("says so when it was not started from a Loci session", async () => {
    const agent = await connect({});
    expect(await agent.tool("map_read")).toMatchObject({ isError: true, text: expect.stringContaining("not connected to Loci") });
  });

  it("starts a map only from the learner's own words", async () => {
    const agent = await connect();
    expect((await agent.tool("map_read")).data).toMatchObject({ exists: false });
    learnerSays("我想把自己的博客部署到一个三节点集群上");
    const invented = await agent.tool("map_init", { subject: "Kubernetes", why: "The learner wants to run production workloads on Kubernetes" });
    expect(invented).toMatchObject({ isError: true, text: expect.stringContaining("word for word") });
    expect(store.canvases.size).toBe(0);
    const started = await agent.tool("map_init", { subject: "Kubernetes", why: "我想把自己的博客部署到一个三节点集群上" });
    expect(started.data).toMatchObject({ saved: true, created: true, title: "Kubernetes", url: `loci://canvas/${map().id}` });
    expect(started.text).toContain(`[Kubernetes](loci://canvas/${map().id})`);
    expect(map()).toMatchObject({ cwd: CWD, tags: [LEARN_MAP_TAG] });
    expect(view()).toMatchObject({ title: "Kubernetes", mission: "我想把自己的博客部署到一个三节点集群上" });
    expect(host.reveal).toHaveBeenCalledWith(map().id, "session-1");
    // A second init leaves the map alone.
    expect((await agent.tool("map_init", { subject: "Other", why: "我想把自己的博客部署到一个三节点集群上" })).data).toMatchObject({ created: false, title: "Kubernetes" });
    expect(requests.every((request) => request.namespace === "learn")).toBe(true);
  });

  it("records prior knowledge as solid nodes with a note that keeps the learner's words", async () => {
    const agent = await connect();
    const recorded = await oriented(agent);
    expect(recorded.data!.nodes).toEqual([
      { id: expect.any(String), label: "Pod", state: "solid", created: true, revisitOn: "2026-10-09", noteUrl: expect.stringMatching(/^loci:\/\/note\/learn-/) },
      { id: expect.any(String), label: "Deployment", state: "solid", created: true, revisitOn: "2026-10-09", noteUrl: expect.stringMatching(/^loci:\/\/note\/learn-/) },
    ]);
    const pod = node("Pod");
    expect(store.notes.get(pod.noteId!)).toMatchObject({
      title: "Pod", tags: ["kubernetes", "learn"], sourceCwd: CWD, sourceSessionId: "session-1",
      body: "### 2026-10-08 · already knew · right\n> Pod 是最小的调度单位\n\nSession: [Kubernetes](loci://session/session-1)",
    });
    expect(view().edges).toEqual([{ id: expect.any(String), from: node("Deployment").id, to: pod.id, label: "管理一组 Pod 的副本", by: "learner" }]);
    const read = (await agent.tool("map_read")).data!;
    expect(read).toMatchObject({ exists: true, title: "Kubernetes", unexplored: "0 outside the roadmap, of at most 9", revisit: [] });
    expect(read.nodes).toEqual([{ id: pod.id, label: "Pod", state: "solid", links: 1 }, { id: node("Deployment").id, label: "Deployment", state: "solid", links: 1 }]);
    expect(read.drawnByLearner).toBeUndefined();
  });

  it("refuses to make a node solid from anything but the learner's words", async () => {
    const agent = await connect();
    await oriented(agent);
    expect((await agent.tool("map_sketch", { near: "Pod", nodes: ["Service"] })).data).toMatchObject({ nodes: [{ label: "Service", state: "ghost" }] });
    agentSays("A Service gives a stable address to the set of Pods its label selector matches.");
    learnerSays("好的，懂了");
    for (const quote of ["A Service gives a stable address to the set of Pods its label selector matches", "Service 给一组 Pod 提供稳定入口，通过 label 选择它们", "好的"]) {
      const refused = await agent.tool("map_record", { nodes: [{ label: "Service", quote, verdict: "right" }] });
      expect(refused, quote).toMatchObject({ isError: true, text: expect.stringContaining("word for word") });
    }
    expect(node("Service")).toMatchObject({ state: "ghost", history: [] });
    learnerSays("Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们，Pod 重建了地址变了也不影响。");
    const missing = await agent.tool("map_record", { nodes: [{ label: "Service", quote: "Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们", verdict: "right", sources: [{ path: "sources/service.md", lines: [1, 20] }] }] });
    expect(missing).toMatchObject({ isError: true, text: expect.stringContaining("does not exist in this project") });
    const outside = await agent.tool("map_record", { nodes: [{ label: "Service", quote: "Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们", verdict: "right", sources: [{ path: "../secrets.md" }] }] });
    expect(outside).toMatchObject({ isError: true, text: expect.stringContaining("inside the project") });
    const agentLabel = await agent.tool("map_record", { nodes: [{ label: "Service", quote: "Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们", verdict: "right" }], edges: [{ from: "Service", to: "Pod", label: "load-balances" }] });
    expect(agentLabel).toMatchObject({ isError: true, text: expect.stringContaining("learner's own wording") });
    const longLabel = await agent.tool("map_record", { nodes: [{ label: "Service", quote: "Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们", verdict: "right" }], edges: [{ from: "Service", to: "Pod", label: "给一组 Pod 一个不变的入口，靠 label 找到它们" }] });
    expect(longLabel).toMatchObject({ isError: true, text: expect.stringContaining("too long to sit on an arrow") });
    expect(node("Service").state).toBe("ghost");
    store.files.add(`${CWD}/sources/service.md`);
    const recorded = await agent.tool("map_record", {
      nodes: [{ label: "Service", quote: "Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们", verdict: "partly", correction: "它还负责在这些 Pod 之间分发流量。", sources: [{ path: "sources/service.md", lines: [1, 20] }] }],
      edges: [{ from: "Service", to: "Pod", label: "靠 label 找到它们" }],
    });
    expect(recorded.isError, recorded.text).toBe(false);
    expect(node("Service")).toMatchObject({ state: "solid", sources: [{ path: "sources/service.md", lines: [1, 20] }] });
    expect(element(node("Service").id)).toMatchObject({ strokeStyle: "solid", strokeWidth: 2 });
    const body = store.notes.get(node("Service").noteId!)!.body;
    expect(body).toContain("### 2026-10-08 · said · partly\n> Service 就是给一组 Pod 一个不变的入口，靠 label 找到它们");
    expect(body).toContain("Correction (agent): 它还负责在这些 Pod 之间分发流量。");
    expect(body).toMatch(/Sources: \[sources\/service\.md, lines 1–20\]\(loci:\/\/file\/[A-Za-z0-9_-]+#L1-20\)/);
  });

  it("keeps the learner's edits to a note when it adds to it", async () => {
    const agent = await connect();
    await oriented(agent);
    const pod = node("Pod");
    const note = store.notes.get(pod.noteId!)!;
    store.notes.set(note.id, { ...note, title: "Pod（我的理解）", body: `${note.body}\n\n我自己补充的一段。`, tags: ["k8s"] });
    learnerSays("Pod 里可以有多个容器，它们共享网络。");
    await agent.tool("map_record", { nodes: [{ id: pod.id, quote: "Pod 里可以有多个容器，它们共享网络", verdict: "right" }] });
    expect(store.notes.get(note.id)).toMatchObject({ title: "Pod（我的理解）", tags: ["k8s"] });
    expect(store.notes.get(note.id)!.body).toMatch(/我自己补充的一段。\n\n### 2026-10-08 · said · right\n> Pod 里可以有多个容器，它们共享网络/);
  });

  it("keeps every record on one node in its note when a single call records that node twice", async () => {
    const agent = await connect();
    await oriented(agent);
    const pod = node("Pod");
    learnerSays("Pod 里可以有多个容器，它们共享网络。");
    const recorded = await agent.tool("map_record", { nodes: [
      { id: pod.id, evidence: "drew" },
      { id: pod.id, quote: "Pod 里可以有多个容器，它们共享网络", verdict: "partly", correction: "它们还共享存储卷。" },
    ] });
    expect(recorded.isError, recorded.text).toBe(false);
    // The node is reported once, as it stands after both records.
    expect(recorded.data!.nodes).toEqual([expect.objectContaining({ id: pod.id, label: "Pod" })]);
    expect(node("Pod").history.map((event) => event.type)).toEqual(["prior", "drew", "said"]);
    const body = store.notes.get(pod.noteId!)!.body;
    expect(body).toContain("### 2026-10-08 · already knew · right");
    expect(body).toContain("### 2026-10-08 · drew");
    expect(body).toContain("### 2026-10-08 · said · partly\n> Pod 里可以有多个容器，它们共享网络");
    expect(body).toContain("Correction (agent): 它们还共享存储卷。");
  });

  it("caps unexplored nodes and never moves what is on the map", async () => {
    const agent = await connect();
    await oriented(agent);
    const before = (JSON.parse(map().dataJson).elements as El[]).map(({ id, x, y }) => [id, x, y]);
    expect((await agent.tool("map_sketch", { near: "Pod", nodes: ["A", "B", "C", "D"] })).isError).toBe(true);
    for (const nodes of [["Service", "Node", "ConfigMap"], ["Ingress", "Volume", "Namespace"], ["Secret", "Job", "DaemonSet"]])
      expect((await agent.tool("map_sketch", { near: "Pod", nodes })).isError).toBe(false);
    expect(await agent.tool("map_sketch", { near: "Pod", nodes: ["StatefulSet"] })).toMatchObject({ isError: true, text: expect.stringContaining("may hold 9") });
    const after = (JSON.parse(map().dataJson).elements as El[]).filter((entry) => before.some(([id]) => id === entry.id)).map(({ id, x, y }) => [id, x, y]);
    expect(after).toEqual(before);
    expect((await agent.tool("map_read")).data).toMatchObject({ unexplored: "9 outside the roadmap, of at most 9" });
  });

  it("draws the roadmap stage by stage, with no connections, and takes off only what nobody touched", async () => {
    const agent = await connect();
    await oriented(agent);
    const { tools } = await agent.request("tools/list");
    expect(Object.keys(tools.find((tool: El) => tool.name === "map_sketch").inputSchema.properties)).toEqual(["stage", "near", "nodes", "edges", "remove"]);

    const first = await agent.tool("map_sketch", { stage: "1 · 工作负载", nodes: ["Pod", "Service", "Ingress", "StatefulSet"] });
    expect(first.isError, first.text).toBe(false);
    // What the learner already explained stays where it is; the stage gets the rest.
    expect(first.data).toMatchObject({ saved: true, stage: "1 · 工作负载", alreadyOnMap: [{ id: node("Pod").id, label: "Pod" }],
      nodes: [{ label: "Service", state: "ghost" }, { label: "Ingress", state: "ghost" }, { label: "StatefulSet", state: "ghost" }] });
    const platform = ["CRD", "Operator", "client-go", "informer", "admission webhook", "controller-runtime", "leader election", "finalizer"];
    expect((await agent.tool("map_sketch", { stage: "2 · 平台开发", nodes: platform })).isError).toBe(false);
    // More than three at a time only as the topics of a stage, and a stage takes eight.
    expect((await agent.tool("map_sketch", { near: "Pod", nodes: ["A", "B", "C", "D"] })).isError).toBe(true);
    expect(await agent.tool("map_sketch", { stage: "2 · 平台开发", nodes: ["webhook 证书"] })).toMatchObject({ isError: true, text: expect.stringContaining("at most 8 topics") });
    // How topics connect is for the learner to say.
    expect(await agent.tool("map_sketch", { stage: "1 · 工作负载", nodes: ["Job"], edges: [{ from: "Job", to: "Pod" }] })).toMatchObject({ isError: true, text: expect.stringContaining("no connections") });
    expect(await agent.tool("map_sketch", { stage: "1 · 工作负载", near: "Pod", nodes: ["Job"] })).toMatchObject({ isError: true });
    expect(view().edges.every((edge) => edge.by === "learner")).toBe(true);

    const read = (await agent.tool("map_read")).data!;
    expect(read.roadmap).toEqual(["1 · 工作负载", "2 · 平台开发"]);
    expect(read.nodes.filter((entry: El) => entry.stage === "1 · 工作负载").map((entry: El) => entry.label)).toEqual(["Service", "Ingress", "StatefulSet"]);
    expect(read.nodes.filter((entry: El) => entry.stage === "2 · 平台开发").map((entry: El) => entry.label)).toEqual(platform);
    // The roadmap's eleven topics do not use up the sketches beside what the learner knows.
    expect(read.unexplored).toBe("0 outside the roadmap, of at most 9");
    expect(read.rules).toContain("the topics of the roadmap");

    // A topic the learner explains turns solid in its stage, and is then theirs.
    learnerSays("Service 给一组 Pod 一个固定的访问入口，靠标签选中它们。");
    const recorded = await agent.tool("map_record", { nodes: [{ label: "Service", evidence: "said", quote: "Service 给一组 Pod 一个固定的访问入口", verdict: "right" }] });
    expect(recorded.isError, recorded.text).toBe(false);
    expect(node("Service")).toMatchObject({ state: "solid", stage: "1 · 工作负载" });
    const before = map().dataJson;
    expect(await agent.tool("map_sketch", { remove: ["Service"] })).toMatchObject({ isError: true, text: expect.stringContaining("only the learner") });
    expect(await agent.tool("map_sketch", {})).toMatchObject({ isError: true, text: expect.stringContaining("Nothing to sketch") });
    expect(map().dataJson).toBe(before);
    const removed = await agent.tool("map_sketch", { remove: ["Ingress", "StatefulSet"] });
    expect(removed.data).toMatchObject({ saved: true, nodes: [], removed: [{ label: "Ingress" }, { label: "StatefulSet" }] });
    expect(view().nodes.filter((entry) => entry.stage === "1 · 工作负载").map((entry) => entry.label)).toEqual(["Service"]);
    // Taking the whole of a stage off takes the stage with it.
    expect((await agent.tool("map_sketch", { remove: platform })).isError).toBe(false);
    expect(view().stages).toEqual(["1 · 工作负载"]);
  });

  it("does not let general canvas tools or the operator CLI change a learning map", async () => {
    const agent = await connect();
    await oriented(agent);
    const id = map().id;
    const saved = map().dataJson;
    await expect(handleCanvasBridge(source, "checkpoint.save", { id: "next", baseId: id, elements: [{ type: "rectangle", id: "x", x: 0, y: 0, width: 10, height: 10 }], deletedIds: [] }, { isOpen: () => false, reveal: () => undefined }))
      .rejects.toThrow(LEARN_MAP_WRITE_REFUSED);
    await expect(handleCanvasBridge(source, "elements.update", { id, expectedRevision: map().updatedAt, updates: [{ id: node("Pod").id, changes: { x: 900 } }] }, { isOpen: () => false, reveal: () => undefined }))
      .rejects.toThrow(LEARN_MAP_WRITE_REFUSED);
    const appHost = {} as Parameters<typeof handleAgentApp>[4];
    await expect(handleAgentApp(source, "r1", "canvas.write-data", { id, dataJson: JSON.stringify({ elements: [], appState: {}, files: {} }) }, appHost)).rejects.toThrow(LEARN_MAP_WRITE_REFUSED);
    await expect(handleAgentApp(source, "r2", "canvas.delete", { id }, appHost)).rejects.toThrow(LEARN_MAP_WRITE_REFUSED);
    expect(map().dataJson).toBe(saved);
    // Reading stays open to every tool.
    expect(await handleCanvasBridge(source, "elements.read", { id }, { isOpen: () => false, reveal: () => undefined })).toMatchObject({ canvasId: id });
  });

  it("tells the session once when the learner has drawn on the map, and takes the drawing in", async () => {
    const agent = await connect();
    await oriented(agent);
    expect(await learnEditHint(source)).toBe("");
    const { applyCheckpointPatch } = await import("../canvas/checkpointScene");
    const pod = node("Pod");
    await store.run("canvas_upsert", { canvas: { ...map(), dataJson: applyCheckpointPatch(map().dataJson, { elements: [
      { type: "rectangle", id: "hand", x: 900, y: 700, width: 200, height: 80, label: { text: "ConfigMap" } },
      { type: "arrow", id: "hand-arrow", x: 900, y: 740, width: 300, height: 200, points: [[0, 0], [-300, -200]], start: { id: "hand" }, end: { id: pod.id }, label: { text: "给 Pod 注入配置" } },
    ] }).dataJson } });
    invalidateCanvases();
    expect(await learnEditHint(source)).toContain("2 unrecorded shape(s) or arrow(s)");
    expect(await learnEditHint(source)).toBe("");
    expect((await agent.tool("map_read")).data!.drawnByLearner).toEqual({
      shapes: [{ id: "hand", type: "rectangle", text: "ConfigMap" }], edges: [{ id: "hand-arrow", from: "hand", to: pod.id, label: "给 Pod 注入配置" }] });
    const adopted = await agent.tool("map_record", { nodes: [{ id: "hand", evidence: "drew" }], edges: [{ id: "hand-arrow" }] });
    expect(adopted.isError, adopted.text).toBe(false);
    expect(node("ConfigMap")).toMatchObject({ id: "hand", state: "solid", history: [{ type: "drew" }] });
    expect(element("hand")).toMatchObject({ x: 900, y: 700 });
    expect((await agent.tool("map_read")).data!.drawnByLearner).toBeUndefined();
  });

  it("runs a revisit from memory: covers the map, withholds the earlier words, then compares", async () => {
    const agent = await connect();
    await oriented(agent);
    const pod = node("Pod");
    vi.setSystemTime(NOW + DAY_MS + 1000);
    const read = (await agent.tool("map_read")).data!;
    expect(read.revisit.map((entry: El) => entry.label)).toEqual(["Pod", "Deployment"]);
    expect(read.nodes[0]).toMatchObject({ id: pod.id, due: true });
    // The wording on a connection is also what the learner said before: it stays hidden while either end is due.
    expect(read.edges).toEqual([{ id: expect.any(String), from: node("Deployment").id, to: pod.id, labelWithheld: true }]);
    expect(JSON.stringify(read)).not.toContain("管理一组");
    expect(element(pod.id).opacity).toBe(45);
    expect((await agent.tool("map_read", { nodeId: pod.id })).data!.note).toContain("Withheld");
    expect(await agent.tool("revisit", { phase: "finish", nodeId: pod.id, quote: "Pod 是最小的调度单位", verdict: "solid" })).toMatchObject({ isError: true, text: expect.stringContaining("phase start first") });
    const started = await agent.tool("revisit", { phase: "start", nodeId: pod.id });
    expect(started.data).toMatchObject({ id: pod.id, label: "Pod", kind: "concept" });
    expect(started.text).not.toContain("最小的调度单位");
    expect(recallCovered(map().id)).toBe(true);
    // Words from before the question do not count as recall.
    expect(await agent.tool("revisit", { phase: "finish", nodeId: pod.id, quote: "Pod 是最小的调度单位", verdict: "solid" })).toMatchObject({ isError: true, text: expect.stringContaining("after the revisit began") });
    learnerSays("Pod 是 Kubernetes 里能调度的最小单元，里面跑一个或几个容器。");
    const finished = await agent.tool("revisit", { phase: "finish", nodeId: pod.id, quote: "Pod 是 Kubernetes 里能调度的最小单元", verdict: "solid" });
    expect(finished.data).toMatchObject({ verdict: "solid", state: "solid", revisitOn: "2026-10-12", earlier: expect.stringContaining("> Pod 是最小的调度单位") });
    // What it connected to, in the learner's earlier words, comes back with the note for the comparison.
    expect(finished.data!.connections).toEqual([{ with: "Deployment", said: "管理一组 Pod 的副本" }]);
    expect(recallCovered(map().id)).toBe(false);
    expect(element(pod.id).opacity).toBe(100);
    expect(store.notes.get(pod.noteId!)!.body).toContain("### 2026-10-09 · revisit · solid\n> Pod 是 Kubernetes 里能调度的最小单元");
    expect((await agent.tool("map_read", { nodeId: pod.id })).data!.note).toContain("already knew");
  });

  it("counts a revisit as shaky when the learner looked, and leaves a declined one due", async () => {
    const agent = await connect();
    await oriented(agent);
    const pod = node("Pod");
    const deployment = node("Deployment");
    vi.setSystemTime(NOW + DAY_MS + 1000);
    await agent.tool("revisit", { phase: "start", nodeId: pod.id });
    liftRecallCover(map().id);
    expect(recallCovered(map().id)).toBe(false);
    learnerSays("Pod 是最小的调度单元，这个我看了图才想起来。");
    expect((await agent.tool("revisit", { phase: "finish", nodeId: pod.id, quote: "Pod 是最小的调度单元", verdict: "solid" })).data)
      .toMatchObject({ verdict: "shaky", state: "solid", revisitOn: "2026-10-10", adjusted: expect.stringContaining("uncovered") });
    await agent.tool("revisit", { phase: "start", nodeId: deployment.id });
    expect((await agent.tool("revisit", { phase: "cancel", nodeId: deployment.id })).data).toMatchObject({ cancelled: true });
    expect(recallCovered(map().id)).toBe(false);
    expect(node("Deployment")).toMatchObject({ due: true, history: [{ type: "prior" }] });
  });

  it("records a judgment and, on its date, what happened and the principle drawn from it", async () => {
    const agent = await connect();
    await oriented(agent);
    learnerSays("我认为单副本的博客在节点重启时会中断，所以至少要两个副本。如果重启时访问一次都没失败，就说明我错了。");
    expect(await agent.tool("map_record", { nodes: [{ kind: "judgment", label: "单副本会中断", quote: "单副本的博客在节点重启时会中断", wrongIf: "重启时访问一次都没失败", lookBackAt: "2026-10-01" }] }))
      .toMatchObject({ isError: true, text: expect.stringContaining("future date") });
    const judged = await agent.tool("map_record", {
      nodes: [{ kind: "judgment", label: "单副本会中断", near: "Deployment", quote: "单副本的博客在节点重启时会中断", wrongIf: "重启时访问一次都没失败", lookBackAt: "2026-11-08" }],
      edges: [{ from: "单副本会中断", to: "Deployment" }],
    });
    expect(judged.isError, judged.text).toBe(false);
    const judgment = node("单副本会中断");
    expect(judged.data!.nodes[0]).toMatchObject({ state: "open", lookBackOn: "2026-11-08" });
    expect(element(judgment.id)).toMatchObject({ type: "diamond", strokeWidth: 2 });
    expect(store.notes.get(judgment.noteId!)!.body).toContain("Wrong if:\n> 重启时访问一次都没失败\n\nLook back on: 2026-11-08");
    vi.setSystemTime(new Date(2026, 10, 8, 9).getTime());
    expect((await agent.tool("map_read")).data!.revisit[0]).toEqual({ id: judgment.id, label: "单副本会中断", kind: "judgment" });
    const started = await agent.tool("revisit", { phase: "start", nodeId: judgment.id });
    expect(started.data!.written).toContain("单副本的博客在节点重启时会中断");
    // Looking back compares with reality, so nothing is hidden.
    expect(recallCovered(map().id)).toBe(false);
    learnerSays("重启那台节点时博客断了大约四十秒。以后凡是要对外的服务都至少两个副本并且分散在不同节点。");
    const closed = await agent.tool("revisit", { phase: "finish", nodeId: judgment.id, quote: "重启那台节点时博客断了大约四十秒", principle: { label: "对外服务至少两副本", quote: "凡是要对外的服务都至少两个副本并且分散在不同节点" } });
    expect(closed.data).toMatchObject({ state: "closed", principle: { label: "对外服务至少两副本" } });
    expect(element(judgment.id)).toMatchObject({ strokeWidth: 4, opacity: 100 });
    expect(node("对外服务至少两副本")).toMatchObject({ kind: "concept", state: "solid" });
    expect(view().edges.some((edge) => edge.from === node("对外服务至少两副本").id && edge.to === judgment.id)).toBe(true);
    expect(store.notes.get(judgment.noteId!)!.body).toContain("### 2026-11-08 · looked back\n> 重启那台节点时博客断了大约四十秒");
  });

  it("marks a node the learner has used, on the agent's statement, only once it was explained", async () => {
    const agent = await connect();
    await oriented(agent);
    expect(await agent.tool("map_record", { nodes: [{ label: "StatefulSet", evidence: "did", detail: "Deployed one." }] })).toMatchObject({ isError: true, text: expect.stringContaining("already on the map") });
    const used = await agent.tool("map_record", { nodes: [{ label: "Deployment", evidence: "did", detail: "The learner wrote blog-deployment.yaml and applied it; `kubectl get deploy blog` showed 2/2 ready." }] });
    expect(used.isError, used.text).toBe(false);
    expect(node("Deployment").state).toBe("anchored");
    expect(element(node("Deployment").id).strokeWidth).toBe(4);
    expect(store.notes.get(node("Deployment").noteId!)!.body).toContain("### 2026-10-08 · did\nAgent's statement: The learner wrote blog-deployment.yaml");
  });

  it("reports whether explanations last when asked", async () => {
    const agent = await connect();
    await oriented(agent);
    expect((await agent.tool("map_read", { stats: true })).data!.stats).toEqual({
      concepts: { ghost: 0, solid: 2, anchored: 0 }, judgments: { open: 0, closed: 0 }, delayedRecall: { total: 0, held: 0 }, weeklySessions: [0, 0, 0, 1] });
  });
});
