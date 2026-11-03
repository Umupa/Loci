import { useSyncExternalStore } from "react";
import type { Session } from "../../features/sessions/model/session";
import { loadHostRoster } from "../../features/agents/model/mentorStore";
import { loadTranscriptPage } from "../../features/agents/model/agentTranscript";
import {
  earlierBlocks, hasEarlierPages, readEarlierPage, type EarlierPages,
} from "../../features/agents/model/transcriptPages";
import type { HostSettingValues } from "../../platform/hostSettings";
import type { ConnectionStatus } from "../../platform/remoteTransport";
import type { Transport, Unlisten } from "../../platform/transport";
import type { HarnessId } from "../../features/sessions/model/session";
import type { HostModels } from "./hostModels";
import type { HarnessBinaryInspection } from "../../integrations/harness/core/child";
import { applySessionChanges, type SessionFeed } from "./sessionFeed";
import type { SessionIntents } from "./sessionIntents";

/** The host's intent table as a connected device calls it: each entry sends the intent. */
export type RemoteIntents = { [K in keyof SessionIntents]: (...args: Parameters<SessionIntents[K]>) => Promise<unknown> };

export type RemoteSessionsState = {
  status: ConnectionStatus;
  /** The host's sessions in memory, as its feed last described them. */
  sessions: Session[];
  /** Archived turns this window has read back, per session. */
  earlier: ReadonlyMap<string, EarlierPages>;
  /** The last intent the host refused or failed, for the window to show. */
  error: string | null;
};

export type RemoteClientOptions = {
  /** What `remote_client_connect` reaches: `{ kind: "loopback" }` or `{ kind: "device", deviceId }`. */
  target?: Record<string, unknown>;
  /** Puts the host's shared settings in this window (`applyHostSettings`). */
  applySettings?: (values: HostSettingValues) => void;
  /** Makes the host's providers and models this window's (`applyHostModels`). */
  applyModels?: (models: HostModels) => void;
  /** Back after the host was offline: what was read from what this device kept is read again. */
  onReconnected?: () => void;
};

/** How long the mirror settles before this device keeps a copy for when the host is offline. */
const KEEP_MS = 2_000;

const LEASE_MS = 30_000;
const RETRY_MS = 1_000;
const RETRY_MAX_MS = 30_000;

/**
 * A window's view of another device's sessions. It mirrors the host's session
 * feed and sends intents in place of running anything itself: no agent CLI is
 * started and nothing is saved here. Keeps the connection up, reconnecting
 * with backoff, and catches up from where it was by `{ epoch, seq }`.
 */
export class RemoteSessionClient {
  private state: RemoteSessionsState = { status: { state: "connecting" }, sessions: [], earlier: new Map(), error: null };
  private readonly listeners = new Set<() => void>();
  private stops: Unlisten[] = [];
  private epoch: string | undefined;
  private seq = 0;
  private resyncing = false;
  private attempt = 0;
  private retry: ReturnType<typeof setTimeout> | undefined;
  private lease: ReturnType<typeof setInterval> | undefined;
  private viewed: string[] = [];
  private readonly pages = new Map<string, Promise<EarlierPages>>();
  private stopped = false;
  /** The host's shared settings as its feed last said them. */
  private hostSettings: HostSettingValues = {};
  private wasOffline = false;
  private keep: ReturnType<typeof setTimeout> | undefined;
  private readonly target: Record<string, unknown>;

  constructor(private readonly transport: Transport, private readonly options: RemoteClientOptions = {}) {
    this.target = options.target ?? { kind: "loopback" };
  }

  readonly intents = new Proxy({}, {
    get: (_, name: string) => (...args: unknown[]) => this.send(name, args),
  }) as RemoteIntents;

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };

  getSnapshot = () => this.state;

  async start(): Promise<void> {
    this.stopped = false;
    this.stops = await Promise.all([
      this.transport.listen<ConnectionStatus>("remote-client-status", ({ payload }) => this.onStatus(payload)),
      this.transport.listen<SessionFeed>("session.feed", ({ payload }) => this.onFeed(payload)),
    ]);
    this.lease = setInterval(() => this.sendView(), LEASE_MS);
    await this.connect();
    if (!this.epoch) await this.restoreKept();
  }

  /** What this device kept from the host, shown until (or unless) the host answers. */
  private async restoreKept() {
    const kept = await this.transport.call<Session[] | null>("remote_client_cache_get", { key: "sessions" }).catch(() => null);
    if (!this.epoch && Array.isArray(kept)) this.set({ sessions: kept });
    void loadHostRoster().catch(() => undefined);
  }

  stop(): void {
    this.stopped = true;
    for (const stop of this.stops) stop();
    this.stops = [];
    clearTimeout(this.retry);
    clearInterval(this.lease);
    clearTimeout(this.keep);
  }

  /** Connects now, as the window's reconnect button does. */
  async connect(): Promise<void> {
    clearTimeout(this.retry);
    this.retry = undefined;
    this.set({ status: { state: "connecting" } });
    try {
      await this.transport.call("remote_client_connect", { target: this.target });
    } catch (error) {
      // The bridge also reports the failure as a status; either one schedules the retry.
      this.onStatus({ state: "disconnected", error: String(error) });
    }
  }

  /** Sessions this window shows, which the host keeps in memory for it. */
  view(sessionIds: string[]): void {
    this.viewed = sessionIds;
    this.sendView();
    for (const sessionId of sessionIds) void this.prefetchEarlier(sessionId);
  }

  /** The host's session as this window shows it: archived turns read back, then the live ones. */
  sessionWithEarlier(session: Session): Session {
    const blocks = earlierBlocks(this.state.earlier.get(session.id), session.blocks);
    return blocks?.length ? { ...session, blocks: [...blocks, ...session.blocks] } : session;
  }

  /** Whether the host has older turns for a session this window shows. */
  hasEarlier(sessionId: string): boolean {
    return hasEarlierPages(this.state.earlier.get(sessionId));
  }

  /** Reads the next archived page into view; it is on the host's disk, not in its feed. */
  async loadEarlier(sessionId: string): Promise<void> {
    if (!this.hasEarlier(sessionId)) return;
    try {
      await this.readEarlier(sessionId, true);
    } catch (error) {
      this.set({ error: String(error) });
    }
  }

  /**
   * Hands the host a shared setting this window just saved. The host's answer
   * is the value it keeps; a refusal puts back the host's value.
   */
  async setSetting(key: string, value: string | null): Promise<void> {
    try {
      const kept = await this.send("settings.set", [key, value]) as string | null;
      this.applySettings({ [key]: kept });
    } catch {
      this.options.applySettings?.({ [key]: this.hostSettings[key] ?? null });
    }
  }

  /** Reads the host's providers and models again, for these providers. */
  async refreshModels(harnesses?: HarnessId[]): Promise<void> {
    if (this.state.status.state !== "connected") return;
    const models = await this.transport.call<HostModels>("session.models", harnesses ? [harnesses] : []).catch(() => undefined);
    if (models) this.options.applyModels?.(models);
  }

  /** Where a provider's CLI is on the host, and its version: only the host may run it. */
  inspectBinary(harness: HarnessId, binaryPath?: string | null): Promise<HarnessBinaryInspection> {
    return this.transport.call<HarnessBinaryInspection>("providers.inspectBinary", [harness, binaryPath ?? null]);
  }

  /** Opens an agent's conversation on the host; its id, once the host has it in memory. */
  async openAgent(agentId: string): Promise<string | null> {
    return await this.intents["agent.open"](agentId) as string | null;
  }

  clearError(): void {
    this.set({ error: null });
  }

  private applySettings(values: HostSettingValues) {
    this.hostSettings = { ...this.hostSettings, ...values };
    this.options.applySettings?.(values);
  }

  private set(change: Partial<RemoteSessionsState>) {
    this.state = { ...this.state, ...change };
    for (const listener of this.listeners) listener();
    if (change.sessions && this.epoch && !this.keep) {
      this.keep = setTimeout(() => {
        this.keep = undefined;
        void this.transport.call("remote_client_cache_put", { key: "sessions", value: this.state.sessions }).catch(() => undefined);
      }, KEEP_MS);
    }
  }

  private async send(name: string, args: unknown[]): Promise<unknown> {
    // An object URL is this window's own and means nothing to the host.
    const sent = JSON.parse(JSON.stringify(args, (key, value: unknown) => key === "previewUrl" ? undefined : value)) as unknown[];
    try {
      const result = await this.transport.call(name, sent);
      if (name === "session.submit" && result === false) this.set({ error: "The host did not take the message." });
      if (name.startsWith("agent.")) void loadHostRoster().catch(() => undefined);
      return result;
    } catch (error) {
      this.set({ error: String(error) });
      throw error;
    }
  }

  private sendView() {
    if (this.state.status.state !== "connected") return;
    void this.transport.call("session.view", [this.viewed]).catch(() => undefined);
  }

  /** Reads the newest page for a session shown here, once, so its pane knows history exists. */
  private async prefetchEarlier(sessionId: string): Promise<void> {
    if (this.state.status.state !== "connected") return;
    if (this.state.earlier.has(sessionId) || this.pages.has(sessionId)) return;
    await this.readEarlier(sessionId, false).catch(() => undefined);
  }

  private readEarlier(sessionId: string, append: boolean): Promise<EarlierPages> {
    const pending = this.pages.get(sessionId);
    if (pending) return pending;
    const request = readEarlierPage(sessionId, this.state.earlier.get(sessionId), append,
      (id, before) => loadTranscriptPage(id, before, this.transport)).then((next) => {
      this.set({ earlier: new Map(this.state.earlier).set(sessionId, next) });
      return next;
    }).finally(() => {
      if (this.pages.get(sessionId) === request) this.pages.delete(sessionId);
    });
    this.pages.set(sessionId, request);
    return request;
  }

  private onStatus(status: ConnectionStatus) {
    if (this.stopped) return;
    this.set({ status });
    if (status.state === "connected") {
      this.attempt = 0;
      if (this.wasOffline) this.options.onReconnected?.();
      this.wasOffline = false;
      void this.resubscribe();
      void loadHostRoster().catch(() => undefined);
      this.sendView();
      for (const sessionId of this.viewed) void this.prefetchEarlier(sessionId);
      void this.refreshModels();
    } else if (status.state === "disconnected") {
      this.wasOffline = true;
      if (this.retry) return;
      const delay = Math.min(RETRY_MS * 2 ** this.attempt, RETRY_MAX_MS);
      this.attempt += 1;
      this.retry = setTimeout(() => { this.retry = undefined; void this.connect(); }, delay);
    }
  }

  /** Asks the host for what this window missed: patches after `seq`, or a snapshot. */
  private async resubscribe(fresh = false) {
    this.resyncing = true;
    const from = this.epoch && !fresh ? { epoch: this.epoch, seq: this.seq } : {};
    try {
      await this.transport.call("remote_client_subscribe", from);
    } catch {
      // A dropped connection resubscribes when it is back.
    } finally {
      this.resyncing = false;
    }
  }

  private onFeed(feed: SessionFeed) {
    if (feed.kind === "snapshot") {
      this.epoch = feed.epoch;
      this.seq = feed.seq;
      this.set({ sessions: feed.sessions });
      if (feed.settings) this.applySettings(feed.settings);
      void loadHostRoster().catch(() => undefined);
      return;
    }
    // The host window reloaded: what this window has belongs to an older page.
    if (feed.epoch !== this.epoch) {
      if (!this.resyncing) void this.resubscribe(true);
      return;
    }
    if (feed.seq <= this.seq) return;
    if (feed.seq !== this.seq + 1) {
      if (!this.resyncing) void this.resubscribe();
      return;
    }
    this.seq = feed.seq;
    if (feed.kind === "settings") {
      this.applySettings(feed.values);
      return;
    }
    const known = new Set(this.state.sessions.map((session) => session.id));
    this.set({ sessions: applySessionChanges(this.state.sessions, feed.changes) });
    // A conversation that came or went may belong to a mentor that came or went.
    if (feed.changes.some((change) => "removed" in change || !known.has(change.id))) void loadHostRoster().catch(() => undefined);
  }
}

export function useRemoteSessions(client: RemoteSessionClient): RemoteSessionsState {
  return useSyncExternalStore(client.subscribe, client.getSnapshot);
}
