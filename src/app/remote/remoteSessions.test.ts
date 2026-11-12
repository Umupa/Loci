import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { appendUser, applyHarnessEvents, stopStreaming } from "../../integrations/harness/core/apply";
import { newSession, type Session } from "../../features/sessions/model/session";
import { createRemoteTransport, HOST_OFFLINE, NOT_CONNECTED, RESEND_GRACE_MS, type ConnectionStatus } from "../../platform/remoteTransport";

/** What the client bridge answers a read with offline when it kept nothing for it (`client.rs`). */
const NOT_KEPT = "This was not read from the host before it went offline";
import type { CallArgs, Transport, TransportEvent } from "../../platform/transport";
import { createSessionHost, type RemoteIntent } from "../hooks/useSessionHost";
import { createSessionFeed, outgoingSession, type SessionFeed } from "./sessionFeed";
import { sessionIntents } from "./sessionIntents";
import { RemoteSessionClient, type RemoteClientOptions } from "./remoteSessions";
import type { HostModels } from "./hostModels";
import type { HostSettingValues } from "../../platform/hostSettings";

const roster = vi.hoisted(() => ({ load: vi.fn(async () => undefined) }));
vi.mock("../../features/agents/model/mentorStore", () => ({ loadHostRoster: roster.load }));

/**
 * One host window and one connected window in this process. The host runs the
 * real intent table, session host and feed over sessions it changes the way
 * its submission hooks would; the bridge between them behaves like the
 * gateway and the client bridge (`remote_client_*`, `remote-client-*`).
 */
function world(archived: { seq: number; blocksJson: string; hasOlder: boolean }[] = [], target?: RemoteClientOptions["target"],
  { hostOffline = false, kept = new Map<string, unknown>(), pagesKept = new Map<string, unknown>() }:
  { hostOffline?: boolean; kept?: Map<string, unknown>; pagesKept?: Map<string, unknown> } = {}) {
  let offline = hostOffline;
  const onReconnected = vi.fn();
  let hostSessions: Session[] = [{ ...newSession("claude", "/w", "claude:sonnet"), id: "chat", title: "Chat", blocks: [{ id: "old", role: "assistant", text: "Earlier answer" }] }];
  const received: { name: string; args: unknown }[] = [];
  const bridgeCalls: string[] = [];
  const buffer: Exclude<SessionFeed, { kind: "snapshot" }>[] = [];
  // The host window's storage, for the settings it shares, and this window's copy of them.
  const hostSettings: HostSettingValues = { "loci.followUpBehavior": "queue", "loci.defaultModels": '{"claude":"claude:opus"}' };
  const clientSettings: HostSettingValues = {};
  const connects: unknown[] = [];
  const hostModels: HostModels = {
    available: { claude: true, codex: false } as HostModels["available"],
    catalogs: { claude: { models: [{ id: "claude:opus-9", harness: "claude", name: "Opus 9" }], defaultId: "claude:opus-9" } },
  };
  const readModels = vi.fn(async (_harnesses?: unknown) => hostModels);
  const applyModels = vi.fn();
  let connected = false;
  let subscribed = false;
  let lose = 0;
  // The host runs this intent, then the connection drops before its answer arrives.
  let dropAfter: string | undefined;
  const handlers = new Map<string, Set<(event: TransportEvent<unknown>) => void>>();
  const emit = (event: string, payload: unknown) => { for (const handler of handlers.get(event) ?? []) handler({ event, payload }); };
  const hostEvent = (name: string, payload: unknown) => {
    if (lose > 0) { lose -= 1; return; }
    if (connected && subscribed) emit("remote-client-event", { name, payload });
  };

  const updateSessions = (update: Session[] | ((current: Session[]) => Session[])) => {
    hostSessions = typeof update === "function" ? update(hostSessions) : update;
    feed.changed(hostSessions);
  };
  const change = (id: string, edit: (session: Session) => Session) =>
    updateSessions((current) => current.map((session) => session.id === id ? edit(session) : session));
  const submission = {
    onSubmit: vi.fn((id: string, text: string) => { change(id, (session) => appendUser(session, text)); return true; }),
    stop: vi.fn(async (id: string) => change(id, (session) => ({ ...stopStreaming(session), busy: false }))),
    answer: vi.fn((id: string) => change(id, (session) => ({ ...session, pendingQuestion: undefined }))),
    changeModel: vi.fn((id: string, harness: Session["harness"], model: string) => change(id, (session) => ({ ...session, harness, model }))),
    approve: vi.fn(),
  };
  const agentHeartbeat = {
    approve: vi.fn((id: string, requestId: number, decision: "allow" | "deny") => change(id, (session) => ({
      ...session, blocks: session.blocks.map((block) => block.approval?.requestId === requestId ? { ...block, approval: { requestId, decided: decision } } : block),
    }))),
  };
  const agents = { chat: vi.fn(async () => hostSessions[0]), create: vi.fn(), reset: vi.fn(), remove: vi.fn() };
  const store = { archiveSession: vi.fn(), removeSession: vi.fn() };
  const table = sessionIntents({ submission: submission as never, agents: agents as never, agentHeartbeat, store: store as never, updateSessions });
  const feed = createSessionFeed(hostSessions, (message) => {
    if (message.kind !== "snapshot") buffer.push(message);
    hostEvent("session.feed", message);
  }, { settings: () => ({ ...hostSettings }) });
  const hostWrites = (key: string, value: string | null) => {
    hostSettings[key] = value;
    feed.settingsChanged({ [key]: value });
  };
  const host = createSessionHost({
    intents: () => table, feed, onLeases: vi.fn(),
    setSetting: (key, value) => { hostWrites(key, value); return value; },
    models: readModels,
    inspectBinary: async (harness, binaryPath) => ({ path: binaryPath ?? `/host/bin/${harness}`, version: "1.0" }),
  });
  const epoch = feed.snapshot().epoch;

  // The client bridge, as the window's own Tauri backend.
  const bridge: Transport = {
    async call<T>(cmd: string, args?: CallArgs): Promise<T> {
      bridgeCalls.push(cmd);
      const input = (args ?? {}) as Record<string, unknown>;
      // What the bridge keeps on this device for the host (`remote_client_cache_*`).
      if (cmd === "remote_client_cache_put") { kept.set(input.key as string, structuredClone(input.value)); return undefined as T; }
      if (cmd === "remote_client_cache_get") return (kept.get(input.key as string) ?? null) as T;
      if (cmd === "remote_client_connect") {
        connects.push(input.target);
        if (offline) {
          emit("remote-client-status", { state: "disconnected", error: "The host did not answer" } satisfies ConnectionStatus);
          throw "The host did not answer";
        }
        connected = true;
        subscribed = false;
        emit("remote-client-status", { state: "connected" } satisfies ConnectionStatus);
        return { hostKey: "host" } as T;
      }
      // Offline, the bridge answers a read from what it kept, as `call_or_kept` does.
      if (!connected && cmd === "remote_client_call" && (input.cmd as string) === "agent_transcript_page") {
        const page = pagesKept.get(JSON.stringify(input.args));
        if (page === undefined) throw NOT_KEPT;
        return page as T;
      }
      if (!connected) throw NOT_CONNECTED;
      if (cmd === "remote_client_subscribe") {
        subscribed = true;
        // Every patch is kept here, so a known epoch is always replayed.
        if (input.epoch === epoch) for (const patch of buffer.filter((patch) => patch.seq > (input.seq as number))) hostEvent("session.feed", patch);
        else hostEvent("session.feed", feed.snapshot());
        return null as T;
      }
      if (cmd === "remote_client_call") {
        const name = input.cmd as string;
        received.push({ name, args: input.args });
        if (name === "agent_transcript_page") {
          const { before } = input.args as { before?: number | null };
          const page = [...archived].reverse().find((page) => before == null || page.seq < before) ?? null;
          pagesKept.set(JSON.stringify(input.args), page);
          return page as T;
        }
        if (!name.includes(".")) return { cmd: name } as T;
        const intent: RemoteIntent = { requestId: input.requestId as string, connectionId: "client", name, args: input.args as unknown[] };
        const result = await host.handle(intent) as T;
        if (dropAfter === name) {
          dropAfter = undefined;
          connected = false;
          emit("remote-client-status", { state: "disconnected", error: "The tunnel closed" });
          throw NOT_CONNECTED;
        }
        return result;
      }
      throw new Error(`Unexpected command ${cmd}`);
    },
    async listen(event, handler) {
      if (!/^[\w\-/:]+$/.test(event)) throw new Error(`invalid event name ${event}`);
      const set = handlers.get(event) ?? new Set();
      handlers.set(event, set);
      set.add(handler as (event: TransportEvent<unknown>) => void);
      return () => set.delete(handler as (event: TransportEvent<unknown>) => void);
    },
    fileUrl: async (path) => path,
  };

  const transport = createRemoteTransport(bridge);
  const callsThroughTransport: string[] = [];
  const watched: Transport = { ...transport, call: (cmd, args) => { callsThroughTransport.push(cmd); return transport.call(cmd, args); } };
  const client = new RemoteSessionClient(watched, {
    target, applySettings: (values) => Object.assign(clientSettings, values), applyModels, onReconnected,
  });
  return {
    client, submission, agentHeartbeat, received, bridgeCalls, callsThroughTransport,
    hostSettings, clientSettings, hostWrites, connects, readModels, applyModels, hostModels,
    host: () => hostSessions,
    change,
    loseNextEvent() { lose += 1; },
    dropAfter(name: string) { dropAfter = name; },
    kept, onReconnected,
    hostComesBack() { offline = false; },
    drop() { connected = false; emit("remote-client-status", { state: "disconnected", error: "The tunnel closed" }); },
    mirror: () => client.getSnapshot().sessions,
  };
}

async function settle(ms = 60) {
  await vi.advanceTimersByTimeAsync(ms);
}

describe("a connected window and its host", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("shows the host's sessions, and keeps them equal while a reply streams", async () => {
    const w = world();
    await w.client.start();
    await settle();
    expect(w.client.getSnapshot().status).toEqual({ state: "connected" });
    expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    expect(w.mirror()[0].blocks[0].text).toBe("Earlier answer");

    for (const text of ["Hel", "lo", ", there"]) {
      w.change("chat", (session) => applyHarnessEvents({ ...session, busy: true }, [{ type: "message.delta", text }]));
      await settle();
      expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    }
    expect(w.mirror()[0].blocks.at(-1)!.text).toBe("Hello, there");
    w.client.stop();
  });

  it("reads archived pages from the host and shows them before the mirrored turns", async () => {
    const w = world([
      { seq: 1, blocksJson: JSON.stringify([{ id: "u1", role: "user", text: "Oldest" }]), hasOlder: false },
      { seq: 2, blocksJson: JSON.stringify([{ id: "u2", role: "user", text: "Older" }]), hasOlder: true },
    ]);
    await w.client.start();
    await settle();
    w.client.view(["chat"]);
    await settle();
    const reads = () => w.received.filter((call) => call.name === "agent_transcript_page");
    expect(reads().map((call) => call.args)).toEqual([{ sessionId: "chat", before: null }]);
    expect(w.client.hasEarlier("chat")).toBe(true);
    // Reading ahead only says history exists; the live mirror stays as the host sent it.
    expect(w.client.sessionWithEarlier(w.mirror()[0]).blocks.map((block) => block.id)).toEqual(["old"]);

    await w.client.loadEarlier("chat");
    expect(w.client.sessionWithEarlier(w.mirror()[0]).blocks.map((block) => block.id)).toEqual(["u2", "old"]);
    await w.client.loadEarlier("chat");
    expect(reads().map((call) => call.args)).toEqual([
      { sessionId: "chat", before: null },
      { sessionId: "chat", before: 2 },
    ]);
    expect(w.client.sessionWithEarlier(w.mirror()[0]).blocks.map((block) => block.id)).toEqual(["u1", "u2", "old"]);
    expect(w.client.hasEarlier("chat")).toBe(false);

    await w.client.loadEarlier("chat");
    expect(reads()).toHaveLength(2);
    w.client.stop();
  });

  it("tells the host what it shows once per change", async () => {
    const w = world();
    await w.client.start();
    await settle();
    const views = () => w.received.filter((call) => call.name === "session.view").map((call) => call.args);
    const before = views().length;
    w.client.view(["chat"]);
    w.client.view(["chat"]);
    w.client.view(["chat", "work"]);
    await settle();
    expect(views().slice(before)).toEqual([[["chat"]], [["chat", "work"]]]);
    w.client.stop();
  });

  it("asks for archived turns once when the host has none", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.client.view(["chat"]);
    await settle();
    const reads = () => w.received.filter((call) => call.name === "agent_transcript_page");
    expect(reads().map((call) => call.args)).toEqual([{ sessionId: "chat", before: null }]);
    expect(w.client.hasEarlier("chat")).toBe(false);
    await w.client.loadEarlier("chat");
    expect(reads()).toHaveLength(1);
    expect(w.client.sessionWithEarlier(w.mirror()[0])).toBe(w.mirror()[0]);
    w.client.stop();
  });

  it("sends a message, stops, answers an approval and a question, and switches the model", async () => {
    const w = world();
    await w.client.start();
    await settle();
    const { intents } = w.client;

    await expect(intents["session.submit"]("chat", "What is a sandbox?", [], { followUpBehavior: "queue" })).resolves.toBe(true);
    expect(w.submission.onSubmit).toHaveBeenCalledWith("chat", "What is a sandbox?", [], { followUpBehavior: "queue" });
    await settle();
    expect(w.mirror()[0]).toMatchObject({ busy: true });
    expect(w.mirror()[0].blocks.at(-1)).toMatchObject({ role: "user", text: "What is a sandbox?" });

    await intents["session.stop"]("chat");
    await settle();
    expect(w.mirror()[0].busy).toBe(false);

    w.change("chat", (session) => ({ ...session, blocks: [...session.blocks, { id: "ask", role: "tool", text: "rm -rf build", approval: { requestId: 4 } }],
      pendingQuestion: { requestId: 9, questions: [{ id: "q", prompt: "Which?", options: [] }] } as never }));
    await settle();
    await intents["session.approve"]("chat", 4, "allow");
    expect(w.agentHeartbeat.approve).toHaveBeenCalledWith("chat", 4, "allow");
    await intents["session.answer"]("chat", 9, { answers: { q: "this" } } as never);
    expect(w.submission.answer).toHaveBeenCalledWith("chat", 9, { answers: { q: "this" } });
    await intents["session.changeModel"]("chat", "codex", "codex:test");
    await settle();
    expect(w.mirror()[0]).toMatchObject({ harness: "codex", model: "codex:test" });
    expect(w.mirror()[0]).not.toHaveProperty("pendingQuestion");
    expect(w.mirror()[0].blocks.find((block) => block.id === "ask")!.approval).toEqual({ requestId: 4, decided: "allow" });
    expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    w.client.stop();
  });

  it("catches up after the connection drops, and refuses a message made while the host is offline", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.drop();
    w.change("chat", (session) => ({ ...session, title: "Renamed while away" }));
    await settle();
    w.change("chat", (session) => applyHarnessEvents(session, [{ type: "message.delta", text: "missed" }]));
    await settle();
    expect(w.mirror()[0].title).toBe("Chat");

    // Nothing is queued for later: the window is read-only until the host is back.
    await expect(w.client.intents["session.submit"]("chat", "Sent while away")).rejects.toThrow(HOST_OFFLINE);
    expect(w.client.getSnapshot().error).toContain("read-only");
    await settle(1_100);
    expect(w.client.getSnapshot().status.state).toBe("connected");
    expect(w.submission.onSubmit).not.toHaveBeenCalled();
    expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    expect(w.mirror()[0].title).toBe("Renamed while away");
    w.client.stop();
  });

  it("sends a message again whose answer was lost with the connection, and the host runs it once", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.dropAfter("session.submit");
    const sending = w.client.intents["session.submit"]("chat", "Lost answer");
    await settle(1_100);
    await expect(sending).resolves.toBe(true);
    expect(w.submission.onSubmit).toHaveBeenCalledOnce();
    expect(w.received.filter((call) => call.name === "session.submit")).toHaveLength(2);
    w.client.stop();
  });

  it("gives up on a message on its way when the host stays away", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.dropAfter("session.stop");
    // The host never comes back within the grace period.
    w.client.stop();
    const stopping = w.client.intents["session.stop"]("chat");
    const failed = expect(stopping).rejects.toThrow(HOST_OFFLINE);
    await settle(RESEND_GRACE_MS + 10);
    await failed;
  });

  it("asks again for a patch it missed while connected", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.loseNextEvent();
    w.change("chat", (session) => ({ ...session, title: "Lost on the way" }));
    await settle();
    expect(w.mirror()[0].title).toBe("Chat");
    w.change("chat", (session) => ({ ...session, busy: true }));
    await settle();
    expect(w.bridgeCalls.filter((cmd) => cmd === "remote_client_subscribe")).toHaveLength(2);
    expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    w.client.stop();
  });

  it("never asks for an agent CLI", async () => {
    const w = world();
    await w.client.start();
    await settle();
    await w.client.intents["session.submit"]("chat", "hi");
    await w.client.openAgent("agent");
    w.client.view(["chat"]);
    await settle();
    const bridge = { call: vi.fn(), listen: vi.fn(async () => () => undefined), fileUrl: vi.fn() };
    await expect(createRemoteTransport(bridge).call("harness_spawn", {})).rejects.toThrow("not available");
    expect(bridge.call).not.toHaveBeenCalled();
    expect([...w.bridgeCalls, ...w.callsThroughTransport, ...w.received.map((call) => call.name)].filter((cmd) => cmd.startsWith("harness_"))).toEqual([]);
    w.client.stop();
  });

  it("keeps the host's shared settings here, through a dropped connection too", async () => {
    const w = world();
    await w.client.start();
    await settle();
    expect(w.clientSettings).toEqual(w.hostSettings);
    w.hostWrites("loci.followUpBehavior", "steer");
    await settle();
    expect(w.clientSettings["loci.followUpBehavior"]).toBe("steer");

    w.drop();
    w.hostWrites("loci.learningLanguage", "zh-CN");
    await settle(1_100);
    expect(w.client.getSnapshot().status.state).toBe("connected");
    expect(w.clientSettings).toEqual(w.hostSettings);
    w.client.stop();
  });

  it("hands a setting saved here to the host, which keeps it, and refuses one that is not shared", async () => {
    const w = world();
    await w.client.start();
    await settle();
    await w.client.setSetting("loci.followUpBehavior", "steer");
    expect(w.hostSettings["loci.followUpBehavior"]).toBe("steer");
    expect(w.clientSettings["loci.followUpBehavior"]).toBe("steer");

    // Saved here first, as a save function does; the host refuses, so the host's value comes back.
    w.clientSettings["loci:agent-handed"] = "{}";
    await w.client.setSetting("loci:agent-handed", "{}");
    expect(w.hostSettings).not.toHaveProperty("loci:agent-handed");
    expect(w.clientSettings["loci:agent-handed"]).toBeNull();
    expect(w.client.getSnapshot().error).toContain("not a setting connected devices can change");
    await settle();
    expect(w.clientSettings["loci.followUpBehavior"]).toBe("steer");
    w.client.stop();
  });

  it("shows the host's providers and models, and asks the host to read them again", async () => {
    const w = world();
    await w.client.start();
    await settle();
    expect(w.applyModels).toHaveBeenCalledWith(w.hostModels);
    await w.client.refreshModels(["codex"]);
    expect(w.readModels).toHaveBeenLastCalledWith(["codex"]);
    w.client.stop();
  });

  it("brings the reader's place to the host with a message", async () => {
    const w = world();
    await w.client.start();
    await settle();
    const reading = { reading: { kind: "document" as const, id: "doc-1", title: "Pods" }, place: { section: ["Lifecycle"] } };
    await w.client.intents["session.submit"]("chat", "What is this?", [], { reading });
    expect(w.submission.onSubmit).toHaveBeenCalledWith("chat", "What is this?", [], { reading });
    w.client.stop();
  });

  it("connects to the device the window was opened for", async () => {
    const w = world([], { kind: "device", deviceId: "mac-mini-id" });
    await w.client.start();
    await settle();
    expect(w.connects).toEqual([{ kind: "device", deviceId: "mac-mini-id" }]);
    expect(w.client.getSnapshot().status.state).toBe("connected");
    w.client.stop();
  });

  it("keeps a copy of the host's sessions on this device as they change", async () => {
    const w = world();
    await w.client.start();
    await settle();
    w.change("chat", (session) => ({ ...session, title: "Kept" }));
    await settle(2_100);
    expect(w.kept.get("sessions")).toEqual(w.mirror());
    expect((w.kept.get("sessions") as Session[])[0].title).toBe("Kept");
    w.client.stop();
  });

  it("shows what this device kept while the host is offline, and the host's sessions once it is back", async () => {
    const kept = new Map<string, unknown>([["sessions", [{ ...newSession("claude", "/w"), id: "chat", title: "Kept copy", blocks: [] }]]]);
    const w = world([], undefined, { hostOffline: true, kept });
    roster.load.mockClear();
    await w.client.start();
    await settle();
    expect(w.client.getSnapshot().status.state).toBe("disconnected");
    expect(w.mirror()[0].title).toBe("Kept copy");
    // The roster is read too; offline, the bridge answers it from what it kept.
    expect(roster.load).toHaveBeenCalled();
    await expect(w.client.intents["session.stop"]("chat")).rejects.toThrow(HOST_OFFLINE);

    w.hostComesBack();
    await settle(1_100);
    expect(w.client.getSnapshot().status.state).toBe("connected");
    expect(w.onReconnected).toHaveBeenCalledOnce();
    expect(w.mirror()).toEqual(w.host().map(outgoingSession));
    w.client.stop();
  });

  it("reads archived turns while the host is offline from what was kept, and says so when nothing was", async () => {
    const pages = [
      { seq: 1, blocksJson: JSON.stringify([{ id: "u1", role: "user", text: "Oldest" }]), hasOlder: false },
      { seq: 2, blocksJson: JSON.stringify([{ id: "u2", role: "user", text: "Older" }]), hasOlder: true },
    ];
    const offlineAfterLooking = async (pagesKept?: Map<string, unknown>) => {
      const w = world(pages, undefined, { pagesKept });
      await w.client.start();
      await settle();
      w.client.view(["chat"]);
      await settle();
      w.drop();
      w.client.stop();
      // The newest page was read ahead while connected.
      await w.client.loadEarlier("chat");
      expect(w.client.sessionWithEarlier(w.mirror()[0]).blocks.map((block) => block.id)).toEqual(["u2", "old"]);
      await w.client.loadEarlier("chat");
      return w;
    };

    // The older page was read on an earlier visit, so this device kept it.
    const kept = await offlineAfterLooking(new Map([[JSON.stringify({ sessionId: "chat", before: 2 }), pages[0]]]));
    expect(kept.client.sessionWithEarlier(kept.mirror()[0]).blocks.map((block) => block.id)).toEqual(["u1", "u2", "old"]);
    expect(kept.client.getSnapshot().error).toBeNull();

    const never = await offlineAfterLooking();
    expect(never.client.getSnapshot().error).toBe(NOT_KEPT);
    expect(never.client.hasEarlier("chat")).toBe(true);
  });

  it("asks the host where a provider's CLI is, for the settings page", async () => {
    const w = world();
    await w.client.start();
    await settle();
    await expect(w.client.inspectBinary("codex")).resolves.toEqual({ path: "/host/bin/codex", version: "1.0" });
    expect(w.bridgeCalls.filter((cmd) => cmd.startsWith("harness_"))).toEqual([]);
    w.client.stop();
  });
});
