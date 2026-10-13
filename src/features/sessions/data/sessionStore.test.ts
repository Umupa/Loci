import { describe,expect,it } from "vitest";
import { appendUser,applyHarnessEvents } from "../../../integrations/harness/core/apply";
import { mapCodexNotification } from "../../../integrations/harness/providers/codex/codexProtocol";
import {
newSession,
type Block,
type BtwThread,
type Session,
} from "../model/session";
import { toolCallLabel } from "../model/transcriptActivity";
import {
backfillClaudeShellCommands,
backfillCodexShellCommands,
isPersistableId,
persistFingerprint,
sanitizeSessionForPersist
} from "./sessionStore";
import { hydrateStoredBlocks } from "./sessionStore";

it("persists and hydrates source quotes on user turns", () => {
  const context = {
    sources: [{ id: "source", kind: "conversation" as const, title: "Experiment", quote: "The sender remained blocked.", sessionId: "session", blockId: "tool:42" }],
  };
  const initial = newSession("codex", "/project");
  initial.blocks = [{ id: "question", role: "user", text: "Why?", ...context }];
  const stored = sanitizeSessionForPersist(initial);
  expect(stored.blocks[0]).toMatchObject(context);
  expect(hydrateStoredBlocks(JSON.parse(JSON.stringify(stored.blocks)))[0]).toMatchObject(context);
});

describe("Claude Shell row recovery", () => {
  it("restores only matching placeholder rows and preserves tool output", () => {
    const blocks: Block[] = [
      {
        id: "shell",
        role: "tool",
        text: "Shell",
        tool: {
          callId: "toolu_shell",
          title: "Shell",
          kind: "execute",
          status: "completed",
          detail: "tests passed",
        },
      },
      {
        id: "read",
        role: "tool",
        text: "Read file.ts",
        tool: { callId: "toolu_read", kind: "read" },
      },
    ];
    const command = `npm run check:web ${"--filter tests ".repeat(20)}`.trim();
    const repaired = backfillClaudeShellCommands(blocks, {
      toolu_shell: command,
      toolu_read: "ignore me",
    });
    expect(repaired[0]).toMatchObject({
      text: command,
      tool: { title: command, status: "completed", detail: "tests passed" },
    });
    expect(repaired[1]).toBe(blocks[1]);
    expect(backfillClaudeShellCommands(repaired, {})).toBe(repaired);
  });
});

describe("Codex Shell row recovery", () => {
  it("relabels from the command saved on the row, keeping redactions", () => {
    // The command Codex sent with the item is already on the row as its preview
    // title. Reading it back means whatever Codex redacted stays redacted.
    const redacted = "/usr/bin/zsh -lc 'curl -H \"token=[redacted]\" example'";
    const blocks: Block[] = [
      {
        id: "shell",
        role: "tool",
        text: "Shell",
        tool: {
          callId: "exec-1",
          title: "Shell",
          kind: "execute",
          preview: { kind: "shell", title: redacted },
        },
      },
    ];
    const repaired = backfillCodexShellCommands(blocks);
    expect(repaired[0].text).not.toBe("Shell");
    expect(repaired[0].tool?.preview?.title).toContain("[redacted]");
  });

  it("leaves a row with no usable saved command as it is", () => {
    // A weak preview title names no command, so there is nothing to relabel
    // from and the row keeps its placeholder.
    const blocks: Block[] = [
      {
        id: "shell",
        role: "tool",
        text: "Shell",
        tool: {
          callId: "exec-1",
          title: "Shell",
          kind: "execute",
          preview: { kind: "shell", title: "Shell" },
        },
      },
    ];
    expect(backfillCodexShellCommands(blocks)).toBe(blocks);
  });

  it("labels placeholder rows with the saved command and rebuilds the preview", () => {
    const blocks: Block[] = [
      {
        id: "shell",
        role: "tool",
        text: "Shell",
        tool: {
          callId: "exec-1",
          title: "Shell",
          kind: "execute",
          status: "failed",
          detail: "exit 1",
          preview: {
            kind: "shell",
            title: "rg --files -g AGENTS.md -g '!node_modules'",
          },
        },
      },
      {
        id: "read",
        role: "tool",
        text: "Read file.ts",
        tool: { callId: "exec-2", kind: "read" },
      },
    ];
    const repaired = backfillCodexShellCommands(blocks);
    expect(repaired[0]).toMatchObject({
      text: "Find files",
      tool: {
        title: "Find files",
        status: "failed",
        detail: "exit 1",
        preview: { kind: "shell", title: "rg --files -g AGENTS.md -g '!node_modules'" },
      },
    });
    expect(repaired[1]).toBe(blocks[1]);
    expect(backfillCodexShellCommands(repaired)).toBe(repaired);
  });

  it("keeps the raw command when no readable intent is inferred", () => {
    const blocks: Block[] = [
      {
        id: "shell",
        role: "tool",
        text: "Shell",
        tool: {
          callId: "exec-3",
          title: "Shell",
          kind: "execute",
          preview: { kind: "shell", title: "git commit -m 'Fix shell labels'" },
        },
      },
    ];
    const repaired = backfillCodexShellCommands(blocks);
    expect(repaired[0].text).toBe("git commit -m 'Fix shell labels'");
  });

  // A row repaired from the saved preview has to read the same as one rendered
  // live, or reopening a session would relabel work the user already saw.
  it("labels a recovered row exactly as the live item does", () => {
    // Captured from `codex app-server`: the reported session's middle row was
    // `rg --files -g AGENTS.md`, which Codex labels a path-less `listFiles`.
    const item = {
      type: "commandExecution",
      id: "exec-88885872",
      status: "inProgress",
      command: `/usr/bin/zsh -lc "rg --files -g AGENTS.md -g '"'"'!node_modules'"'"'"`,
      commandActions: [
        { type: "listFiles", command: "rg --files -g AGENTS.md -g '!node_modules'", path: null },
      ],
    };
    let live = newSession("codex", "/home/me/proj");
    live = applyHarnessEvents(live, mapCodexNotification("item/started", { item }).events);
    const liveRow = live.blocks[0];

    // The same row as the buggy build saved it. No recovered map: the command
    // is already on the row, which is how it reads in production.
    const saved: Block[] = [
      {
        id: "e84ab067",
        role: "tool",
        text: "Shell",
        tool: { ...liveRow.tool, title: "Shell" },
      },
    ];
    const [recovered] = backfillCodexShellCommands(saved);

    expect(recovered.text).not.toBe("Shell");
    expect(recovered.text).toBe(liveRow.text);
    expect(recovered.tool?.title).toBe(liveRow.tool?.title);
    expect(toolCallLabel(recovered, "/home/me/proj")).toBe(
      toolCallLabel(liveRow, "/home/me/proj"),
    );
  });
});

describe("isPersistableId", () => {
  it("accepts alphanumeric ids with hyphens and underscores", () => {
    expect(isPersistableId("acp-session-1")).toBe(true);
    expect(isPersistableId("abc_123")).toBe(true);
  });

  it("rejects filesystem paths", () => {
    expect(isPersistableId("/Users/me/provider/sessions/abc.jsonl")).toBe(
      false,
    );
  });
});

describe("persisting a subagent's trail", () => {
  const withRun = (steps: Block["agentRun"]) => {
    const session = newSession("claude", "/tmp/project");
    session.blocks = [
      {
        id: "a1",
        role: "tool",
        text: "Correctness review",
        tool: { callId: "agent-1", kind: "agent", status: "completed" },
        agentRun: steps,
      },
    ];
    return sanitizeSessionForPersist(session)?.blocks[0].agentRun;
  };

  it("keeps the run so a reopened session can still be inspected", () => {
    expect(
      withRun({
        name: "Correctness review",
        agentType: "code-reviewer",
        steps: [
          {
            id: "s1",
            kind: "tool",
            text: "Read src/App.tsx",
            toolKind: "read",
            status: "failed",
            detail: "File not found",
          },
          { id: "s2", kind: "message", text: "Nothing to flag." },
        ],
      }),
    ).toEqual({
      name: "Correctness review",
      agentType: "code-reviewer",
      steps: [
        {
          id: "s1",
          kind: "tool",
          text: "Read src/App.tsx",
          toolKind: "read",
          status: "failed",
          detail: "File not found",
        },
        { id: "s2", kind: "message", text: "Nothing to flag." },
      ],
    });
  });

  it("drops steps a provider left malformed", () => {
    expect(
      withRun({
        name: "Correctness review",
        steps: [
          { id: "", kind: "tool", text: "Read" },
          { id: "s2", kind: "bogus", text: "Read" },
          { id: "s3", kind: "tool", text: "Read src/App.tsx" },
        ] as never,
      })?.steps,
    ).toEqual([{ id: "s3", kind: "tool", text: "Read src/App.tsx" }]);
  });

  it("keeps only the tail of a long run", () => {
    const steps = Array.from({ length: 260 }, (_, index) => ({
      id: `s${index}`,
      kind: "tool" as const,
      text: `Read file-${index}.ts`,
    }));
    const saved = withRun({ name: "Correctness review", steps });
    expect(saved?.steps).toHaveLength(100);
    expect(saved?.steps[99].id).toBe("s259");
  });
});

describe("sanitizeSessionForPersist", () => {
  it("keeps what an agent's chat needs to tell a habit's post and a completion report apart", () => {
    const session = newSession("codex", "/home/me", "codex:test");
    session.blocks = [
      { id: "u", role: "user", text: "results", agentSessionCompletion: { sessionId: "s1", title: "Fix CI", status: "failed", sessionCount: 2 } },
      { id: "h", role: "assistant", text: "CI is red.", agentHabit: { id: "h1", name: "Morning CI check", at: 5 } },
      { id: "q", role: "approval", text: "", approval: { requestId: 1_000_000_001 }, agentHabit: { id: "h1", name: "Morning CI check", at: 6 } },
    ];
    const saved = sanitizeSessionForPersist(session).blocks;
    expect(saved[0].agentSessionCompletion).toEqual({ sessionId: "s1", title: "Fix CI", status: "failed", sessionCount: 2 });
    expect(saved[1].agentHabit).toEqual({ id: "h1", name: "Morning CI check", at: 5 });
    // A relayed question cannot be answered after a restart, so it is not kept.
    expect(saved).toHaveLength(2);
  });

  it("keeps the stripped /operator turn marker for later turns", () => {
    const submitted = appendUser(newSession("codex", "/repo"), "list notes", [], {
      loci: true,
    });
    expect(sanitizeSessionForPersist(submitted).blocks[0]).toMatchObject({
      role: "user",
      text: "list notes",
      loci: true,
    });
  });

  it("persists the request ID for an agent-sent follow-up", () => {
    const submitted = appendUser(newSession("codex", "/repo"), "Continue", [], {
      appRequestId: "app-source-request-1",
    });
    expect(sanitizeSessionForPersist(submitted).blocks[0]).toMatchObject({
      text: "Continue",
      appRequestId: "app-source-request-1",
    });
  });

  it("persists the request ID on an unsent agent-created draft", () => {
    const session = newSession("codex", "/repo");
    session.blocks = [
      {
        id: "draft",
        role: "user",
        text: "Review later",
        draft: true,
        appRequestId: "app-source-draft-1",
      },
    ];
    expect(sanitizeSessionForPersist(session).blocks[0]).toMatchObject({
      draft: true,
      appRequestId: "app-source-draft-1",
    });
  });

  it("keeps an unsent user turn appended to a started thread", () => {
    const session = newSession("codex", "/repo");
    session.blocks = [
      { id: "sent", role: "user", text: "Start here" },
      { id: "reply", role: "assistant", text: "Done" },
      { id: "draft", role: "user", text: "Explore this", draft: true },
    ];
    expect(sanitizeSessionForPersist(session).blocks).toEqual([
      { id: "sent", role: "user", text: "Start here" },
      { id: "reply", role: "assistant", text: "Done" },
      { id: "draft", role: "user", text: "Explore this", draft: true },
    ]);
  });

  it("persists generated image metadata without binary payloads", () => {
    const session = newSession("codex", "/repo");
    session.blocks = [
      { id: "u", role: "user", text: "Draw this" },
      {
        id: "image",
        role: "image",
        text: "",
        image: {
          path: "/app-data/generated-images/image.png",
          name: "generated-image",
          mimeType: "image/png",
          size: 8,
          alt: "A clean product photo",
        },
      },
    ];

    expect(sanitizeSessionForPersist(session).blocks[1]).toEqual({
      id: "image",
      role: "image",
      text: "",
      image: {
        path: "/app-data/generated-images/image.png",
        name: "generated-image",
        mimeType: "image/png",
        size: 8,
        alt: "A clean product photo",
      },
    });
  });

  it("drops malformed generated image metadata", () => {
    const session = newSession("codex", "/repo");
    session.blocks = [
      { id: "u", role: "user", text: "Draw this" },
      {
        id: "image",
        role: "image",
        text: "",
        image: {
          path: "",
          name: "generated-image",
          mimeType: "image/png",
          size: 0,
        },
      },
    ];

    expect(sanitizeSessionForPersist(session).blocks).toEqual([
      { id: "u", role: "user", text: "Draw this" },
    ]);
  });
  it("persists model provenance recorded on a user turn", () => {
    const session = newSession("claude", "/tmp/project", "claude:opus-5");
    session.blocks = [
      {
        id: "u1",
        role: "user",
        text: "remember this",
        turnModel: {
          harness: "claude",
          id: "claude:opus-5",
          name: "Claude Opus 5",
        },
      },
    ];

    expect(sanitizeSessionForPersist(session).blocks[0]?.turnModel).toEqual({
      harness: "claude",
      id: "claude:opus-5",
      name: "Claude Opus 5",
    });
  });

  it("persists a BTW thread's model and provider settings", () => {
    const session = newSession("codex", "/tmp/project");
    const thread: BtwThread = {
      id: "btw-1",
      sourceEndBlockId: "u1",
      createdAt: 1,
      updatedAt: 2,
      status: "ready",
      messages: [
        { id: "m1", role: "user", text: "Why?", createdAt: 1 },
        { id: "m2", role: "assistant", text: "Because.", createdAt: 2 },
      ],
      model: "codex:gpt-5.4",
      modelSettings: {
        reasoningEffort: "high",
        serviceTier: "fast",
      },
    };
    session.blocks = [
      { id: "u1", role: "user", text: "Explain this", btwThreads: [thread] },
    ];

    expect(sanitizeSessionForPersist(session).blocks[0]?.btwThreads).toEqual([
      thread,
    ]);
  });

  it("persists provider metrics recorded on a user turn", () => {
    const session = newSession("claude", "/tmp/project");
    session.blocks = [
      {
        id: "u1",
        role: "user",
        text: "remember this",
        turnMetrics: {
          inputTokens: 100,
          outputTokens: 20,
          cacheReadTokens: 80,
          cacheHitPercent: 40,
        },
      },
    ];

    expect(sanitizeSessionForPersist(session).blocks[0]?.turnMetrics).toEqual({
      inputTokens: 100,
      outputTokens: 20,
      cacheReadTokens: 80,
      cacheHitPercent: 40,
    });
  });

  it("omits a path-like provider session id so upsert can still snapshot git", () => {
    const session = newSession("codex", "/tmp/project");
    session.providerSessionId = "/Users/me/provider/sessions/abc.jsonl";
    session.blocks = [{ id: "u1", role: "user", text: "hey" }];

    expect(
      sanitizeSessionForPersist(session).providerSessionId,
    ).toBeUndefined();
  });

  it("keeps a UUID provider session id", () => {
    const session = newSession("codex", "/tmp/project");
    session.providerSessionId = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
    session.blocks = [{ id: "u1", role: "user", text: "hey" }];

    expect(sanitizeSessionForPersist(session).providerSessionId).toBe(
      "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    );
  });

  it("keeps a handoff divider and settles a preparing one", () => {
    const session = newSession("codex", "/tmp/project");
    session.blocks = [
      { id: "u1", role: "user", text: "hey" },
      {
        id: "h1",
        role: "handoff",
        text: "",
        handoff: { from: "codex", to: "claude", status: "preparing" },
      },
    ];
    const persisted = sanitizeSessionForPersist(session);
    expect(persisted.blocks[1]).toMatchObject({
      role: "handoff",
      handoff: { from: "codex", to: "claude", status: "ready", pending: true },
    });
  });

  it("keeps a notice flag on system blocks and drops anything else", () => {
    const session = newSession("codex", "/tmp/project");
    session.blocks = [
      {
        id: "e1",
        role: "system",
        text: "Provider connection lost",
        notice: "error",
      },
      {
        id: "i1",
        role: "system",
        text: "Turn interrupted when Loci quit.",
        notice: "interrupt",
      },
      {
        id: "b1",
        role: "system",
        text: "Mystery",
        notice: "mystery" as Block["notice"],
      },
      {
        id: "a1",
        role: "assistant",
        text: "hi",
        notice: "error" as Block["notice"],
      },
    ];

    const persisted = sanitizeSessionForPersist(session).blocks;
    expect(persisted[0]?.notice).toBe("error");
    expect(persisted[1]?.notice).toBe("interrupt");
    expect(persisted[2]?.notice).toBeUndefined();
    expect(persisted[3]?.notice).toBeUndefined();
  });

  it("keeps a note card on the user turn without the note body", () => {
    const session = newSession("codex", "/tmp/project");
    session.blocks = [
      {
        id: "u1",
        role: "user",
        text: "hi",
        noteCard: {
          id: "n1",
          slug: "overview",
          title: "agent-os project overview",
          sourceCwd: "/tmp/project",
        },
      },
    ];
    expect(sanitizeSessionForPersist(session).blocks[0]).toEqual({
      id: "u1",
      role: "user",
      text: "hi",
      noteCard: {
        id: "n1",
        slug: "overview",
        title: "agent-os project overview",
        sourceCwd: "/tmp/project",
      },
    });
  });

  it("keeps structured task lists", () => {
    const session = newSession("codex", "/tmp/project");
    session.blocks = [
      { id: "u1", role: "user", text: "fix it" },
      {
        id: "tasks1",
        role: "tasks",
        text: "[x] Inspect\n[~] Implement",
        taskList: {
          key: "turn_1",
          explanation: "Inspection complete.",
          items: [
            { id: "1", text: "Inspect", status: "completed" },
            { id: "2", text: "Implement", status: "in_progress" },
          ],
        },
      },
    ];
    expect(sanitizeSessionForPersist(session).blocks[1]).toEqual(
      session.blocks[1],
    );
  });
});

describe("persistFingerprint", () => {
  const user: Block = { id: "u1", role: "user", text: "hi" };
  const answer: Block = { id: "a1", role: "assistant", text: "done" };

  // One base session: `newSession` mints a fresh id, and the id is part of the
  // fingerprint, so variants have to be spread off a single session.
  const base = (blocks: Block[] = [user, answer]): Session => ({
    ...newSession("codex", "/tmp/project"),
    blocks,
  });

  it("is stable while nothing changes", () => {
    const session = base();
    expect(persistFingerprint(session)).toBe(persistFingerprint(session));
  });

  it("matches a copy holding the same blocks", () => {
    const session = base();
    expect(persistFingerprint({ ...session })).toBe(
      persistFingerprint(session),
    );
  });

  it("changes when a block in the middle is replaced", () => {
    const tool: Block = {
      id: "t1",
      role: "tool",
      text: "run",
      tool: { status: "running" },
    };
    const before = base([user, tool, answer]);
    const after = {
      ...before,
      blocks: [user, { ...tool, tool: { status: "completed" } }, answer],
    };
    expect(persistFingerprint(after)).not.toBe(persistFingerprint(before));
  });

  it("changes when an approval is decided", () => {
    const approval: Block = {
      id: "p1",
      role: "approval",
      text: "allow?",
      approval: { requestId: 1 },
    };
    const before = base([user, approval]);
    const after = {
      ...before,
      blocks: [
        user,
        { ...approval, approval: { requestId: 1, decided: "allow" as const } },
      ],
    };
    expect(persistFingerprint(after)).not.toBe(persistFingerprint(before));
  });

  it("changes when a block is appended", () => {
    const before = base([user]);
    expect(persistFingerprint({ ...before, blocks: [user, answer] })).not.toBe(
      persistFingerprint(before),
    );
  });

  it("changes when a persisted field changes", () => {
    const before = base();
    expect(persistFingerprint({ ...before, title: "Renamed" })).not.toBe(
      persistFingerprint(before),
    );
  });

  it("ignores state that is never written", () => {
    const before = base();
    expect(persistFingerprint({ ...before, busy: true })).toBe(
      persistFingerprint(before),
    );
  });

  it("treats a path-like provider session id as absent", () => {
    const session = base();
    expect(
      persistFingerprint({
        ...session,
        providerSessionId: "/Users/me/provider/sessions/abc.jsonl",
      }),
    ).toBe(persistFingerprint(session));
  });

  it("matches persist for a zero context window", () => {
    const session = base();
    expect(
      persistFingerprint({ ...session, context: { used: 10, window: 0 } }),
    ).toBe(persistFingerprint({ ...session, context: { used: 10 } }));
  });
});
