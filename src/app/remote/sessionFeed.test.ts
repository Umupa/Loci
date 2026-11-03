import { afterEach, describe, expect, it, vi } from "vitest";
import { appendUser, applyHarnessEvents, stopStreaming } from "../../integrations/harness/core/apply";
import { newSession, type Block, type Session } from "../../features/sessions/model/session";
import { applySessionChanges, createSessionFeed, diffSessions, outgoingSession, type SessionChange, type SessionFeed } from "./sessionFeed";

const session = (id: string, blocks: Block[] = [], extra: Partial<Session> = {}): Session =>
  ({ ...newSession("claude", "/w"), id, title: id, blocks, ...extra });
const block = (id: string, text = id, extra: Partial<Block> = {}): Block => ({ id, role: "assistant", text, ...extra });

/** The feed's contract: a mirror that applies the diff ends up with what the host has. */
function roundTrip(previous: Session[], next: Session[]): SessionChange[] {
  const changes = diffSessions(previous, next);
  // Through JSON, as the changes travel, so an `undefined` cannot slip through.
  const received = JSON.parse(JSON.stringify(changes)) as SessionChange[];
  const mirror = applySessionChanges(previous.map(outgoingSession), received);
  expect(mirror).toEqual(next.map(outgoingSession));
  return changes;
}

describe("diffSessions and applySessionChanges", () => {
  it("sends only the added text while a reply streams", () => {
    const start = session("s", [block("u", "hi", { role: "user" })], { busy: true });
    const first = applyHarnessEvents(start, [{ type: "message.delta", text: "Hel" }]);
    const second = applyHarnessEvents(first, [{ type: "message.delta", text: "lo" }, { type: "message.delta", text: " there" }]);
    roundTrip([start], [first]);
    const changes = roundTrip([first], [second]);
    const streamed = second.blocks.at(-1)!;
    expect(changes).toEqual([{ id: "s", append: [{ id: streamed.id, text: "lo there" }] }]);
  });

  it("sends a block whole when more than its text changed", () => {
    const streaming = applyHarnessEvents(session("s", [], { busy: true }), [{ type: "message.delta", text: "Done" }]);
    const settled = { ...stopStreaming(streaming), busy: false };
    const changes = roundTrip([streaming], [settled]);
    expect(changes[0]).toMatchObject({ blocks: [{ text: "Done" }] });
    expect(changes[0]).not.toHaveProperty("append");
  });

  it("adds blocks with their order", () => {
    const before = session("s", [block("a")]);
    const after = { ...before, blocks: [...before.blocks, block("b"), block("c")] };
    expect(roundTrip([before], [after])).toEqual([{ id: "s", order: ["a", "b", "c"], blocks: [block("b"), block("c")] }]);
  });

  it("carries a sent message and the busy flag it sets", () => {
    const before = session("s", [block("a")], { pendingQuestion: { requestId: 1, standing: true, questions: [] } as never });
    const after = appendUser(before, "Next question");
    const changes = roundTrip([before], [after]);
    expect(changes[0]).toMatchObject({ meta: { busy: true }, unset: ["pendingQuestion"] });
  });

  it("drops archived head blocks with the order alone", () => {
    const before = session("s", [block("a"), block("b"), block("c"), block("d")]);
    const after = { ...before, blocks: before.blocks.slice(2) };
    expect(roundTrip([before], [after])).toEqual([{ id: "s", order: ["c", "d"] }]);
  });

  it("names removed fields, which JSON cannot carry as undefined", () => {
    const before = session("s", [], { busy: true, usageLimit: { resetsAt: 5 }, noteCard: { id: "n" } as never });
    const after: Session = { ...before, busy: false, usageLimit: undefined };
    delete (after as Partial<Session>).noteCard;
    expect(roundTrip([before], [after])).toEqual([{ id: "s", meta: { busy: false }, unset: ["usageLimit", "noteCard"] }]);
  });

  it("adds and removes whole sessions", () => {
    const kept = session("kept", [block("a")]);
    const gone = session("gone", [block("b")]);
    const added = session("added", [block("c")]);
    const changes = roundTrip([kept, gone], [kept, added]);
    expect(changes).toContainEqual({ id: "gone", removed: true });
    expect(changes.find((change) => change.id === "added")).toMatchObject({ order: ["c"], meta: { title: "added" } });
    expect(changes.some((change) => change.id === "kept")).toBe(false);
  });

  it("keeps attachment bytes and object URLs on the host", () => {
    const attachment = { id: "f", name: "a.png", mimeType: "image/png", kind: "image" as const, size: 3, path: "/w/a.png", data: "AAAA", previewUrl: "blob:x" };
    const before = session("s");
    const after = { ...before, blocks: [block("u", "see", { role: "user", attachments: [attachment] })],
      queuedMessages: [{ id: "q", text: "later", attachments: [attachment] }] };
    const changes = roundTrip([before], [after]);
    const sent = JSON.stringify(changes);
    expect(sent).not.toContain("AAAA");
    expect(sent).not.toContain("blob:x");
    expect(sent).toContain("/w/a.png");
  });

  it("finds nothing when nothing was replaced", () => {
    const one = session("s", [block("a")]);
    expect(diffSessions([one], [one])).toEqual([]);
    expect(diffSessions([one], [{ ...one }])).toEqual([]);
  });

  it("diffs a long conversation quickly", () => {
    // 2,000 blocks: 0.08 ms per diff, whether the last block streams or one
    // is added (Apple M5 Pro, Node 24, warmed up). The target is under 2 ms;
    // the bound below only catches a diff that turned quadratic.
    const blocks = Array.from({ length: 2000 }, (_, index) => block(`b${index}`, "x".repeat(200)));
    const before = session("s", blocks);
    const after = { ...before, blocks: [...blocks.slice(0, -1), { ...blocks[1999], text: blocks[1999].text + "more" }] };
    const runs = 50;
    const started = performance.now();
    for (let run = 0; run < runs; run += 1) diffSessions([before], [after]);
    const each = (performance.now() - started) / runs;
    expect(diffSessions([before], [after])).toEqual([{ id: "s", append: [{ id: "b1999", text: "more" }] }]);
    expect(each).toBeLessThan(20);
  });
});

describe("createSessionFeed", () => {
  afterEach(() => vi.useRealTimers());

  it("sends one patch for a burst of changes, numbered from the snapshot", () => {
    vi.useFakeTimers();
    const sent: SessionFeed[] = [];
    const one = session("s", [block("a")]);
    const feed = createSessionFeed([one], (message) => sent.push(message));
    const snapshot = feed.snapshot();
    expect(snapshot).toMatchObject({ kind: "snapshot", seq: 0, sessions: [one] });

    const two = { ...one, blocks: [...one.blocks, block("b")] };
    const three = { ...two, title: "renamed" };
    feed.changed([two]);
    feed.changed([three]);
    expect(sent).toEqual([]);
    vi.advanceTimersByTime(50);
    expect(sent).toEqual([{ kind: "patch", epoch: snapshot.epoch, seq: 1, changes: [{ id: "s", meta: { title: "renamed" }, order: ["a", "b"], blocks: [block("b")] }] }]);

    feed.changed([three]);
    vi.advanceTimersByTime(50);
    expect(sent).toHaveLength(1);
    feed.dispose();
  });

  it("leaves hidden runs out", () => {
    vi.useFakeTimers();
    const sent: SessionFeed[] = [];
    const feed = createSessionFeed([], (message) => sent.push(message));
    feed.changed([session("habit", [], { ephemeral: true })]);
    vi.advanceTimersByTime(50);
    expect(sent).toEqual([]);
    expect(feed.snapshot()).toMatchObject({ sessions: [] });
  });

  it("includes pending changes in a snapshot, which a later patch continues", () => {
    vi.useFakeTimers();
    const sent: SessionFeed[] = [];
    const feed = createSessionFeed([], (message) => sent.push(message));
    feed.changed([session("s")]);
    const snapshot = feed.snapshot();
    expect(snapshot).toMatchObject({ seq: 1, sessions: [{ id: "s" }] });
    feed.changed([session("s", [], { title: "t" })]);
    vi.advanceTimersByTime(50);
    expect(sent.at(-1)).toMatchObject({ seq: 2 });
  });
});

describe("createSessionFeed with the host's settings", () => {
  afterEach(() => vi.useRealTimers());

  it("puts the settings in a snapshot and sends a change once, after the session changes made before it", () => {
    vi.useFakeTimers();
    let stored: Record<string, string | null> = { "loci.followUpBehavior": "steer" };
    const sent: SessionFeed[] = [];
    const feed = createSessionFeed([], (message) => sent.push(message), { settings: () => stored });
    expect(feed.snapshot()).toMatchObject({ seq: 0, settings: { "loci.followUpBehavior": "steer" } });

    feed.changed([session("s")]);
    stored = { "loci.followUpBehavior": "queue" };
    feed.settingsChanged({ "loci.followUpBehavior": "queue" });
    feed.settingsChanged({ "loci.followUpBehavior": "queue" });
    expect(sent.map((message) => [message.kind, message.seq])).toEqual([["patch", 1], ["settings", 2]]);
    expect(sent[1]).toMatchObject({ values: { "loci.followUpBehavior": "queue" } });

    // A snapshot already carries the value; a later write of the same value is not news.
    stored = { "loci.followUpBehavior": "steer" };
    expect(feed.snapshot()).toMatchObject({ seq: 2, settings: { "loci.followUpBehavior": "steer" } });
    feed.settingsChanged({ "loci.followUpBehavior": "steer" });
    expect(sent).toHaveLength(2);
  });
});
