import { describe, expect, it } from "vitest";
import type { SessionSummary } from "../sessions/data/sessionStore";
import { newSession, type Block, type HarnessId, type Session } from "../sessions/model/session";
import { learnSessionFor } from "./learnSeed";

const CWD = "/work/kubernetes";
const user = (extra: Partial<Block> = {}): Block => ({ id: crypto.randomUUID(), role: "user", text: "x", ...extra });
const loaded = (harness: HarnessId, blocks: Block[], cwd = CWD): Session => ({ ...newSession(harness, cwd), blocks });
const summary = (harness: HarnessId, extra: Partial<SessionSummary> = {}): SessionSummary =>
  ({ id: crypto.randomUUID(), cwd: CWD, harness, model: `${harness}:remembered`, runtimeMode: "auto-accept-edits", title: "t", createdAt: 1, updatedAt: 2, ...extra });
const everything = () => true;

describe("the session opened from a node", () => {
  it("is made like the project's latest learning conversation that is still loaded", () => {
    const codex = loaded("codex", [user({ learn: true })]);
    const session = learnSessionFor(CWD, [loaded("claude", [user()]), codex, loaded("claude", [user({ learn: true })], "/other"), loaded("claude", [user()])], [summary("claude")], everything);
    expect(session.harness).toBe("codex");
    expect(session.cwd).toBe(CWD);
    expect(session.model).toBe(codex.model);
    expect(session.blocks).toEqual([]);
  });

  it("falls back to any loaded conversation of the project that can learn", () => {
    expect(learnSessionFor(CWD, [loaded("cursor", [user()]), loaded("codex", [user()])], [], everything).harness).toBe("codex");
  });

  it("after a restart follows the newest stored conversation on a provider that can learn and is available", () => {
    const stored = [summary("cursor"), summary("codex", { archived: true }), summary("codex", { draft: true }), summary("codex", { model: "codex:gpt-6.1-sol", runtimeMode: "supervised" }), summary("claude")];
    const session = learnSessionFor(CWD, [], stored, everything);
    expect(session).toMatchObject({ harness: "codex", model: "codex:gpt-6.1-sol", runtimeMode: "supervised", cwd: CWD });
    // A provider that is not installed is passed over.
    expect(learnSessionFor(CWD, [], stored, (harness) => harness !== "codex").harness).toBe("claude");
  });

  it("starts on the first available provider when the project has no history", () => {
    expect(learnSessionFor(CWD, [], [], everything).harness).toBe("claude");
    expect(learnSessionFor(CWD, [], [], (harness) => harness === "codex").harness).toBe("codex");
    expect(learnSessionFor(CWD, [], [], () => false).harness).toBe("claude");
  });
});
