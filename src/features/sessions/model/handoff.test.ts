import { describe,expect,it } from "vitest";
import {
appendPreparingHandoff,
appendReadyHandoff,
buildDeterministicHandoff,
buildOutgoingHandoffPrompt,
chooseHandoffBrief,
completeHandoff,
consumeHandoff,
hasSessionEdits,
pendingHandoff,
planComposerSwitch,
sessionChildHarnesses,
shouldAskOutgoingAgent,
userMessagesAfterHandoff,
wrapHandoffPrompt
} from "./handoff";
import { newSession,type Block,type Session } from "./session";

function sessionWith(
  blocks: Block[],
  extra?: Partial<Session>,
): Session {
  return {
    ...newSession("codex", "/tmp/project"),
    blocks,
    ...extra,
  };
}

describe("planComposerSwitch", () => {
  it("only updates the composer on an empty session", () => {
    expect(planComposerSwitch(newSession("codex", "/tmp"), "claude")).toEqual({
      kind: "empty",
      forget: "codex",
    });
  });

  it("arms a handoff for later instead of running it on picker change", () => {
    const session = sessionWith(
      [{ id: "u1", role: "user", text: "hey" }],
      { providerSessionId: "acp-1" },
    );
    expect(planComposerSwitch(session, "claude")).toEqual({
      kind: "arm",
      pending: {
        from: "codex",
        fromModel: session.model,
        fromSettings: session.modelSettings,
        fromProviderSessionId: "acp-1",
      },
    });
  });

  it("reverts to the original provider if the user switches back", () => {
    const session = sessionWith([{ id: "u1", role: "user", text: "hey" }], {
      harness: "claude",
      pendingSwitch: {
        from: "codex",
        fromModel: "codex:composer-2",
        fromSettings: {},
        fromProviderSessionId: "acp-1",
      },
    });
    expect(planComposerSwitch(session, "codex")).toEqual({
      kind: "revert",
      restoreProviderSessionId: "acp-1",
    });
  });
});

describe("deterministic handoff", () => {
  it("recaps the chat and files edited, without a Goal heading", () => {
    const brief = buildDeterministicHandoff(
      sessionWith(
        [
          { id: "u1", role: "user", text: "hey whats up" },
          { id: "a1", role: "assistant", text: "Hey — ready to help." },
          {
            id: "t-read",
            role: "tool",
            text: "Read CHANGELOG.md",
            tool: {
              title: "Read CHANGELOG.md",
              kind: "read",
              preview: { kind: "read", path: "/tmp/project/CHANGELOG.md" },
            },
          },
          {
            id: "t-edit",
            role: "tool",
            text: "Edited src/index.css",
            tool: {
              title: "Edited src/index.css",
              kind: "edit",
              preview: { kind: "write", path: "/tmp/project/src/index.css" },
            },
          },
          { id: "u2", role: "user", text: "add dark mode" },
        ],
        { cwd: "/tmp/project" },
      ),
      "add dark mode",
    );
    expect(brief).not.toMatch(/##\s*Goal/i);
    expect(brief).not.toContain("add dark mode");
    expect(brief).toContain("hey whats up");
    expect(brief).toContain("src/index.css");
    expect(brief).not.toContain("CHANGELOG.md");
  });

  it("labels live task progress separately from an authored plan", () => {
    const brief = buildDeterministicHandoff(
      sessionWith([
        { id: "u1", role: "user", text: "fix it" },
        { id: "tasks", role: "tasks", text: "[x] Inspect\n[~] Implement" },
        { id: "plan", role: "plan", text: "Use two layers." },
      ]),
    );
    expect(brief).toContain("## Plan\nUse two layers.");
    expect(brief).toContain("## Current tasks\n[x] Inspect\n[~] Implement");
  });

  it("keeps a short recent recap instead of the whole transcript", () => {
    const brief = buildDeterministicHandoff(
      sessionWith([
        { id: "u1", role: "user", text: "first" },
        { id: "a1", role: "assistant", text: "long ".repeat(400) },
        { id: "u2", role: "user", text: "second" },
        { id: "a2", role: "assistant", text: "ok" },
        { id: "u3", role: "user", text: "third" },
        {
          id: "a3",
          role: "assistant",
          text: "Ready to dig into agent-os whenever you are. ".repeat(20),
        },
        { id: "u4", role: "user", text: "fourth" },
      ]),
      "fourth",
    );
    expect(brief).not.toMatch(/##\s*Goal/i);
    expect(brief).not.toContain("fourth");
    expect(brief).toContain("third");
    expect(brief).toContain("earlier messages omitted");
    expect(brief).not.toContain("first");
    expect(brief.length).toBeLessThan(2_100);
  });

  it("does not treat a greeting-only chat as having session edits", () => {
    const session = sessionWith([
      { id: "u1", role: "user", text: "hey" },
      { id: "a1", role: "assistant", text: "hello" },
      {
        id: "t1",
        role: "tool",
        text: "Read src/App.tsx",
        tool: {
          title: "Read src/App.tsx",
          kind: "read",
          preview: { kind: "read", path: "/tmp/project/src/App.tsx" },
        },
      },
    ]);
    expect(hasSessionEdits(session)).toBe(false);
    expect(
      shouldAskOutgoingAgent({
        ...session,
        pendingSwitch: {
          from: "codex",
          fromModel: session.model,
          fromSettings: {},
          fromProviderSessionId: "acp-1",
        },
      }),
    ).toBe(false);
  });

  it("prefers a long agent recap over the fallback and drops a Goal heading", () => {
    const agent =
      "## Goal\nadd dark mode\n\n## Session so far\nShipped tokens.\n\n## Files edited in this session\n- src/index.css";
    const session = sessionWith([
      { id: "u1", role: "user", text: "fallback packet" },
    ]);
    expect(chooseHandoffBrief(agent, session)).toContain("Shipped tokens");
    expect(chooseHandoffBrief(agent, session)).toContain("src/index.css");
    expect(chooseHandoffBrief(agent, session)).not.toMatch(/##\s*Goal/i);
    expect(chooseHandoffBrief("too short", session)).toBe(
      "## Session so far\nUser: fallback packet",
    );
  });
});

describe("handoff block lifecycle", () => {
  it("keeps the inject pending until the incoming harness accepts a turn", () => {
    let session = appendPreparingHandoff(
      sessionWith([{ id: "u1", role: "user", text: "go" }]),
      "codex",
      "claude",
    );
    session = completeHandoff(session, "Left: tests");
    expect(pendingHandoff(session)?.text).toContain("Left: tests");
    session = consumeHandoff(session);
    expect(pendingHandoff(session)).toBeNull();
  });

  it("keeps a ready divider pending so a failed first turn can retry the wrap", () => {
    const session = appendReadyHandoff(
      sessionWith([{ id: "u1", role: "user", text: "go" }]),
      "codex",
      "claude",
      "Session so far: go",
    );
    expect(pendingHandoff(session)).toEqual({
      from: "codex",
      to: "claude",
      text: "Session so far: go",
    });
    const afterFailedSend = {
      ...session,
      blocks: [
        ...session.blocks,
        { id: "u2", role: "user", text: "hey what is this" },
        { id: "e1", role: "system", text: "Claude did not start. Claude exited" },
      ],
    };
    expect(pendingHandoff(afterFailedSend)?.from).toBe("codex");
    expect(userMessagesAfterHandoff(afterFailedSend)).toEqual([
      "hey what is this",
    ]);
  });

  it("tracks the outgoing child while a switch is armed or preparing", () => {
    const armed = sessionWith([{ id: "u1", role: "user", text: "go" }], {
      harness: "claude",
      pendingSwitch: {
        from: "codex",
        fromModel: "codex:composer-2",
        fromSettings: {},
      },
    });
    expect(sessionChildHarnesses(armed).sort()).toEqual(["claude", "codex"]);

    const preparing = {
      ...appendPreparingHandoff(
        sessionWith([{ id: "u1", role: "user", text: "go" }]),
        "codex",
        "claude",
      ),
      harness: "claude" as const,
    };
    expect(sessionChildHarnesses(preparing).sort()).toEqual([
      "claude",
      "codex",
    ]);
  });
});

describe("wrapHandoffPrompt", () => {
  it("leads with the user request and says this is not a new session", () => {
    const prompt = wrapHandoffPrompt(
      "Session so far: hello",
      "codex",
      "do the sidebar",
    );
    expect(prompt).toContain("not a new session");
    expect(prompt).toContain("do the sidebar");
    expect(prompt).toContain("Codex");
    expect(prompt.indexOf("do the sidebar")).toBeLessThan(
      prompt.indexOf("Session so far"),
    );
  });

  it("does not forward a Goal heading in the recap", () => {
    const prompt = wrapHandoffPrompt(
      "## Goal\nhey whats happening\n\n## Session so far\nUser: hey",
      "codex",
      "hey whats happening",
    );
    expect(prompt).toContain("hey whats happening");
    expect(prompt).toContain("Session so far");
    expect(prompt).not.toMatch(/##\s*Goal/i);
  });

  it("includes user messages sent after the switch when retrying", () => {
    const prompt = wrapHandoffPrompt(
      "## Session so far\nhey what is this",
      "codex",
      "hello",
      ["hey what is this"],
    );
    expect(prompt).toContain("hello");
    expect(prompt).toContain("hey what is this");
    expect(prompt).toContain("before this message");
  });

  it("tells the outgoing agent not to inspect the project", () => {
    expect(buildOutgoingHandoffPrompt("add dark mode")).toContain(
      "Do not inspect the project",
    );
    expect(buildOutgoingHandoffPrompt("add dark mode")).toContain(
      "add dark mode",
    );
    expect(buildOutgoingHandoffPrompt("add dark mode")).toContain(
      "Do not paste the whole transcript",
    );
    expect(buildOutgoingHandoffPrompt("add dark mode")).not.toContain(
      "Goal (the user request)",
    );
  });
});
