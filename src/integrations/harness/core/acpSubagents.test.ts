import { describe,expect,it } from "vitest";
import { AcpSubagents, acpAgentInfo } from "./acpSubagents";
import type { HarnessEvent } from "./types";

describe("ACP child routing", () => {
  it("recognizes delegated work carried in a generic tool's input", () => {
    expect(acpAgentInfo({ rawInput: { _toolName: "task", description: "Compare sources", model: "review-model" } }, {}, "other", "Task"))
      .toEqual({ kind: "agent", title: "Compare sources", agentModel: "review-model" });
    expect(acpAgentInfo({ rawInput: { path: "report.md" } }, {}, "read", "Read report"))
      .toBeUndefined();
  });

  it("retains failed child output while keeping successful output out of the saved step", () => {
    const router = new AcpSubagents();
    router.route({}, [{ type: "tool.started", callId: "parent", title: "Compare sources", kind: "agent" }]);
    const input = { parentToolCallId: "parent" };
    router.route(input, [{ type: "tool.started", callId: "read", title: "Read report", kind: "read" }]);
    const failed = router.route({ toolCallId: "read" }, [{ type: "tool.updated", callId: "read", status: "failed", detail: "File missing" }]);
    expect(failed).toEqual([expect.objectContaining({ type: "agent.step", callId: "parent", stepId: "tool:read", detail: "File missing", status: "failed" })]);
    const complete = router.route({ toolCallId: "read" }, [{ type: "tool.updated", callId: "read", status: "completed", detail: "Report contents" }]);
    expect(complete[0]).not.toHaveProperty("detail");
  });
  it("buffers children until the matching row exists, even with simultaneous spawns", () => {
    const router = new AcpSubagents();
    const child = (id: string, text: string): HarnessEvent[] =>
      router.route(
        { update: { _meta: { cursor: { parentToolCallId: id } } } },
        [{ type: "message.delta", text }],
      );
    expect(child("b", "Second child")).toEqual([]);
    expect(child("a", "First child")).toEqual([]);
    const start = (callId: string) =>
      router.route({}, [
        { type: "tool.updated", callId, kind: "agent", title: callId },
      ]);
    expect(start("a")).toEqual([
      expect.objectContaining({ callId: "a", type: "tool.updated" }),
      expect.objectContaining({
        callId: "a",
        type: "agent.step",
        text: "First child",
      }),
    ]);
    expect(start("b")[1]).toMatchObject({ callId: "b", text: "Second child" });
  });

  it("keeps nested work on its ancestor and suppresses child context and completion", () => {
    const router = new AcpSubagents();
    router.route({}, [
      { type: "tool.started", callId: "root", title: "Explore", kind: "agent" },
    ]);
    router.route({ parentToolCallId: "root" }, [
      { type: "tool.started", callId: "nested", title: "Task", kind: "agent" },
    ]);
    const params = { parentToolCallId: "nested" };
    expect(
      router.route(params, [
        { type: "message.delta", text: "Nested answer" },
      ])[0],
    ).toMatchObject({ type: "agent.step", callId: "root" });
    expect(
      router.route(params, [
        { type: "context", used: 999 },
        { type: "message.completed" },
        { type: "session.ended" },
      ]),
    ).toEqual([]);
  });

  it("replaces whole prose snapshots and starts a new step after tools", () => {
    const router = new AcpSubagents();
    router.route({}, [{ type: "tool.started", callId: "a", title: "Explore" }]);
    const params = {
      update: { sessionUpdate: "agent_message", parentToolCallId: "a" },
    };
    const first = router.route(params, [
      { type: "message.delta", text: "Hello" },
    ])[0];
    const repeated = router.route(params, [
      { type: "message.delta", text: "Hello again" },
    ])[0];
    expect(repeated).toMatchObject({ ...first, text: "Hello again" });
    router.route(params, [
      { type: "tool.started", callId: "t", title: "Read" },
    ]);
    expect(
      router.route(params, [{ type: "message.delta", text: "Done" }])[0],
    ).not.toMatchObject({ stepId: (first as { stepId: string }).stepId });
  });
});
