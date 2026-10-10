import { beforeEach, expect, it, vi } from "vitest";
import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { getLearningSource } from "./learningStore";
import { askAboutWidget } from "./widgetContext";
import { changeWidgetState, seedWidget } from "./widgetRuntime";

vi.mock("../../agents/model/agent", () => ({ findAgent: vi.fn() }));
vi.mock("../../sessions/model/quoteDraft", () => ({ requestAddToChat: vi.fn() }));
vi.mock("./learningStore", () => ({ getLearningSource: vi.fn(), getLearningWidget: vi.fn(), setLearningWidgetSaved: vi.fn(), setLearningWidgetState: vi.fn(), subscribeLearningChanges: vi.fn() }));
beforeEach(() => vi.clearAllMocks());

it("prefills an agent's current conversation with the latest local state and evidence, without HTML", async () => {
  const owner = { kind: "agent" as const, id: crypto.randomUUID() };
  const ref = { owner, id: "cache" };
  const widget = seedWidget(ref, { id: "cache", title: "Cache", html: "<script>private source</script>", sourceIds: ["evidence"] }, "previous-agent-chat");
  const source = { kind: "file" as const, id: "evidence", title: "Cache implementation", quote: "expiry", path: "/repo/cache.ts" };
  vi.mocked(getLearningSource).mockResolvedValue(source);
  vi.mocked(findAgent).mockReturnValue({ id: owner.id, sessionId: "current-agent-chat", avatar: "", color: "", projects: [] });
  await changeWidgetState(ref, { age: 22 });
  await askAboutWidget(widget, "Why?", "stale");
  expect(requestAddToChat).toHaveBeenCalledWith("Why?", "plain", {
    targetSessionId: "current-agent-chat", sources: [source],
    widgetContext: { owner, id: "cache", title: "Cache", revision: 0, state: { age: 22 }, selection: "stale" },
  });
});

it("keeps ordinary-session questions addressed to the owning session", async () => {
  const owner = { kind: "session" as const, id: crypto.randomUUID() };
  const widget = seedWidget({ owner, id: "trace" }, { id: "trace", title: "Trace", html: "<p>Trace</p>", sourceIds: [] }, owner.id);
  await askAboutWidget(widget, "Explain the next step.");
  expect(requestAddToChat).toHaveBeenCalledWith("Explain the next step.", "plain", expect.objectContaining({ targetSessionId: owner.id }));
  expect(findAgent).not.toHaveBeenCalled();
});
