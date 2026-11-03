import { useCallback, useEffect, useRef, useState, type MutableRefObject } from "react";
import { getCurrentWindow } from "../../platform/native";
import { transport } from "../../platform/transport";
import { HARNESSES, type HarnessId, type Session } from "../../features/sessions/model/session";
import { inspectHarnessBinary } from "../../integrations/harness/core/child";
import {
  applyHostSettings, HOST_SETTING_MAX_CHARS, hostSettingsSnapshot, isHostSharedKey, setHostSettingSink,
} from "../../platform/hostSettings";
import { readHostModels } from "../remote/hostModels";
import { createSessionFeed, type SessionFeedPublisher } from "../remote/sessionFeed";
import { CONFIRMED_INTENTS, type SessionIntents } from "../remote/sessionIntents";

/** What the gateway hands the host window for a connected device. */
export type RemoteIntent = { requestId: string; connectionId: string; name: string; args: unknown[] };

type HostOptions = {
  intents: () => SessionIntents;
  feed: Pick<SessionFeedPublisher, "snapshot">;
  /** Sessions a connected device is looking at; called with every change. */
  onLeases: (sessionIds: string[]) => void;
  /** Stores a host-shared setting a device changed; the value the host keeps. */
  setSetting?: (key: string, value: string | null) => string | null;
  /** The host's providers and models, its catalogs read again for these providers. */
  models?: (harnesses?: HarnessId[]) => Promise<unknown>;
  /** Where a provider's CLI is on the host, and its version. */
  inspectBinary?: (harness: HarnessId, binaryPath: string | null) => Promise<unknown>;
};

/**
 * Runs connected devices' intents in this window. A retry with the same
 * request id gets the first run's answer instead of running again, so a
 * message resent after a dropped connection is sent once.
 */
export function createSessionHost({ intents, feed, onLeases, setSetting, models, inspectBinary }: HostOptions) {
  const receipts = new Map<string, { signature: string; promise: Promise<unknown> }>();
  const leases = new Map<string, string[]>();

  const run = async ({ connectionId, name, args }: RemoteIntent): Promise<unknown> => {
    // A device says what it shows every so often; the gateway sends an empty
    // list for it when its connection ends.
    if (name === "session.view") {
      const ids = args[0] as string[];
      if (ids.length) leases.set(connectionId, ids); else leases.delete(connectionId);
      onLeases([...new Set([...leases.values()].flat())]);
      return null;
    }
    if (name === "session.snapshot") return feed.snapshot();
    if (name === "settings.set" && setSetting) {
      const [key, value] = args as [unknown, unknown];
      if (typeof key !== "string" || !isHostSharedKey(key)) throw new Error(`${String(key)} is not a setting connected devices can change`);
      if (value !== null && (typeof value !== "string" || value.length > HOST_SETTING_MAX_CHARS)) throw new Error(`Invalid value for ${key}`);
      return setSetting(key, value);
    }
    if (name === "session.models" && models) return models(args[0] as HarnessId[] | undefined);
    if (name === "providers.inspectBinary" && inspectBinary) {
      const [harness, binaryPath] = args as [HarnessId, string | null];
      if (!HARNESSES.includes(harness)) throw new Error(`Unknown provider: ${String(harness)}`);
      return inspectBinary(harness, typeof binaryPath === "string" ? binaryPath : null);
    }
    const table = intents();
    if (!Object.prototype.hasOwnProperty.call(table, name)) throw new Error(`Unknown intent: ${name}`);
    if (CONFIRMED_INTENTS.has(name) && (args[args.length - 1] as { confirmed?: unknown } | undefined)?.confirmed !== true) {
      throw new Error(`${name} must be confirmed on the device that sent it`);
    }
    const result = await (table[name as keyof SessionIntents] as (...input: unknown[]) => unknown)(...args);
    // The device shows the conversation it opened only once it has the id; until
    // it says so, it holds it here, or an empty new chat is released first.
    if (name === "agent.open" && typeof result === "string") {
      leases.set(connectionId, [...new Set([...(leases.get(connectionId) ?? []), result])]);
      onLeases([...new Set([...leases.values()].flat())]);
    }
    return result;
  };

  return {
    handle(intent: RemoteIntent): Promise<unknown> {
      const signature = JSON.stringify([intent.name, intent.args]);
      const previous = receipts.get(intent.requestId);
      if (previous) {
        return previous.signature === signature ? previous.promise
          : Promise.reject(new Error("Request ID was already used with different input"));
      }
      const promise = run(intent);
      receipts.set(intent.requestId, { signature, promise });
      // A failed intent changed nothing, so a retry may run it again.
      void promise.catch(() => { if (receipts.get(intent.requestId)?.promise === promise) receipts.delete(intent.requestId); });
      if (receipts.size > 256) receipts.delete(receipts.keys().next().value!);
      return promise;
    },
  };
}

/**
 * Makes this window the session host for remote access: it publishes the
 * session feed and runs the intents connected devices send. Only the `main`
 * window hosts, and only while remote access is on: it starts and stops as
 * `remote-status-changed` says, without a reload.
 */
export function useSessionHost(sessionsRef: MutableRefObject<Session[]>, intents: () => SessionIntents) {
  const latestIntents = useRef(intents);
  latestIntents.current = intents;
  const feed = useRef<SessionFeedPublisher | null>(null);
  const [leasedIds, setLeasedIds] = useState<string[]>([]);

  useEffect(() => {
    if (getCurrentWindow().label !== "main") return;

    /** Starts publishing and answering intents; the returned function undoes it. */
    const startHosting = async () => {
      const publisher = createSessionFeed(sessionsRef.current, (message) => {
        void transport.call("remote_session_publish", { feed: message }).catch(console.error);
      }, { settings: hostSettingsSnapshot });
      // Whoever wrote a shared setting, in this window or another of this
      // device's: devices hear the value now stored. Unchanged values are not resent.
      setHostSettingSink((key) => publisher.settingsChanged({ [key]: localStorage.getItem(key) }));
      const onStorage = (event: StorageEvent) => {
        if (event.key === null) publisher.settingsChanged(hostSettingsSnapshot());
        else if (isHostSharedKey(event.key)) publisher.settingsChanged({ [event.key]: localStorage.getItem(event.key) });
      };
      window.addEventListener("storage", onStorage);
      const host = createSessionHost({
        intents: () => latestIntents.current(), feed: publisher, onLeases: setLeasedIds,
        setSetting: (key, value) => {
          applyHostSettings({ [key]: value });
          const kept = localStorage.getItem(key);
          publisher.settingsChanged({ [key]: kept });
          return kept;
        },
        models: (harnesses) => readHostModels(harnesses),
        inspectBinary: inspectHarnessBinary,
      });
      const stop = () => {
        window.removeEventListener("storage", onStorage);
        setHostSettingSink(undefined);
        publisher.dispose();
        if (feed.current === publisher) feed.current = null;
        setLeasedIds([]);
      };
      try {
        const unlisten = await transport.listen<RemoteIntent>("loci-remote-intent", ({ payload }) => {
          void host.handle(payload).then(
            (value) => transport.call("remote_intent_reply", { requestId: payload.requestId, ok: true, value: value ?? null }),
            (error: unknown) => transport.call("remote_intent_reply", {
              requestId: payload.requestId, ok: false, error: error instanceof Error ? error.message : String(error),
            }),
          ).catch(console.error);
        });
        feed.current = publisher;
        // The gateway learns this page's epoch before any patch arrives.
        void transport.call("remote_session_publish", { feed: publisher.snapshot() }).catch(console.error);
        return () => { unlisten(); stop(); };
      } catch (error) {
        stop();
        throw error;
      }
    };

    let disposed = false;
    let stopHosting: (() => void) | undefined;
    // One change at a time, so turning it off and on quickly ends as asked.
    let changing = Promise.resolve();
    const want = (enabled: boolean) => {
      changing = changing.then(async () => {
        if (disposed) return;
        if (enabled && !stopHosting) {
          const stop = await startHosting();
          if (disposed) stop(); else stopHosting = stop;
        } else if (!enabled && stopHosting) {
          stopHosting();
          stopHosting = undefined;
        }
      }).catch(console.error);
    };
    const listening = transport.listen<{ enabled?: boolean }>("remote-status-changed", ({ payload }) => want(payload?.enabled === true));
    // Off when remote access is unavailable, including before the gateway exists.
    void transport.call<{ enabled?: boolean } | null>("remote_status").then((status) => want(status?.enabled === true), () => undefined);
    return () => {
      disposed = true;
      void listening.then((stop) => stop(), () => undefined);
      stopHosting?.();
      stopHosting = undefined;
    };
  }, [sessionsRef]);

  const sessionsChanged = useCallback((sessions: Session[]) => feed.current?.changed(sessions), []);
  return { sessionsChanged, leasedIds };
}
