import { useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { mockIPC } from "@tauri-apps/api/mocks";
import { useSessionRuntime, type SessionRuntime } from "../../../src/app/hooks/useSessionRuntime";
import { useSessionSubmission } from "../../../src/app/hooks/useSessionSubmission";
import { useIdleSessionDetach } from "../../../src/app/hooks/useIdleSessionDetach";
import { newTab } from "../../../src/features/workspace/model/layout";
import { newSession, type Session } from "../../../src/features/sessions/model/session";
import { btwThreadBlocks } from "../../../src/features/sessions/model/btw";
import { AgentTranscript } from "../../../src/features/sessions/ui/AgentTranscript";
import { registerHarness, type TextPromptInput } from "../../../src/integrations/harness/core/registry";
import { loadMcpSettings } from "../../../src/features/settings/model/mcpSettingsCache";
import "../../../src/styles/index.css";

// Production controllers and transcript renderer; only IPC/provider are fake.
// Every record belongs to this page, never to the user's database or agent CLI.
const records = new Map<string, unknown>();
const errors: string[] = [];
let writes = 0;
let mcpDiscoveries = 0;
let runtime: SessionRuntime;
let cachedSessions = new Map<string, Session>();
let pending: { input: TextPromptInput; resolve: (text: string) => void } | undefined;
let answer = "";
let chunks = 0;
mockIPC((command, payload) => {
  if (command === "mcp_discover") {
    if (++mcpDiscoveries === 1) throw new Error("Temporary discovery failure");
    return [{ provider: "codex", name: "fixture-docs", scope: "project", configPath: "synthetic.json", transport: "stdio" }];
  }
  if (command === "session_upsert") {
    const { session } = payload as { session: { id: string } & Record<string, unknown> };
    const row = structuredClone({ ...session, createdAt: 1, updatedAt: 2 });
    records.set(row.id, row);
    writes += 1;
    return row;
  }
  throw new Error(`Unexpected fixture IPC: ${command}`);
}, { shouldMockEvents: true });
window.addEventListener("error", (event) => errors.push(event.message));
window.addEventListener("unhandledrejection", (event) => errors.push(String(event.reason)));
registerHarness({
  id: "codex", live: true,
  sendTurn: async () => undefined, steerTurn: async () => undefined,
  cancelTurn: async () => undefined, respondApproval: () => undefined,
  stopSession: async () => undefined, forgetSession: async () => undefined,
  bindSession: () => undefined,
  runTextPrompt: (input) => new Promise((resolve) => { answer = ""; chunks = 0; pending = { input, resolve }; }),
});
const initial: Session = {
  ...newSession("codex", "/synthetic-state-fixture", "codex:test"),
  blocks: [
    { id: "main-question", role: "user", text: "Main question" },
    { id: "main-answer", role: "assistant", text: "Main answer" },
  ],
};

function Fixture() {
  const [sessions, setSessions] = useState([initial]);
  const [parentRenders, setParentRenders] = useState(0);
  const [chatOpen, setChatOpen] = useState(true);
  const [mcpStatus, setMcpStatus] = useState("MCP not queried");
  const tabs = useMemo(() => chatOpen ? [newTab(initial.id)] : [], [chatOpen]);
  const tabsRef = useRef(tabs);
  tabsRef.current = tabs;
  const cache = useRef(new Map<string, Session>());
  cachedSessions = cache.current;
  const opening = useRef(new Set<string>());
  const protectedIds = useRef(new Set<string>());
  const sessionsRef = useRef(sessions);
  runtime = useSessionRuntime({ sessions, sessionsRef, setSessions, onPersistenceError: (error) => errors.push(String(error)) });
  const actions = useSessionSubmission({ runtime });
  useIdleSessionDetach({
    sessions, sessionsRef, tabs, tabsRef, liveAgentsEnabled: false,
    unseenFinishedIds: new Set(), openingSessionIds: opening,
    loadedSessionCache: cache, skipForgetSessionIds: protectedIds,
    persistSession: runtime.persistSession, setSessions: runtime.updateSessions,
    onError: (error) => errors.push(String(error)),
  });
  const session = sessions[0] ?? cache.current.get(initial.id) ?? initial;
  const thread = session.blocks[0].btwThreads?.[0];
  const blocks = thread ? btwThreadBlocks({ ...thread, running: thread.status === "running" }) : [];
  return <main style={{ height: "100vh", display: "flex", flexDirection: "column" }}>
    <header style={{ padding: 16, display: "flex", gap: 12, flexWrap: "wrap" }}>
      <strong>Synthetic side-question fixture</strong>
      <button onClick={() => actions.btwSubmit(session.id, session.blocks, "side", `question-${Date.now()}`, "Explain further")} disabled={!chatOpen || thread?.status === "running"}>Ask side question</button>
      <button disabled={!chatOpen} onClick={() => setChatOpen(false)}>Close chat</button>
      <button disabled={chatOpen} onClick={() => {
        const cached = cache.current.get(initial.id);
        if (cached && !runtime.sessionsRef.current.length) {
          runtime.bindRestoredSession(cached);
          runtime.updateSessions([cached]);
        }
        setChatOpen(true);
      }}>Reopen chat</button>
      <button disabled={thread?.status !== "running"} onClick={() => {
        const text = `Chunk ${++chunks}. `;
        answer += text;
        pending?.input.onEvent?.({ type: "message.delta", text });
      }}>Stream chunk</button>
      <button disabled={thread?.status !== "running"} onClick={() => {
        pending?.input.onEvent?.({ type: "message.completed" });
        pending?.resolve(answer || "Completed.");
        pending = undefined;
      }}>Complete side answer</button>
      <button disabled={!chatOpen || !thread} onClick={() => actions.btwModelChange(session.id, session.blocks, "side", "new-model", {})}>Change model</button>
      <button disabled={!chatOpen || !thread} onClick={() => actions.btwDelete(session.id, session.blocks, "side")}>Delete side question</button>
      <button onClick={() => setParentRenders((count) => count + 1)}>Parent render</button>
      <button onClick={() => { void loadMcpSettings("/synthetic-mcp-fixture", false, { claudeHealth: false })
        .then((snapshot) => setMcpStatus(snapshot.error || snapshot.servers.map((server) => server.name).join(", "))); }}>Check MCP</button>
    </header>
    <output style={{ padding: 16 }} aria-label="State">
      {chatOpen ? "Open" : "Closed"} · {thread ? `${thread.status} · ${thread.model}` : "No side question"} · Parent renders: {parentRenders}
    </output>
    <output aria-label="MCP state" style={{ padding: 16 }}>{mcpStatus}</output>
    <section style={{ flex: 1, minHeight: 0 }}>
      {chatOpen && thread && <AgentTranscript blocks={blocks} busy={thread.status === "running"} visible />}
    </section>
  </main>;
}

Object.assign(window, { lociStateFixture: {
  snapshot: () => ({ session: runtime.sessions[0] ?? cachedSessions.get(initial.id), attached: runtime.sessions.length,
    cached: cachedSessions.size, persisted: records.get(initial.id), writes, mcpDiscoveries, errors: [...errors] }),
  flush: () => runtime.flushPersistence(),
} });
createRoot(document.getElementById("root")!).render(<Fixture />);
