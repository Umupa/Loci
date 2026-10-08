import { createElement } from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import { AgentTranscript } from "../../../src/features/sessions/ui/AgentTranscript";
import { PooledTranscript, TranscriptPool, TranscriptPoolOutlet } from "../../../src/features/sessions/ui/TranscriptPool";
import type { Block } from "../../../src/features/sessions/model/session";
import "../../../src/styles/index.css";

// Only synthetic data. No App bootstrap, provider calls, Tauri IPC or user DB.
const chats = Array.from({ length: 30 }, (_, chat) => ({
  id: `fixture-${chat}`,
  blocks: Array.from({ length: 200 }, (_, turn): Block[] => [
    { id: `${chat}-u-${turn}`, role: "user", text: `Question ${turn}: explain the lifecycle of session ${chat}.` },
    { id: `${chat}-a-${turn}`, role: "assistant", text:
      `## Response ${turn}\n\nThe session has **bounded resources** and a saved transcript.\n\n` +
      Array.from({ length: 6 }, (_, row) => `- Check ${row}: preserve ordering, cancellation and recovery.`).join("\n") },
  ]).flat(),
}));
const root = createRoot(document.getElementById("root")!);
let pool = new TranscriptPool();
let shown = 0;
let running = false;
const errors: string[] = [];
window.addEventListener("error", (event) => errors.push(event.message));
window.addEventListener("unhandledrejection", (event) => errors.push(String(event.reason)));

function render(index: number | null) {
  shown = index ?? shown;
  const chat = index == null ? null : chats[index];
  flushSync(() => root.render(createElement("main", {
    style: { height: "100vh", display: "flex", flexDirection: "column" },
  },
  createElement("header", { style: { padding: 12, flexShrink: 0 } },
    "Synthetic production renderer · 30 chats × 200 turns · ",
    createElement("button", { onClick: () => render((shown + 1) % chats.length) }, "Next chat")),
  chat ? createElement("section", {
    key: chat.id, style: { flex: 1, minHeight: 0, overflow: "hidden" },
  }, createElement(PooledTranscript, { pool, sessionId: chat.id,
    children: createElement(AgentTranscript, { blocks: chat.blocks, visible: true, busy: false }),
  })) : null,
  createElement(TranscriptPoolOutlet, { pool }))));
}

const nextPaint = () => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
const percentile = (values: number[], fraction: number) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * fraction) - 1] ?? 0;
function snapshot() {
  const entries = pool.getSnapshot();
  return {
    entries: entries.length,
    parked: entries.filter((entry) => !entry.host).length,
    retainedElements: entries.reduce((sum, entry) => sum + entry.container.querySelectorAll("*").length, 0),
    documentElements: document.querySelectorAll("*").length,
    visibleTurns: document.querySelectorAll("[data-transcript-turn]").length,
    errors: [...errors],
  };
}

async function runCycles(count = 500, workingSet = 30, scheduling: "frames" | "timers" = "frames") {
  if (running) throw new Error("A run is already active");
  if (!Number.isInteger(count) || count < 1 || count > 10_000 || !Number.isInteger(workingSet) || workingSet < 1 || workingSet > 30) throw new Error("Invalid workload");
  running = true;
  const commits: number[] = [];
  const paints: number[] = [];
  const checkpoints: Array<ReturnType<typeof snapshot> & { cycle: number }> = [];
  const start = performance.now();
  try {
    for (let cycle = 0; cycle < count; cycle += 1) {
      const began = performance.now();
      render(cycle % workingSet);
      commits.push(performance.now() - began);
      // Timer mode measures commits and retention when the browser host suspends
      // painting. It must not be reported as visible interaction/paint latency.
      if (scheduling === "frames") await nextPaint();
      else await new Promise<void>((resolve) => setTimeout(resolve, 0));
      paints.push(performance.now() - began);
      if ((cycle + 1) % 50 === 0) checkpoints.push({ cycle: cycle + 1, ...snapshot() });
    }
    const windowSize = Math.min(100, Math.floor(count / 2));
    return {
      count, workingSet, scheduling, elapsedMs: performance.now() - start,
      commitP95Ms: percentile(commits, 0.95),
      ...(scheduling === "frames" ? { paintOpportunityP95Ms: percentile(paints, 0.95) } : {}),
      firstWindowCommitP95Ms: percentile(commits.slice(0, windowSize), 0.95),
      lastWindowCommitP95Ms: percentile(commits.slice(-windowSize), 0.95), checkpoints,
    };
  } finally { running = false; }
}

const fixture = {
  snapshot, runCycles,
  show: async (index: number) => { render(index); await nextPaint(); return snapshot(); },
  close: async () => { render(null); await nextPaint(); return snapshot(); },
  reset: async () => { render(null); pool = new TranscriptPool(); render(0); await nextPaint(); return snapshot(); },
  unmount: async () => { flushSync(() => root.unmount()); pool = new TranscriptPool(); await nextPaint(); return snapshot(); },
};
Object.assign(window, { lociStability: fixture });
render(0);
