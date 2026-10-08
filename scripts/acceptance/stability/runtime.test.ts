import { act, createElement, useRef, useState } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useSessionRuntime, type SessionRuntime } from "../../../src/app/hooks/useSessionRuntime";
import { useSessionSubmission, type SessionSubmission } from "../../../src/app/hooks/useSessionSubmission";
import { newSession, type Session } from "../../../src/features/sessions/model/session";
import { registerHarness, resetHarnessIdlePark } from "../../../src/integrations/harness/core/registry";
import type { SendTurnInput } from "../../../src/integrations/harness/core/types";

const mocks = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke, isTauri: () => true }));
vi.mock("../../../src/integrations/harness/core/child", () => ({ startHarnessBridge: () => () => undefined }));
vi.mock("../../../src/features/sessions/model/promptPreparation", () => ({ preparePrompt: async (text: string) => text }));
vi.mock("../../../src/features/skills/model/skills", () => ({ isNativeCommandPrompt: () => false }));

type Pending = { input: SendTurnInput; finish: () => void };
let root: Root;
let host: HTMLDivElement;
let runtime: SessionRuntime;
let actions: SessionSubmission;
let pending: Pending[];

async function mount(initial: Session[]) {
  function Harness() {
    const [sessions, setSessions] = useState(initial);
    const sessionsRef = useRef(sessions);
    sessionsRef.current = sessions;
    runtime = useSessionRuntime({ sessions, sessionsRef, setSessions });
    actions = useSessionSubmission({ runtime });
    return null;
  }
  await act(async () => root.render(createElement(Harness)));
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  pending = [];
  mocks.invoke.mockReset().mockImplementation(async (command, args) => {
    if (command === "app_cli_path") return "/stability-fixture/loci";
    if (command === "session_upsert") return { ...args.session, createdAt: 1, updatedAt: 2 };
  });
  registerHarness({
    id: "codex", live: true,
    sendTurn: (input) => new Promise<void>((resolve) => {
      pending.push({ input, finish: resolve });
      input.onAccepted?.();
    }),
    steerTurn: async () => undefined, cancelTurn: async () => undefined,
    respondApproval: () => undefined, respondQuestion: () => undefined,
    stopSession: async () => undefined, forgetSession: async () => undefined,
    bindSession: () => undefined,
  });
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(async () => {
  await act(async () => { for (const run of pending) run.finish(); });
  await act(async () => root.unmount());
  host.remove();
  resetHarnessIdlePark();
  vi.unstubAllGlobals();
});

describe("repeated runtime transitions", () => {
  it("isolates late text, approval and terminal events over 100 cancel/resubmit cycles", async () => {
    const session = newSession("codex", "/stability-fixture", "codex:test");
    await mount([session]);
    for (let cycle = 0; cycle < 100; cycle += 1) {
      await act(async () => { expect(actions.onSubmit(session.id, `cancel-${cycle}`)).toBe(true); });
      const stale = pending[pending.length - 1];
      expect(stale).toBeDefined();
      await act(async () => actions.stop(session.id));
      // The registry serializes turns until the provider's send promise settles.
      // Late callbacks may still arrive after that settlement.
      await act(async () => stale.finish());
      await act(async () => { expect(actions.onSubmit(session.id, `keep-${cycle}`)).toBe(true); });
      const current = pending[pending.length - 1];
      expect(current).not.toBe(stale);
      await act(async () => {
        stale.input.onEvent({ type: "message.delta", text: "STALE-MARKER" });
        stale.input.onEvent({ type: "approval.requested", requestId: cycle, title: "stale approval", kind: "read" });
        stale.input.onEvent({ type: "session.ended", code: 1 });
        stale.finish();
        current.input.onEvent({ type: "message.delta", text: `CURRENT-${cycle}` });
        runtime.flushEvents();
      });
      const snapshot = runtime.sessionsRef.current[0];
      expect(snapshot.busy).toBe(true);
      expect(snapshot.blocks[snapshot.blocks.length - 1]?.text).toBe(`CURRENT-${cycle}`);
      expect(snapshot.blocks.some((block) => block.text.includes("STALE-MARKER") || block.approval)).toBe(false);
      await act(async () => {
        current.input.onEvent({ type: "message.completed" });
        current.input.onEvent({ type: "session.ended", code: 0 });
        current.finish();
      });
      expect(runtime.sessionsRef.current[0].busy).toBe(false);
      expect(runtime.hasActiveTurn(session.id)).toBe(false);
    }
    await runtime.flushPersistence();
  });

  it("keeps all 30,000 deltas ordered and isolated across three sessions", async () => {
    const sessions = Array.from({ length: 3 }, (_, i) => ({
      ...newSession("codex", "/stability-fixture", "codex:test"), id: `stream-${i}`,
      blocks: [{ id: `user-${i}`, role: "user" as const, text: "Start" }],
    }));
    await mount(sessions);
    await act(async () => {
      for (let i = 0; i < 10_000; i += 1) {
        for (const session of sessions) runtime.enqueueEvent(session.id, { type: "message.delta", text: `${session.id}:${i};` });
        if (i % 100 === 99) runtime.flushEvents();
      }
      runtime.flushEvents();
    });
    for (const session of sessions) {
      const actual = runtime.sessionsRef.current.find((s) => s.id === session.id)!;
      const expected = Array.from({ length: 10_000 }, (_, i) => `${session.id}:${i};`).join("");
      expect(actual.blocks[actual.blocks.length - 1]?.text).toBe(expected);
    }
    await runtime.flushPersistence();
  });
});
