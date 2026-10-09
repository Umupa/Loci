import { expect, it } from "vitest";
import type { Block } from "./session";
import { latestTurnReply, turnOutcome } from "./turnOutcome";

const blocks = [
  { id: "u1", role: "user", text: "first" },
  { id: "a1", role: "assistant", text: "old answer" },
  { id: "u2", role: "user", text: "second" },
  { id: "a2", role: "assistant", text: "Looking into it." },
  { id: "t1", role: "assistant", text: "", tool: { title: "Read file" } },
  { id: "a3", role: "assistant", text: "Done: two tests fixed." },
  { id: "t2", role: "assistant", text: "tool output", tool: { title: "Run" } },
] as Block[];

it("takes the last prose of the latest turn as its answer", () => {
  expect(latestTurnReply(blocks)).toBe("Done: two tests fixed.");
});

it("never reaches back into an earlier turn", () => {
  expect(latestTurnReply(blocks.slice(0, 3))).toBe("");
  expect(latestTurnReply([])).toBe("");
});

it("carries an error only for a failed turn", () => {
  expect(turnOutcome(blocks, "completed", "ignored")).toEqual({
    status: "completed",
    text: "Done: two tests fixed.",
  });
  expect(turnOutcome(blocks, "cancelled")).toEqual({
    status: "cancelled",
    text: "Done: two tests fixed.",
  });
  expect(turnOutcome([], "failed", " Not signed in ")).toEqual({
    status: "failed",
    text: "",
    error: "Not signed in",
  });
  expect(turnOutcome([], "failed").error).toBe("The turn did not finish.");
});
