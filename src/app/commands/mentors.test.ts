// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type Block, type Session } from "../../features/sessions/model/session";
import { runCommand } from "./dispatch";
import { providerId, turnState } from "./mentors";
import { agent, testContext } from "./testContext";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
vi.mock("../../integrations/harness/core/availability", () => ({ isHarnessAvailable: () => true }));
vi.mock("../../features/agents/model/agentWorkdir", () => ({ setAgentWorkdir: vi.fn(async (_id: string, path: string) => path) }));

const external = { requestId: "r1", caller: "external" as const };
beforeEach(() => localStorage.clear());

describe("providers", () => {
  it("accept Loci's ids and the names people use", () => {
    expect(providerId("antigravity")).toBe("antigravity");
    expect(providerId("agy")).toBe("antigravity");
    expect(providerId("Claude-Code")).toBe("claude");
    expect(() => providerId("gpt")).toThrow(/Unknown provider/);
  });
});

describe("mentors create and update", () => {
  it("create from a template with a provider and permissions, without switching", async () => {
    const mentors = [agent("a1", "Kern")];
    const { ctx, chatOf } = testContext(mentors, {});
    ctx.createAgent = vi.fn(async () => { mentors.push(agent("new", "Mentor")); return "new"; });
    const created = await runCommand(ctx, "mentors.create", { template: "learning-guide", provider: "agy", mode: "full-access" }, external) as Record<string, unknown>;
    expect(ctx.createAgent).toHaveBeenCalledWith(expect.objectContaining({ id: "learning-guide" }));
    expect(ctx.submission.changeModel).toHaveBeenCalledWith(chatOf("new").id, "antigravity", expect.any(String));
    expect(ctx.submission.changeRuntimeMode).toHaveBeenCalledWith(chatOf("new").id, "full-access");
    expect(ctx.switchAgent).not.toHaveBeenCalled();
    expect(created).toMatchObject({ id: "new", created: true });
  });

  it("refuse unknown templates and settings before creating anything", async () => {
    const { ctx } = testContext([]);
    await expect(runCommand(ctx, "mentors.create", { template: "nope" }, external)).rejects.toMatchObject({ code: "usage" });
    await expect(runCommand(ctx, "mentors.create", { provider: "gpt" }, external)).rejects.toMatchObject({ code: "usage" });
    expect(ctx.createAgent).not.toHaveBeenCalled();
  });

  it("update the look and permissions, and refuse while the mentor is busy", async () => {
    const mentors = [agent("a1", "Kern")];
    localStorage.setItem("loci:agent-roster", JSON.stringify(mentors));
    const { ctx, chatOf } = testContext(mentors);
    await runCommand(ctx, "mentors.update", { mentor: "Kern", mode: "auto" }, external);
    expect(ctx.submission.changeRuntimeMode).toHaveBeenCalledWith(chatOf("a1").id, "auto");
    // A mode chosen from the terminal is the mentor's own choice, as in its settings.
    expect(JSON.parse(localStorage.getItem("loci:agent-roster") ?? "[]")[0].accessMigrated).toBe(true);
    await expect(runCommand(ctx, "mentors.update", { mentor: "a1", mode: "yolo" }, external)).rejects.toMatchObject({ code: "usage" });
    chatOf("a1").busy = true;
    await expect(runCommand(ctx, "mentors.update", { mentor: "a1", mode: "auto" }, external)).rejects.toMatchObject({ code: "busy" });
  });
});

describe("mentors delete", () => {
  it("skips the question with --yes only away from the installed app", async () => {
    const { ctx } = testContext([agent("a1")]);
    await runCommand(ctx, "mentors.delete", { mentor: "a1", yes: true }, external);
    expect(ctx.removeAgent).toHaveBeenLastCalledWith("a1", true);
    ctx.identifier = async () => "com.loci.desktop";
    await runCommand(ctx, "mentors.delete", { mentor: "a1", yes: true }, external);
    expect(ctx.removeAgent).toHaveBeenLastCalledWith("a1", false);
    ctx.removeAgent = vi.fn(async () => false);
    await expect(runCommand(ctx, "mentors.delete", { mentor: "a1" }, external)).rejects.toMatchObject({ code: "declined" });
  });
});

describe("mentors send", () => {
  it("submits once per request and refuses a busy mentor", async () => {
    const { ctx, chatOf } = testContext([agent("a1")]);
    const sent = await runCommand(ctx, "mentors.send", { mentor: "a1", text: "Hello" }, external);
    expect(sent).toEqual({ mentor: "a1", sessionId: chatOf("a1").id, turn: "cli-r1" });
    expect(ctx.submission.submit).toHaveBeenCalledWith(chatOf("a1").id, "Hello", [], { appRequestId: "cli-r1" });
    chatOf("a1").blocks.push({ id: "u", role: "user", text: "Hello", appRequestId: "cli-r1" });
    expect(await runCommand(ctx, "mentors.send", { mentor: "a1", text: "Hello" }, external)).toMatchObject({ alreadySent: true });
    chatOf("a1").busy = true;
    await expect(runCommand(ctx, "mentors.send", { mentor: "a1", text: "Again" }, { requestId: "r2", caller: "external" })).rejects.toMatchObject({ code: "busy" });
  });
});

describe("a turn's state", () => {
  const chat = (blocks: Block[], extra: Partial<Session> = {}): Session => ({ ...newSession("claude", "/x"), id: "chat", blocks, ...extra });
  const user = (extra: Partial<Block> = {}): Block => ({ id: "u", role: "user", text: "Hi", appRequestId: "cli-r1", ...extra });
  it("follows the turn from queued to done", () => {
    expect(turnState(chat([user({ draft: true })]), "cli-r1").status).toBe("queued");
    expect(turnState(chat([user()]), "cli-r1").status).toBe("queued");
    expect(turnState(chat([user({ startedAt: 1 }), { id: "a", role: "assistant", text: "Part" }], { busy: true }), "cli-r1")).toMatchObject({ status: "running", text: "Part" });
    expect(turnState(chat([user({ startedAt: 1 })], { busy: true, pendingQuestion: { title: "Which?", questions: [] } as unknown as Session["pendingQuestion"] }), "cli-r1").status).toBe("needs-you");
    expect(turnState(chat([user({ startedAt: 1, durationMs: 5 }), { id: "a", role: "assistant", text: "One" }, { id: "b", role: "tool", text: "" }, { id: "c", role: "assistant", text: "Two" }, { id: "n", role: "user", text: "Next" }, { id: "d", role: "assistant", text: "Later" }]), "cli-r1"))
      .toMatchObject({ status: "done", text: "One\n\nTwo" });
  });
  it("reports a turn that ended in an error, and one it cannot find", () => {
    expect(turnState(chat([user({ startedAt: 1, durationMs: 5 }), { id: "t", role: "system", text: "Thinking…", statusKey: "k" }, { id: "s", role: "system", text: "Provider crashed", notice: "error" }]), "cli-r1")).toMatchObject({ status: "failed", error: "Provider crashed" });
    expect(() => turnState(chat([]), "cli-r1")).toThrow(/No such turn/);
  });
});
