// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}));

import { newSession, type Block, type Session } from "../../sessions/model/session";
import {
  archiveOlderTurns,
  canArchive,
  LIVE_TURNS_KEPT,
  LIVE_TURNS_MAX,
  loadTranscriptPage,
  planArchive,
  readAgentConversation,
  type TranscriptPage,
} from "./agentTranscript";

/** `count` exchanges numbered from `from`: a question, a tool step and an answer each. */
function turns(count: number, from = 1): Block[] {
  return Array.from({ length: count }, (_, index) => {
    const n = from + index;
    return [
      { id: `u${n}`, role: "user", text: `Question ${n}` },
      { id: `t${n}`, role: "tool", text: "", tool: { title: "Read" } },
      { id: `a${n}`, role: "assistant", text: `Answer ${n}` },
    ] as Block[];
  }).flat();
}

function chat(blocks: Block[]): Session {
  return { ...newSession("codex", "/home/me", "codex:test"), id: "chat", blocks };
}

beforeEach(() => invoke.mockReset());

it("leaves a short chat alone, and cuts a long one at a turn boundary", () => {
  expect(planArchive(turns(LIVE_TURNS_MAX))).toBeUndefined();
  const habitPost: Block = { id: "h", role: "assistant", text: "Posted before any message" };
  const plan = planArchive([habitPost, ...turns(LIVE_TURNS_MAX + 5)])!;
  expect(plan.kept[0].id).toBe(`u${LIVE_TURNS_MAX + 5 - LIVE_TURNS_KEPT + 1}`);
  expect(plan.kept.filter((block) => block.role === "user")).toHaveLength(LIVE_TURNS_KEPT);
  // What came before the first message goes with the oldest turns.
  expect(plan.archived[0]).toBe(habitPost);
  expect(plan.archived.at(-1)!.id).toBe(`a${LIVE_TURNS_MAX + 5 - LIVE_TURNS_KEPT}`);
  expect(plan.archived.length + plan.kept.length).toBe(1 + (LIVE_TURNS_MAX + 5) * 3);
});

it("archives only a chat with nothing in motion", () => {
  const idle = chat(turns(1));
  expect(canArchive(idle)).toBe(true);
  expect(canArchive({ ...idle, busy: true })).toBe(false);
  expect(canArchive({ ...idle, queuedMessages: [{ id: "q", text: "x", attachments: [] }] })).toBe(false);
  expect(canArchive({ ...idle, blocks: [{ id: "p", role: "approval", text: "", approval: { requestId: 1 } }] })).toBe(false);
});

it("writes the page before giving back what stays", async () => {
  invoke.mockResolvedValue(1);
  const session = chat(turns(LIVE_TURNS_MAX + 1));
  const kept = await archiveOlderTurns(session);
  expect(kept![0].id).toBe(`u${LIVE_TURNS_MAX + 1 - LIVE_TURNS_KEPT + 1}`);
  expect(invoke).toHaveBeenCalledOnce();
  const [command, args] = invoke.mock.calls[0] as [string, { sessionId: string; firstBlockId: string; blocksJson: string }];
  expect(command).toBe("agent_transcript_append");
  expect(args).toMatchObject({ sessionId: "chat", firstBlockId: "u1" });
  const page = JSON.parse(args.blocksJson) as Block[];
  expect(page.at(-1)!.id).toBe(`a${LIVE_TURNS_MAX + 1 - LIVE_TURNS_KEPT}`);
  expect(page).toHaveLength((LIVE_TURNS_MAX + 1 - LIVE_TURNS_KEPT) * 3);
});

it("keeps the chat whole when the page could not be written", async () => {
  const long = chat(turns(LIVE_TURNS_MAX + 1));
  const short = chat(turns(3));
  invoke.mockImplementation(async (command: string) => {
    if (command === "agent_transcript_append") throw new Error("disk");
  });
  await expect(archiveOlderTurns(long)).rejects.toThrow("disk");
  expect(await archiveOlderTurns(short)).toBeUndefined();
});

it("reads a page back as blocks, and nothing when there is none", async () => {
  invoke.mockResolvedValueOnce({ seq: 2, blocksJson: JSON.stringify(turns(1)), hasOlder: true });
  expect(await loadTranscriptPage("chat")).toMatchObject({ seq: 2, hasOlder: true, blocks: [{ id: "u1" }, { id: "t1" }, { id: "a1" }] });
  expect(invoke).toHaveBeenCalledWith("agent_transcript_page", { sessionId: "chat", before: null });
  invoke.mockResolvedValueOnce(null);
  expect(await loadTranscriptPage("chat", 2)).toBeUndefined();
  invoke.mockResolvedValueOnce({ seq: 1, blocksJson: "not json", hasOlder: false });
  expect((await loadTranscriptPage("chat", 2))!.blocks).toEqual([]);
});

/** Two archived pages (turns 1-2, then 3-4) behind a live window of turns 5-6. */
function archive() {
  const pages: TranscriptPage[] = [
    { seq: 1, blocks: turns(2, 1), hasOlder: false },
    { seq: 2, blocks: turns(2, 3), hasOlder: true },
  ];
  const loadPage = vi.fn(async (_id: string, before?: number) =>
    [...pages].reverse().find((page) => before == null || page.seq < before));
  return { session: chat(turns(2, 5)), loadPage };
}

it("answers from the live window without touching the archive, and says more remains", async () => {
  const { session, loadPage } = archive();
  const result = await readAgentConversation(session, { limit: 2 }, loadPage);
  expect(result.turns.map((turn) => turn.turnId)).toEqual(["u5", "u6"]);
  expect(result.nextBefore).toBe("u5");
  expect(loadPage).toHaveBeenCalledOnce();
});

it("pages back through the archive to the first message", async () => {
  const { session, loadPage } = archive();
  const second = await readAgentConversation(session, { limit: 3, before: "u5" }, loadPage);
  expect(second.turns.map((turn) => turn.turnId)).toEqual(["u2", "u3", "u4"]);
  expect(second.turns[2].assistant?.text).toBe("Answer 4");
  expect(second.nextBefore).toBe("u2");
  const first = await readAgentConversation(session, { limit: 3, before: "u2" }, loadPage);
  expect(first.turns.map((turn) => turn.turnId)).toEqual(["u1"]);
  expect(first.nextBefore).toBeNull();
});

it("fills a short live window from the archive, and rejects a cursor that is nowhere", async () => {
  const { session, loadPage } = archive();
  const result = await readAgentConversation(session, { limit: 3 }, loadPage);
  expect(result.turns.map((turn) => turn.turnId)).toEqual(["u4", "u5", "u6"]);
  await expect(readAgentConversation(session, { before: "nope" }, loadPage)).rejects.toThrow("before is not a turn ID");
  await expect(readAgentConversation(session, { limit: 9 }, loadPage)).rejects.toThrow("limit must be");
});
