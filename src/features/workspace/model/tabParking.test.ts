import { afterEach, describe, expect, it } from "vitest";
import { newSession, type Session } from "../../sessions/model/session";
import { setComposerDraft } from "../../sessions/model/draftCache";
import { setFileDraft } from "../../files/model/fileDrafts";
import { fileLeaf, newTab, placeLayout, type WorkspaceTab } from "./layout";
import { attentionOrder, heldTabIds, idleTabIds, isParkable, parkingCandidates, trackTabGrowth } from "./tabParking";
import type { Tab } from "./tabSummary";

function tab(id: string, over: Partial<Tab> = {}): Tab {
  return { id, title: id, project: "p", more: [], sessionCount: 1, harnesses: ["claude"], busyHarnesses: [], status: "idle", ...over };
}
const ids = (n: number, over: (i: number) => Partial<Tab> = () => ({})) => Array.from({ length: n }, (_, i) => tab(`t${i}`, over(i)));
const none = new Set<string>();

describe("what may be parked", () => {
  it("only idle, unpinned, non-empty tabs that are not in view and hold nothing unfinished", () => {
    expect(isParkable(tab("a"), "x", none)).toBe(true);
    expect(isParkable(tab("a"), "a", none)).toBe(false);
    expect(isParkable(tab("a", { pinned: true }), "x", none)).toBe(false);
    expect(isParkable(tab("a", { blank: true }), "x", none)).toBe(false);
    for (const status of ["busy", "approval", "done"] as const) expect(isParkable(tab("a", { status }), "x", none)).toBe(false);
    expect(isParkable(tab("a"), "x", new Set(["a"]))).toBe(false);
    // A parent is live work while what it started still is.
    expect(isParkable(tab("a", { descendantCount: 2, descendantStatus: "busy" }), "x", none)).toBe(false);
    expect(isParkable(tab("a", { descendantCount: 2, descendantStatus: "idle" }), "x", none)).toBe(true);
  });

  it("picks the longest untouched first, but only as many as the limit is exceeded by", () => {
    const tabs = ids(8);
    // t5 was used most recently, then t1; the rest were never opened this session.
    const picked = parkingCandidates({ tabs, activeId: "t5", recent: ["t5", "t1"], held: none, limit: 5 });
    expect(picked).toEqual(["t0", "t2", "t3"]);
    expect(parkingCandidates({ tabs, activeId: "t5", recent: ["t5", "t1"], held: none, limit: 8 })).toEqual([]);
    expect(parkingCandidates({ tabs, activeId: "t5", recent: [], held: none, limit: 0 })).toEqual([]);
  });

  it("parks older used tabs once the unvisited ones run out", () => {
    const tabs = ids(4);
    expect(parkingCandidates({ tabs, activeId: "t3", recent: ["t3", "t0", "t1", "t2"], held: none, limit: 2 })).toEqual(["t2", "t1"]);
  });

  it("parks fewer than asked when too many tabs are busy or held", () => {
    const tabs = ids(6, (i) => (i < 4 ? { status: "busy" } : {}));
    expect(parkingCandidates({ tabs, activeId: "t5", recent: [], held: none, limit: 2 })).toEqual(["t4"]);
  });

  it("lists every idle tab for the close-idle action", () => {
    const tabs = ids(5, (i) => (i === 1 ? { pinned: true } : i === 3 ? { status: "done" } : {}));
    expect(idleTabIds(tabs, "t0", none)).toEqual(["t2", "t4"]);
  });
});

describe("attentionOrder", () => {
  it("puts approvals before finished tabs and leaves out the tab in view", () => {
    const tabs = ids(5, (i) => (i === 1 ? { status: "done" } : i === 2 ? { status: "approval" } : i === 4 ? { status: "approval" } : {}));
    expect(attentionOrder(tabs, "t4")).toEqual(["t2", "t1"]);
    expect(attentionOrder(ids(3), "t0")).toEqual([]);
  });
});

describe("heldTabIds", () => {
  afterEach(() => { setComposerDraft("held", ""); setFileDraft("/p/a.md", null); });

  it("flags tabs with a half-written message, a queued follow-up or an unsaved file", () => {
    const quiet: Session = { ...newSession("claude", "/p"), id: "quiet" };
    const typing: Session = { ...newSession("claude", "/p"), id: "held" };
    const queued: Session = { ...newSession("claude", "/p"), id: "queued", queuedMessages: [{ id: "m", text: "later" } as never] };
    const tabs: WorkspaceTab[] = [newTab("quiet"), newTab("held"), newTab("queued"), { ...newTab("file-host"), layout: placeLayout(newTab("file-host").layout, fileLeaf("/p/a.md"), "file-host", "right") }];
    setComposerDraft("held", "half a sentence");
    setFileDraft("/p/a.md", { text: "edited", base: "" });
    const sessions = [quiet, typing, queued, { ...newSession("claude", "/p"), id: "file-host" }];
    const held = heldTabIds(tabs, sessions);
    expect([...held].sort()).toEqual(tabs.filter((t) => t.id !== tabs[0].id).map((t) => t.id).sort());
    expect(held.has(tabs[0].id)).toBe(false);
  });
});

describe("trackTabGrowth", () => {
  it("counts only a tab opened in the project being viewed as growth", () => {
    const first = trackTabGrowth(null, "/a", 12);
    expect(first.grew).toBe(false);
    expect(trackTabGrowth(first.mark, "/a", 13).grew).toBe(true);
    expect(trackTabGrowth(first.mark, "/a", 12).grew).toBe(false);
    expect(trackTabGrowth(first.mark, "/a", 9).grew).toBe(false);
    // Looking at another project with more tabs is not growth, and neither is coming back.
    const elsewhere = trackTabGrowth(first.mark, "/b", 20);
    expect(elsewhere.grew).toBe(false);
    expect(trackTabGrowth(elsewhere.mark, "/a", 12).grew).toBe(false);
  });
});
