// @vitest-environment happy-dom
import { beforeEach, expect, it, vi } from "vitest";
import type { Block } from "../../sessions/model/session";
import {
  agentPreview,
  loadAgentPreviews,
  previewTimeLabel,
  saveAgentPreview,
  subscribeAgentPreviews,
} from "./agentPreview";

beforeEach(() => {
  const stored = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => stored.get(key) ?? null,
    setItem: (key: string, value: string) => stored.set(key, value),
  });
});

const blocks = (...list: Partial<Block>[]) =>
  list.map((block, index) => ({ id: `b${index}`, text: "", ...block })) as Block[];

it("shows the agent's last reply on one line, timed by the message it answers", () => {
  expect(
    agentPreview({
      blocks: blocks(
        { role: "user", text: "Check CI", startedAt: 100 },
        { role: "assistant", text: "Looking into it." },
        { role: "tool", tool: { title: "Run" } as Block["tool"] },
        { role: "assistant", text: "**CI is red** on `main`:\n\n- the lint job fails" },
      ),
    }),
  ).toEqual({ text: "CI is red on main: the lint job fails", at: 100 });
});

it("shows the user's message while no reply has come, and a habit's post with its own time", () => {
  expect(
    agentPreview({
      blocks: blocks(
        { role: "user", text: "Are you there?", startedAt: 5 },
        { role: "assistant", text: "partial", streaming: true },
      ),
    }),
  ).toEqual({ text: "Are you there?", at: 5 });
  expect(
    agentPreview({
      blocks: blocks(
        { role: "user", text: "hi", startedAt: 5 },
        { role: "assistant", text: "hello" },
        { role: "assistant", text: "CI is green again.", agentHabit: { id: "h", name: "CI", at: 900 } },
      ),
    }),
  ).toEqual({ text: "CI is green again.", at: 900 });
});

it("skips app notifications and drafts, and has nothing to show for an empty chat", () => {
  expect(agentPreview({ blocks: [] })).toBeUndefined();
  expect(
    agentPreview({
      blocks: blocks(
        { role: "user", text: "Real message", startedAt: 1 },
        { role: "assistant", text: "Real answer" },
        { role: "user", text: "Finished: Fix CI", agentSessionCompletion: { sessionId: "s", title: "Fix CI", status: "completed" } },
        { role: "user", text: "unsent", draft: true },
      ),
    })?.text,
  ).toBe("Real answer");
  expect(agentPreview({ blocks: blocks({ role: "assistant", text: "x".repeat(300) }) })!.text).toHaveLength(120);
});

it("remembers each agent's latest words and says when they changed", () => {
  const changed = vi.fn();
  const stop = subscribeAgentPreviews(changed);
  expect(saveAgentPreview("a", { text: "Done.", at: 1 })).toBe(true);
  expect(saveAgentPreview("a", { text: "Done.", at: 1 })).toBe(false);
  expect(loadAgentPreviews()).toEqual({ a: { text: "Done.", at: 1 } });
  expect(saveAgentPreview("a", undefined)).toBe(true);
  expect(loadAgentPreviews()).toEqual({});
  expect(changed).toHaveBeenCalledTimes(2);
  stop();
});

it("labels a time the way a contact list does", () => {
  const now = new Date(2026, 9, 9, 15, 0).getTime();
  expect(previewTimeLabel(new Date(2026, 9, 9, 9, 5).getTime(), now)).toBe("9:05 AM");
  expect(previewTimeLabel(new Date(2026, 9, 8, 23, 59).getTime(), now)).toBe("Yesterday");
  expect(previewTimeLabel(new Date(2026, 9, 1, 12, 0).getTime(), now)).toBe("Oct 1");
});
