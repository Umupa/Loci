// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Block } from "../../sessions/model/session";
import { DAY_MS, GHOST_LIMIT, readMap, type ConceptData, type MapNode } from "./learnMap";
import { connect, placeInRows, placeNear } from "./placement";
import { saidByLearner, wordedByLearner } from "./quote";
import { afterRecall, mapStats, pickRevisits, scheduleFirst } from "./schedule";

// The first use of Excalidraw loads all of it, which a busy machine can take longer than 5 seconds over.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 60_000 });

type El = Record<string, any>;

beforeEach(() => {
  vi.stubGlobal("FontFace", class { constructor(family: string, _source: string, descriptors: object) { Object.assign(this, { family }, descriptors); } });
  // happy-dom has no text rasterizer; the actual Excalidraw conversion runs.
  vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue({ filter: "none", font: "20px sans-serif",
    measureText(text: string) { return { width: text.length * (parseFloat((this as { font: string }).font) || 20) * 0.5 }; } } as never);
});
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

const NOW = Date.UTC(2026, 9, 8, 12);
const scenes = () => import("./mapScene");
const elementsOf = (dataJson: string) => (JSON.parse(dataJson).elements as El[]).filter((element) => !element.isDeleted);
const byId = (dataJson: string, id: string) => elementsOf(dataJson).find((element) => element.id === id)!;
function context(now = NOW, sessionId = "s1") {
  let next = 0;
  return { now, sessionId, newId: (prefix: string) => `${prefix}${++next}`, noteId: (id: string) => `note-${id}` };
}
const user = (text: string): Block => ({ id: crypto.randomUUID(), role: "user", text });
const agent = (text: string): Block => ({ id: crypto.randomUUID(), role: "assistant", text });

describe("learner quotes", () => {
  const blocks = [
    user("Service 给一组 Pod 一个固定入口，靠 label 选中它们。"),
    agent("A Service load-balances across the Pods its selector matches."),
    user("> A Pod is the smallest deployable unit.\n\n— `docs/pods.md`, p. 3\n\nso what is a Deployment?"),
  ];

  it("accepts the learner's words whatever the spacing and punctuation", () => {
    expect(saidByLearner(blocks, "Service给一组Pod一个固定入口,靠label选中它们")).toBe(true);
    expect(saidByLearner(blocks, "SO WHAT IS A deployment")).toBe(true);
  });

  it("rejects the agent's words, a paraphrase and a passage quoted from a file", () => {
    expect(saidByLearner(blocks, "load-balances across the Pods its selector matches")).toBe(false);
    expect(saidByLearner(blocks, "Service 为一组 Pod 提供稳定的访问入口")).toBe(false);
    expect(saidByLearner(blocks, "A Pod is the smallest deployable unit")).toBe(false);
  });

  it("rejects a quote too short to prove anything, a draft, and words said before a revisit began", () => {
    expect(saidByLearner(blocks, "Pod")).toBe(false);
    expect(saidByLearner([{ ...user("an unsent explanation of services"), draft: true }], "an unsent explanation of services")).toBe(false);
    expect(saidByLearner(blocks, "靠 label 选中它们", 1)).toBe(false);
    expect(saidByLearner(blocks, "so what is a Deployment", 1)).toBe(true);
  });

  it("lets an edge label be lifted from the learner's wording only", () => {
    expect(wordedByLearner(blocks, "靠 label 选中")).toBe(true);
    expect(wordedByLearner(blocks, "load-balances")).toBe(false);
  });
});

describe("placement", () => {
  const node = { width: 180, height: 64 };
  const anchor = { x: 0, y: 0, ...node };

  it("puts a node to the right of its anchor, then below, then left", () => {
    expect(placeNear([anchor], anchor, node)).toEqual({ x: 380, y: 0 });
    const right = { x: 380, y: 0, ...node };
    expect(placeNear([anchor, right], anchor, node)).toEqual({ x: 0, y: 180 });
    const below = { x: 0, y: 180, ...node };
    expect(placeNear([anchor, right, below], anchor, node)).toEqual({ x: -380, y: 0 });
    // Above comes last on the axes, and a diagonal below is preferred to one above.
    expect(placeNear([anchor, right, below, { x: -380, y: 0, ...node }], anchor, node)).toEqual({ x: 0, y: -180 });
    expect(placeNear([anchor, right, below, { x: -380, y: 0, ...node }, { x: 0, y: -180, ...node }], anchor, node)).toEqual({ x: 380, y: 180 });
  });

  it("never lands on something already there", () => {
    const taken = [anchor];
    for (let count = 0; count < 30; count++) {
      const spot = { ...placeNear(taken, anchor, node), ...node };
      expect(taken.some((box) => spot.x < box.x + box.width && box.x < spot.x + spot.width && spot.y < box.y + box.height && box.y < spot.y + spot.height)).toBe(false);
      taken.push(spot);
    }
  });

  it("fills rows of four when there is nothing to connect to", () => {
    const taken = [];
    for (let count = 0; count < 5; count++) taken.push({ ...placeInRows(taken, 200, node), ...node });
    expect(taken.map(({ x, y }) => [x, y])).toEqual([[0, 200], [380, 200], [760, 200], [1140, 200], [0, 380]]);
  });

  it("draws an arrow between the facing sides", () => {
    expect(connect(anchor, { x: 380, y: 0, ...node })).toEqual({ x: 180, y: 32, points: [[0, 0], [200, 0]] });
    expect(connect(anchor, { x: 0, y: 180, ...node })).toEqual({ x: 90, y: 64, points: [[0, 0], [0, 116]] });
  });
});

describe("revisit schedule", () => {
  const explained = (): ConceptData => ({ v: 1, self: "n", kind: "concept", state: "solid", ...scheduleFirst(NOW), history: [{ at: NOW, type: "said", verdict: "right", sessionId: "s1" }] });

  it("moves along the ladder while recalls hold, and anchors after a week's wait", () => {
    let node = explained();
    expect(node.dueAt).toBe(NOW + DAY_MS);
    let now = node.dueAt!;
    node = afterRecall(node, "solid", now, "s2");
    expect([node.state, node.step, node.dueAt]).toEqual(["solid", 1, now + 3 * DAY_MS]);
    now = node.dueAt!;
    node = afterRecall(node, "solid", now, "s3");
    expect([node.state, node.step, node.dueAt]).toEqual(["solid", 2, now + 7 * DAY_MS]);
    now = node.dueAt!;
    node = afterRecall(node, "solid", now, "s4");
    expect([node.state, node.step, node.dueAt]).toEqual(["anchored", 3, now + 21 * DAY_MS]);
  });

  it("repeats the interval after a shaky recall and resets after a lost one, keeping history", () => {
    const once = afterRecall(explained(), "solid", NOW + DAY_MS, "s2");
    const shaky = afterRecall(once, "shaky", NOW + 4 * DAY_MS, "s3");
    expect([shaky.state, shaky.step, shaky.dueAt]).toEqual(["solid", 1, NOW + 7 * DAY_MS]);
    const gone = afterRecall(shaky, "gone", NOW + 7 * DAY_MS, "s4");
    expect([gone.state, gone.step, gone.dueAt]).toEqual(["ghost", undefined, undefined]);
    expect(gone.history.map((event) => event.verdict)).toEqual(["right", "solid", "shaky", "gone"]);
  });

  it("offers a few revisits: judgments first, then the oldest, or the most connected when many wait", () => {
    const node = (id: string, dueAt: number, links = 0, kind: MapNode["kind"] = "concept"): MapNode =>
      ({ id, label: id, kind, state: kind === "concept" ? "solid" : "open", due: true, dueAt, history: [], links });
    expect(pickRevisits([node("a", 3), node("b", 1), node("j", 5, 0, "judgment"), node("c", 2), node("d", 4)]).map((entry) => entry.id)).toEqual(["j", "b", "c"]);
    const many = Array.from({ length: GHOST_LIMIT + 1 }, (_, index) => node(`n${index}`, index, index));
    expect(pickRevisits(many).map((entry) => entry.id)).toEqual(["n9", "n8", "n7"]);
    expect(pickRevisits([{ ...node("x", 1), due: false }])).toEqual([]);
  });
});

describe("the map", () => {
  async function started() {
    const { initMapScene, recordOnMap } = await scenes();
    const map = initMapScene("Kubernetes", "我想把自己的博客部署到一个三节点集群上", ["能独立写出 Deployment 和 Service"]);
    return recordOnMap(map, [
      { kind: "concept", label: "Pod", evidence: "prior", verdict: "right" },
      { kind: "concept", label: "Deployment", evidence: "prior", verdict: "partly" },
    ], [{ from: "Deployment", to: "Pod", label: "管理一组" }], context());
  }

  it("starts with the subject and the learner's mission, and no nodes", async () => {
    const { initMapScene } = await scenes();
    const view = readMap(initMapScene("Kubernetes", "部署我的博客", ["写出 Deployment"]), NOW);
    expect(view).toMatchObject({ title: "Kubernetes", mission: "部署我的博客\n· 写出 Deployment", nodes: [], edges: [] });
    expect(view.untracked).toEqual({ shapes: [], edges: [] });
  });

  it("records what the learner already knows as solid nodes due tomorrow", async () => {
    const written = await started();
    const view = readMap(written.dataJson, NOW);
    expect(view.nodes.map(({ label, state, dueAt, step, noteId }) => [label, state, dueAt, step, noteId])).toEqual([
      ["Pod", "solid", NOW + DAY_MS, 0, "note-n1"], ["Deployment", "solid", NOW + DAY_MS, 0, "note-n2"]]);
    expect(view.edges).toEqual([{ id: "e3", from: "n2", to: "n1", label: "管理一组", by: "learner" }]);
    expect(byId(written.dataJson, "n1")).toMatchObject({ strokeStyle: "solid", strokeWidth: 2, opacity: 100, y: expect.any(Number) });
    // Nodes go under the mission text, never on top of it.
    const mission = byId(written.dataJson, "learn-mission");
    expect(byId(written.dataJson, "n1").y).toBeGreaterThan(mission.y + mission.height);
  });

  it("sketches unexplored nodes beside an anchor without moving anything, up to the cap", async () => {
    const { sketchOnMap } = await scenes();
    const base = await started();
    const before = elementsOf(base.dataJson).map(({ id, x, y }) => [id, x, y]);
    const sketched = sketchOnMap(base.dataJson, { near: "Pod", labels: ["Service", "Node"], edges: [{ from: "Service", to: "Pod", label: "selects" }] }, context());
    expect(elementsOf(sketched.dataJson).filter((element) => before.some(([id]) => id === element.id)).map(({ id, x, y }) => [id, x, y])).toEqual(before);
    const view = readMap(sketched.dataJson, NOW);
    expect(view.nodes.filter((node) => node.state === "ghost").map((node) => node.label)).toEqual(["Service", "Node"]);
    const service = view.nodes.find((node) => node.label === "Service")!;
    expect(byId(sketched.dataJson, service.id)).toMatchObject({ strokeStyle: "dashed", strokeWidth: 1 });
    expect(view.edges.find((edge) => edge.by === "proposed")).toMatchObject({ from: service.id, to: "n1", label: "selects" });
    expect(() => sketchOnMap(sketched.dataJson, { labels: ["Service"] }, context())).toThrow(/already on the map/);
    let map = sketched.dataJson;
    for (let count = 2; count < GHOST_LIMIT; count += 1) map = sketchOnMap(map, { labels: [`extra ${count}`] }, context()).dataJson;
    expect(() => sketchOnMap(map, { labels: ["one too many"] }, context())).toThrow(/may hold 9/);
  });

  it("knows a node by the name it was given, however the label wraps inside the shape", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const name = "Pod 标签与 Service selector 的匹配规则";
    const sketched = sketchOnMap((await started()).dataJson, { near: "Pod", labels: [name] }, context());
    const wrapped = elementsOf(sketched.dataJson).find((element) => element.type === "text" && element.originalText === name)!;
    expect(wrapped.text).toContain("\n");
    expect(readMap(sketched.dataJson, NOW).nodes.map((node) => node.label)).toContain(name);
    const recorded = recordOnMap(sketched.dataJson, [{ kind: "concept", label: name, evidence: "said", verdict: "right" }], [], context());
    expect(recorded.nodes).toEqual([expect.objectContaining({ label: name, created: false, state: "solid" })]);
    expect(readMap(recorded.dataJson, NOW).nodes).toHaveLength(3);
  });

  it("turns an unexplored node solid only through a record, and keeps a wrong explanation as history", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const sketched = sketchOnMap((await started()).dataJson, { near: "Pod", labels: ["Service"] }, context());
    const wrong = recordOnMap(sketched.dataJson, [{ kind: "concept", label: "Service", evidence: "said", verdict: "wrong" }], [], context(NOW + 1000));
    const ghost = readMap(wrong.dataJson, NOW).nodes.find((node) => node.label === "Service")!;
    expect(ghost).toMatchObject({ state: "ghost", noteId: `note-${ghost.id}`, unsourced: true });
    const right = recordOnMap(wrong.dataJson, [{ kind: "concept", label: "Service", evidence: "said", verdict: "right", sources: [{ path: "sources/service.md", lines: [10, 42] }] }],
      [{ from: "Service", to: "Pod", label: "靠 label 选中" }], context(NOW + 2000, "s2"));
    const service = readMap(right.dataJson, NOW).nodes.find((node) => node.label === "Service")!;
    expect(service).toMatchObject({ state: "solid", step: 0, dueAt: NOW + 2000 + DAY_MS, sources: [{ path: "sources/service.md", lines: [10, 42] }] });
    expect(service.unsourced).toBeUndefined();
    expect(service.history.map((event) => [event.type, event.verdict, event.sessionId])).toEqual([["said", "wrong", "s1"], ["said", "right", "s2"]]);
    expect(byId(right.dataJson, service.id)).toMatchObject({ strokeStyle: "solid", strokeWidth: 2 });
  });

  it("replaces the agent's proposed edge with the learner's wording", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const sketched = sketchOnMap((await started()).dataJson, { near: "Pod", labels: ["Service"], edges: [{ from: "Service", to: "Pod", label: "selects" }] }, context());
    const recorded = recordOnMap(sketched.dataJson, [{ kind: "concept", label: "Service", evidence: "said", verdict: "right" }],
      [{ from: "Service", to: "Pod", label: "靠 label 选中" }], { ...context(), newId: (prefix) => `${prefix}new` });
    const service = readMap(recorded.dataJson, NOW).nodes.find((node) => node.label === "Service")!;
    expect(readMap(recorded.dataJson, NOW).edges.filter((edge) => edge.from === service.id)).toEqual([{ id: "enew", from: service.id, to: "n1", label: "靠 label 选中", by: "learner" }]);
  });

  it("takes in a box and an arrow the learner drew by hand", async () => {
    const { recordOnMap } = await scenes();
    const { applyCheckpointPatch } = await import("../../canvas/checkpointScene");
    const base = await started();
    const drawn = applyCheckpointPatch(base.dataJson, { elements: [
      { type: "rectangle", id: "hand", x: 900, y: 600, width: 200, height: 80, label: { text: "ConfigMap" } },
      { type: "arrow", id: "hand-arrow", x: 900, y: 640, width: 500, height: 300, points: [[0, 0], [-500, -300]], start: { id: "hand" }, end: { id: "n1" }, label: { text: "注入配置" } },
    ] }).dataJson;
    expect(readMap(drawn, NOW).untracked).toEqual({ shapes: [{ id: "hand", type: "rectangle", text: "ConfigMap" }], edges: [{ id: "hand-arrow", from: "hand", to: "n1", label: "注入配置" }] });
    expect(() => recordOnMap(drawn, [], [{ id: "hand-arrow" }], context())).toThrow(/does not join two nodes/);
    const adopted = recordOnMap(drawn, [{ kind: "concept", id: "hand", evidence: "drew" }], [{ id: "hand-arrow" }], context());
    const view = readMap(adopted.dataJson, NOW);
    expect(view.untracked).toEqual({ shapes: [], edges: [] });
    expect(view.nodes.find((node) => node.id === "hand")).toMatchObject({ label: "ConfigMap", state: "solid", history: [{ type: "drew" }] });
    expect(view.edges.find((edge) => edge.id === "hand-arrow")).toMatchObject({ from: "hand", to: "n1", by: "learner" });
    // The learner's own geometry stays as drawn.
    expect(byId(adopted.dataJson, "hand")).toMatchObject({ x: 900, y: 600, width: 200, height: 80 });
  });

  it("does not let a pasted copy inherit a node's state", async () => {
    const base = await started();
    const scene = JSON.parse(base.dataJson) as { elements: El[] };
    const original = scene.elements.find((element) => element.id === "n1")!;
    scene.elements.push({ ...original, id: "copy", x: original.x + 40, boundElements: null });
    const view = readMap(JSON.stringify(scene), NOW);
    expect(view.nodes.map((node) => node.id)).toEqual(["n1", "n2"]);
    expect(view.untracked.shapes).toEqual([{ id: "copy", type: "rectangle", text: "" }]);
  });

  it("fades nodes that are due, and restores and reschedules them after a revisit", async () => {
    const { finishRecall, overruleRecall, refreshDue } = await scenes();
    const base = await started();
    expect(refreshDue(base.dataJson, NOW)).toBeNull();
    const tomorrow = NOW + DAY_MS;
    const faded = refreshDue(base.dataJson, tomorrow)!;
    expect(byId(faded, "n1").opacity).toBe(45);
    expect(elementsOf(faded).find((element) => element.containerId === "n1")!.opacity).toBe(45);
    expect(readMap(faded, tomorrow).nodes.every((node) => node.due)).toBe(true);
    const held = finishRecall(faded, "n1", "solid", context(tomorrow, "s2"));
    expect(held.data).toMatchObject({ state: "solid", step: 1, dueAt: tomorrow + 3 * DAY_MS });
    expect(byId(held.dataJson, "n1").opacity).toBe(100);
    expect(elementsOf(held.dataJson).find((element) => element.containerId === "n1")!.opacity).toBe(100);
    // The learner disagrees with the verdict: the same revisit is judged again.
    const overruled = overruleRecall(held.dataJson, "n1", "gone", context(tomorrow + 5000));
    expect(overruled.data).toMatchObject({ state: "ghost" });
    expect(overruled.data.history.map((event) => event.verdict)).toEqual(["right", "gone"]);
    expect(byId(overruled.dataJson, "n1")).toMatchObject({ strokeStyle: "dashed", strokeWidth: 1 });
    const again = overruleRecall(overruled.dataJson, "n1", "solid", context(tomorrow + 9000));
    expect(again.data).toMatchObject({ state: "solid", step: 1, dueAt: tomorrow + 3 * DAY_MS });
  });

  it("keeps a judgment open until its date, then closes it against what happened", async () => {
    const { closeJudgment, recordOnMap, refreshDue } = await scenes();
    const lookBackAt = NOW + 90 * DAY_MS;
    expect(() => recordOnMap("", [{ kind: "judgment", label: "ACME 被低估", evidence: "said" }], [], context())).toThrow(/lookBackAt/);
    const base = await started();
    const judged = recordOnMap(base.dataJson, [{ kind: "judgment", label: "ACME 被低估", near: "Pod", evidence: "said", lookBackAt }], [{ from: "ACME 被低估", to: "Pod" }], context());
    const node = readMap(judged.dataJson, NOW).nodes.find((entry) => entry.kind === "judgment")!;
    expect(node).toMatchObject({ state: "open", due: false, dueAt: lookBackAt, noteId: `note-${node.id}` });
    expect(byId(judged.dataJson, node.id)).toMatchObject({ type: "diamond", strokeStyle: "solid", strokeWidth: 2 });
    expect(byId(refreshDue(judged.dataJson, lookBackAt)!, node.id).opacity).toBe(45);
    const closed = closeJudgment(judged.dataJson, node.id, context(lookBackAt, "s9"));
    expect(closed.data).toMatchObject({ state: "closed", history: [{ type: "said" }, { type: "reality", sessionId: "s9" }] });
    expect(closed.data.dueAt).toBeUndefined();
    expect(byId(closed.dataJson, node.id)).toMatchObject({ strokeWidth: 4, opacity: 100 });
  });

  it("anchors a node the learner has put to use", async () => {
    const { recordOnMap } = await scenes();
    const used = recordOnMap((await started()).dataJson, [{ kind: "concept", label: "Pod", evidence: "did" }], [], context(NOW + 5000));
    expect(readMap(used.dataJson, NOW).nodes[0]).toMatchObject({ label: "Pod", state: "anchored" });
    expect(byId(used.dataJson, "n1").strokeWidth).toBe(4);
  });

  it("reports whether learning lasts, not how much time was spent", async () => {
    const { finishRecall } = await scenes();
    const base = await started();
    const early = finishRecall(base.dataJson, "n1", "solid", context(NOW + DAY_MS, "s2"));
    const late = finishRecall(early.dataJson, "n1", "shaky", context(NOW + 9 * DAY_MS, "s3"));
    const held = finishRecall(late.dataJson, "n2", "solid", context(NOW + 9 * DAY_MS, "s3"));
    expect(mapStats(readMap(held.dataJson, NOW + 10 * DAY_MS), NOW + 10 * DAY_MS)).toEqual({
      concepts: { ghost: 0, solid: 1, anchored: 1 }, judgments: { open: 0, closed: 0 },
      delayedRecall: { total: 2, held: 1 }, weeklySessions: [0, 0, 2, 1],
    });
  });
});

describe("the roadmap", () => {
  const frameOf = (dataJson: string, name: string) => elementsOf(dataJson).find((element) => element.type === "frame" && element.name === name)!;
  const nodeOf = (dataJson: string, label: string) => byId(dataJson, readMap(dataJson, NOW).nodes.find((node) => node.label === label)!.id);
  const topicsOf = (dataJson: string, stage: string) => readMap(dataJson, NOW).nodes.filter((node) => node.stage === stage).map((node) => node.label);
  const places = (dataJson: string) => elementsOf(dataJson).map(({ id, x, y }) => [id, x, y]);
  const kept = (after: string, before: string) => places(after).filter(([id]) => places(before).some(([other]) => other === id));
  async function blank() {
    const { initMapScene } = await scenes();
    return initMapScene("Kubernetes", "我想转做平台研发，三个月内能通过面试", []);
  }

  it("lays each stage out as a band of dashed topics, one band under another", async () => {
    const { sketchOnMap } = await scenes();
    const topics = ["容器与进程", "Namespace 隔离", "cgroup 资源限制", "镜像与分层", "容器运行时", "OCI 规范"];
    const first = sketchOnMap(await blank(), { stage: "1 · 容器基础", labels: topics }, context());
    expect(first.nodes.map((node) => [node.label, node.state])).toEqual(topics.map((label) => [label, "ghost"]));
    const second = sketchOnMap(first.dataJson, { stage: "2 · 集群架构", labels: ["API Server", "etcd"] }, context());
    const view = readMap(second.dataJson, NOW);
    expect(view.stages).toEqual(["1 · 容器基础", "2 · 集群架构"]);
    expect(topicsOf(second.dataJson, "1 · 容器基础")).toEqual(topics);
    expect(topicsOf(second.dataJson, "2 · 集群架构")).toEqual(["API Server", "etcd"]);
    // A roadmap names what there is to learn. It claims nothing about the learner and connects nothing.
    expect(view.nodes.every((node) => node.state === "ghost")).toBe(true);
    expect(view.edges).toEqual([]);
    expect(view.untracked).toEqual({ shapes: [], edges: [] });

    const band = frameOf(second.dataJson, "1 · 容器基础");
    const cells = topics.map((label) => nodeOf(second.dataJson, label));
    // Five to a row; the sixth starts the next row under the first.
    expect(new Set(cells.slice(0, 5).map((cell) => cell.y)).size).toBe(1);
    expect(cells.slice(0, 5).map((cell) => cell.x)).toEqual([...cells.slice(0, 5).map((cell) => cell.x)].sort((a, b) => a - b));
    expect([cells[5].x, cells[5].y > cells[0].y]).toEqual([cells[0].x, true]);
    for (const cell of cells) {
      expect(cell).toMatchObject({ frameId: band.id, strokeStyle: "dashed" });
      expect(cell.x >= band.x && cell.x + cell.width <= band.x + band.width && cell.y >= band.y && cell.y + cell.height <= band.y + band.height).toBe(true);
      // The name inside the shape belongs to the stage with it, or dragging the stage would leave it behind.
      expect(elementsOf(second.dataJson).find((element) => element.type === "text" && element.containerId === cell.id)!.frameId).toBe(band.id);
    }
    const mission = byId(second.dataJson, "learn-mission");
    const next = frameOf(second.dataJson, "2 · 集群架构");
    expect(band.y).toBeGreaterThan(mission.y + mission.height);
    expect([next.x, next.y > band.y + band.height]).toEqual([band.x, true]);
    // The first stage stayed where it was when the second arrived.
    expect(kept(second.dataJson, first.dataJson)).toEqual(places(first.dataJson));
  });

  it("leaves a topic that is already on the map where it is, and goes under what is there", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const base = recordOnMap(await blank(), [{ kind: "concept", label: "Pod", evidence: "prior", verdict: "right" }], [], context());
    const road = sketchOnMap(base.dataJson, { stage: "1 · 工作负载", labels: ["pod", "Service"] }, context());
    expect(road.already).toEqual([{ id: "n1", label: "Pod" }]);
    expect(road.nodes.map((node) => node.label)).toEqual(["Service"]);
    expect(kept(road.dataJson, base.dataJson)).toEqual(places(base.dataJson));
    const pod = byId(road.dataJson, "n1");
    expect(frameOf(road.dataJson, "1 · 工作负载").y).toBeGreaterThan(pod.y + pod.height);
    // Naming only topics that are there draws nothing.
    expect(readMap(sketchOnMap(base.dataJson, { stage: "2 · 空", labels: ["Pod"] }, context()).dataJson, NOW).stages).toEqual([]);
  });

  it("stays a road: eight stages of eight topics, without taking room from sketches", async () => {
    const { sketchOnMap } = await scenes();
    const start = await blank();
    expect(() => sketchOnMap(start, { stage: "1", labels: Array.from({ length: 9 }, (_, index) => `t${index}`) }, context())).toThrow(/at most 8 topics/);
    expect(() => sketchOnMap(start, { stage: "1", labels: ["同名", "同名"] }, context())).toThrow(/twice/);
    let map = start;
    for (let stage = 1; stage <= 8; stage += 1) map = sketchOnMap(map, { stage: `${stage} · 阶段`, labels: [`s${stage}a`, `s${stage}b`] }, context()).dataJson;
    expect(() => sketchOnMap(map, { stage: "9 · 阶段", labels: ["x"] }, context())).toThrow(/8 stages/);
    map = sketchOnMap(map, { stage: "1 · 阶段", labels: ["c", "d", "e", "f", "g", "h"] }, context()).dataJson;
    expect(() => sketchOnMap(map, { stage: "1 · 阶段", labels: ["i"] }, context())).toThrow(/has 8/);
    // Twenty-two topics wait on the roadmap, and the nine sketches beside what the learner knows are still theirs to fill.
    for (let count = 0; count < GHOST_LIMIT; count += 1) map = sketchOnMap(map, { labels: [`旁支 ${count}`] }, context()).dataJson;
    expect(() => sketchOnMap(map, { labels: ["再多一个"] }, context())).toThrow(/may hold 9/);
    expect(readMap(map, NOW).nodes.filter((node) => node.state === "ghost" && !node.stage)).toHaveLength(GHOST_LIMIT);
  });

  it("adds topics to a stage by growing its frame, never by moving anything", async () => {
    const { sketchOnMap } = await scenes();
    const one = sketchOnMap(await blank(), { stage: "1 · 容器", labels: ["a1", "a2", "a3"] }, context());
    // Alone on the map, a stage fills its row and then opens a new one under it.
    const alone = sketchOnMap(one.dataJson, { stage: "1 · 容器", labels: ["a4", "a5", "a6"] }, context());
    expect(topicsOf(alone.dataJson, "1 · 容器")).toEqual(["a1", "a2", "a3", "a4", "a5", "a6"]);
    expect(kept(alone.dataJson, one.dataJson)).toEqual(places(one.dataJson));
    expect([nodeOf(alone.dataJson, "a5").y, nodeOf(alone.dataJson, "a6").x]).toEqual([nodeOf(alone.dataJson, "a1").y, nodeOf(alone.dataJson, "a1").x]);
    expect(nodeOf(alone.dataJson, "a6").y).toBeGreaterThan(nodeOf(alone.dataJson, "a1").y);
    expect(frameOf(alone.dataJson, "1 · 容器").height).toBeGreaterThan(frameOf(one.dataJson, "1 · 容器").height);
    // With another stage under it there is no room below, so the row runs on to the right.
    const two = sketchOnMap(one.dataJson, { stage: "2 · 集群", labels: ["b1"] }, context());
    const squeezed = sketchOnMap(two.dataJson, { stage: "1 · 容器", labels: ["a4", "a5", "a6"] }, context());
    expect(kept(squeezed.dataJson, two.dataJson)).toEqual(places(two.dataJson));
    expect(nodeOf(squeezed.dataJson, "a6").y).toBe(nodeOf(squeezed.dataJson, "a1").y);
    expect(nodeOf(squeezed.dataJson, "a6").x).toBeGreaterThan(nodeOf(squeezed.dataJson, "a5").x);
    const wide = frameOf(squeezed.dataJson, "1 · 容器");
    expect(wide.width).toBeGreaterThan(frameOf(two.dataJson, "1 · 容器").width);
    for (const label of ["a4", "a5", "a6"]) {
      const cell = nodeOf(squeezed.dataJson, label);
      expect(cell.frameId).toBe(wide.id);
      expect(cell.x + cell.width <= wide.x + wide.width && cell.y + cell.height <= wide.y + wide.height).toBe(true);
      expect(elementsOf(squeezed.dataJson).find((element) => element.type === "text" && element.containerId === cell.id)!.frameId).toBe(wide.id);
    }
  });

  it("takes off the map only unexplored nodes nobody has touched", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const road = sketchOnMap(await blank(), { stage: "1 · 容器", labels: ["Namespace", "cgroup"] }, context());
    const said = recordOnMap(road.dataJson, [{ kind: "concept", label: "Namespace", evidence: "said", verdict: "right" }], [], context());
    // What the learner explained, or tied to something else, is theirs.
    expect(() => sketchOnMap(said.dataJson, { labels: [], remove: ["Namespace"] }, context())).toThrow(/only the learner/);
    const linked = recordOnMap(said.dataJson, [], [{ from: "Namespace", to: "cgroup", label: "隔离靠" }], context());
    expect(() => sketchOnMap(linked.dataJson, { labels: [], remove: ["cgroup"] }, context())).toThrow(/learner has connected/);
    expect(() => sketchOnMap(said.dataJson, { labels: [], remove: ["没有这个"] }, context())).toThrow(/not a node on this map/);

    const gone = sketchOnMap(said.dataJson, { labels: [], remove: ["cgroup"] }, context());
    expect(gone.removed).toEqual([{ id: expect.any(String), label: "cgroup" }]);
    expect(readMap(gone.dataJson, NOW)).toMatchObject({ stages: ["1 · 容器"], nodes: [{ label: "Namespace", state: "solid" }] });
    // A stage goes with its last topic. One that is refilled in the same call stays where it is.
    const other = sketchOnMap(gone.dataJson, { stage: "2 · 集群", labels: ["etcd"] }, context());
    expect(readMap(sketchOnMap(other.dataJson, { labels: [], remove: ["etcd"] }, context()).dataJson, NOW).stages).toEqual(["1 · 容器"]);
    const swapped = sketchOnMap(other.dataJson, { stage: "2 · 集群", labels: ["API Server"], remove: ["etcd"] }, context());
    expect(topicsOf(swapped.dataJson, "2 · 集群")).toEqual(["API Server"]);
    expect(frameOf(swapped.dataJson, "2 · 集群")).toMatchObject({ id: frameOf(other.dataJson, "2 · 集群").id, x: frameOf(other.dataJson, "2 · 集群").x, y: frameOf(other.dataJson, "2 · 集群").y });
    expect([nodeOf(swapped.dataJson, "API Server").x, nodeOf(swapped.dataJson, "API Server").y]).toEqual([nodeOf(other.dataJson, "etcd").x, nodeOf(other.dataJson, "etcd").y]);
    // An arrow the agent only proposed goes with the node it proposed.
    const proposed = sketchOnMap(said.dataJson, { near: "Namespace", labels: ["chroot"], edges: [{ from: "chroot", to: "Namespace" }] }, context());
    const cleaned = sketchOnMap(proposed.dataJson, { labels: [], remove: ["chroot"] }, context());
    expect(readMap(cleaned.dataJson, NOW).edges).toEqual([]);
    expect(elementsOf(cleaned.dataJson).filter((element) => element.type === "arrow")).toEqual([]);
  });

  it("turns a topic solid where it stands, and grows the learner's own nodes beside the road", async () => {
    const { recordOnMap, sketchOnMap } = await scenes();
    const first = sketchOnMap(await blank(), { stage: "1 · 容器", labels: ["Namespace", "cgroup", "镜像"] }, context());
    const road = sketchOnMap(first.dataJson, { stage: "2 · 集群", labels: ["etcd", "调度器"] }, context());
    const band = frameOf(road.dataJson, "1 · 容器");
    const topic = nodeOf(road.dataJson, "cgroup");
    const said = recordOnMap(road.dataJson, [{ kind: "concept", label: "cgroup", evidence: "said", verdict: "right" }], [], context());
    expect(said.nodes).toEqual([expect.objectContaining({ label: "cgroup", state: "solid", created: false })]);
    expect(nodeOf(said.dataJson, "cgroup")).toMatchObject({ x: topic.x, y: topic.y, frameId: band.id, strokeStyle: "solid" });
    expect(readMap(said.dataJson, NOW).nodes.find((node) => node.label === "cgroup")).toMatchObject({ state: "solid", stage: "1 · 容器" });

    // Something of the learner's own that hangs off a topic sits right of that stage, level with the topic.
    const own = recordOnMap(said.dataJson, [{ kind: "concept", label: "OOM 时我见过的现象", near: "cgroup", evidence: "said", verdict: "right" }], [{ from: "OOM 时我见过的现象", to: "cgroup", label: "超限就被杀" }], context());
    const mine = nodeOf(own.dataJson, "OOM 时我见过的现象");
    expect(mine.x).toBeGreaterThan(band.x + band.width);
    expect(mine.y + mine.height / 2).toBe(topic.y + topic.height / 2);
    expect(mine.frameId ?? null).toBeNull();
    expect(readMap(own.dataJson, NOW).nodes.find((node) => node.label === "OOM 时我见过的现象")!.stage).toBeUndefined();
    // Something with nothing to hang off goes beside the road as well, leaving the space under it for later stages.
    const loose = recordOnMap(own.dataJson, [{ kind: "concept", label: "我以前用过的 Docker Compose", evidence: "prior", verdict: "right" }], [], context());
    const free = nodeOf(loose.dataJson, "我以前用过的 Docker Compose");
    expect(free.x).toBeGreaterThan(band.x + band.width);
    expect(free.y).toBeLessThan(frameOf(loose.dataJson, "2 · 集群").y + frameOf(loose.dataJson, "2 · 集群").height);
    expect(kept(loose.dataJson, road.dataJson).map(([id, x, y]) => [id, x, y])).toEqual(places(road.dataJson));
  });
});
