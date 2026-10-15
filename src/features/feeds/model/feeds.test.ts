import { describe, expect, it } from "vitest";
import { MAX_CONTEXT_CHARS, v2exTopicMarkdown } from "./feedContext";
import { addSavedNode, parseSavedNodes, parseSource, removeSavedNode, sourceKey, v2exListOf } from "./feedSources";
import { unreadOf, withSeen, withStarred, type FeedItemState } from "./feedState";
import { parseNodeName, type V2exReply, type V2exTopic } from "./v2ex";

const topic: V2exTopic = {
  id: 1247772,
  title: "Linux 装机率",
  url: "https://www.v2ex.com/t/1247772",
  content: "第一行\n第二行",
  node: { name: "linux", title: "Linux" },
  member: { username: "intoext" },
  replies: 2,
  created: 1_791_685_650,
  lastTouched: 1_791_710_090,
};

const reply = (id: number, content: string, username = "bob"): V2exReply => ({ id, content, member: { username }, created: 1_791_685_899 });

describe("V2EX context", () => {
  it("frames the topic as untrusted reference material with replies quoted", () => {
    const text = v2exTopicMarkdown(topic, [reply(1, "同意\n第二段"), reply(2, "+1", "carol")]);
    expect(text).toContain("# Linux 装机率");
    expect(text).toContain("not from the user");
    expect(text).toContain("V2EX › Linux · @intoext");
    expect(text).toContain(topic.url);
    expect(text).toContain("**#1 @bob**");
    expect(text).toContain("> 同意\n> 第二段");
    expect(text).toContain("**#2 @carol**");
  });

  it("drops replies past the budget and says how many", () => {
    const many = Array.from({ length: 50 }, (_, index) => reply(index, "x".repeat(100)));
    const text = v2exTopicMarkdown(topic, many, 1_000);
    expect(text.length).toBeLessThan(1_100);
    expect(text).toMatch(/_\d+ more replies omitted\._$/);
  });

  it("keeps the default budget bounded", () => {
    const many = Array.from({ length: 2_000 }, (_, index) => reply(index, "y".repeat(200)));
    expect(v2exTopicMarkdown(topic, many).length).toBeLessThan(MAX_CONTEXT_CHARS + 100);
  });
});

describe("feed sources", () => {
  it("round-trips source keys and rejects junk", () => {
    for (const source of [{ kind: "v2ex-hot" }, { kind: "v2ex-node", name: "python" }] as const) {
      expect(parseSource(sourceKey(source))).toEqual(source);
    }
    expect(parseSource("v2ex-node:../etc")).toBeNull();
    expect(parseSource("hn")).toBeNull();
    expect(parseSource(null)).toBeNull();
  });

  it("maps topic sources to list requests", () => {
    expect(v2exListOf({ kind: "v2ex-latest" })).toEqual({ kind: "latest" });
    expect(v2exListOf({ kind: "v2ex-node", name: "qna" })).toEqual({ kind: "node", name: "qna" });
    expect(v2exListOf({ kind: "v2ex-starred" })).toBeNull();
  });

  it("sanitizes saved nodes and keeps them unique", () => {
    expect(parseSavedNodes('[{"name":"python","title":"Python"},{"name":"python"},{"name":"bad/name"},{"name":"qna","title":" "}, 3]'))
      .toEqual([{ name: "python", title: "Python" }, { name: "qna", title: "qna" }]);
    expect(parseSavedNodes("not json")).toEqual([]);
    const nodes = addSavedNode([{ name: "a", title: "A" }], { name: "a", title: "A2" });
    expect(nodes).toEqual([{ name: "a", title: "A2" }]);
    expect(removeSavedNode(nodes, "a")).toEqual([]);
  });

  it("reads node names from pasted text", () => {
    expect(parseNodeName("python")).toBe("python");
    expect(parseNodeName(" https://www.v2ex.com/go/create?p=2 ")).toBe("create");
    expect(parseNodeName("/go/qna")).toBe("qna");
    expect(parseNodeName("https://www.v2ex.com/t/123")).toBeNull();
    expect(parseNodeName("two words")).toBeNull();
  });
});

describe("feed state", () => {
  const seen = (count: number): FeedItemState => ({ itemId: "1", seenCount: count, starred: false });

  it("reports new items and new replies", () => {
    expect(unreadOf(undefined, 4)).toEqual({ kind: "new" });
    expect(unreadOf({ itemId: "1", starred: true }, 4)).toEqual({ kind: "new" });
    expect(unreadOf(seen(4), 4)).toBeNull();
    expect(unreadOf(seen(4), 9)).toEqual({ kind: "replies", count: 5 });
    // Deleted replies can shrink the count; that's not unread.
    expect(unreadOf(seen(4), 2)).toBeNull();
  });

  it("applies optimistic marks without losing stars", () => {
    const starred = withStarred(new Map(), "1", true, { id: 1 });
    const next = withSeen(starred, "1", 3);
    expect(next.get("1")).toMatchObject({ starred: true, seenCount: 3, snapshot: { id: 1 } });
    expect(withSeen(next, "1", 1).get("1")?.seenCount).toBe(3);
    expect(withStarred(next, "1", false).get("1")).toMatchObject({ starred: false, seenCount: 3, snapshot: undefined });
  });
});
