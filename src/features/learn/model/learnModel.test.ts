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
