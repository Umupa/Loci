import type { CallArgs, Transport, TransportEvent, Unlisten } from "./transport";

/**
 * Commands a connected device runs on its own machine: its windows, menus,
 * clipboard, notifications permission, appearance, and the connection itself.
 * Mirrors the `ClientLocal` class in `src-tauri/src/remote_catalog.rs`; a test
 * keeps the two lists equal.
 */
export const CLIENT_LOCAL_COMMANDS: ReadonlySet<string> = new Set([
  "save_chat_background", "remove_chat_background", "download_wallpaper",
  "fetch_link_preview", "keybindings_set_overrides",
  "notification_permission", "request_notification_permission", "open_notification_settings",
  "clipboard_file_paths", "clipboard_image",
  "set_window_glass_enabled", "hide_window", "destroy_window", "quit_poll_reply", "quit_decision", "quit_ready", "quit_app",
  "set_traffic_lights_visible", "set_window_background_blur", "set_dock_badge", "set_trackpad_zoom_enabled", "open_new_window",
  "remote_client_connect", "remote_client_call", "remote_client_subscribe", "remote_client_disconnect", "remote_client_upload",
  "remote_client_cache_put", "remote_client_cache_get",
  "remote_group_status", "remote_group_create", "remote_group_join", "remote_group_leave",
  "remote_devices_list", "remote_device_remove", "remote_settings_get", "remote_settings_set",
]);

/**
 * Commands that write this window's copy of the mentor roster (or view state
 * kept beside it) back to the host as a whole. The copy can be behind the
 * host's, so sending it would undo changes made there: a connected window
 * changes mentors through `agent.*` intents and reads the roster back.
 */
export const HOST_ROSTER_WRITES: ReadonlySet<string> = new Set(["mentors_sync", "mentors_remove", "storage_migrate", "mentor_state_set"]);

/** What the client bridge rejects with while there is no connection. */
export const NOT_CONNECTED = "Not connected to the host";
/** What a change made while the host is offline is refused with. Nothing is queued for later. */
export const HOST_OFFLINE = "The host is offline. This window is read-only until it is back.";
/** How long a change already on its way waits for a dropped connection to come back. */
export const RESEND_GRACE_MS = 10_000;

export type ConnectionState = "connecting" | "connected" | "disconnected";
export type ConnectionStatus = { state: ConnectionState; error?: string };

const MIME: Record<string, string> = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp",
  svg: "image/svg+xml", avif: "image/avif", bmp: "image/bmp", pdf: "application/pdf",
};

/**
 * The transport of a window connected to another device: commands and the
 * session feed go to the host through the client bridge, while the window's
 * own events (menus, zoom, quit) and `ClientLocal` commands stay here.
 *
 * While the host is offline the window is read-only: reads are answered from
 * what this device kept (the bridge does that), and changes are refused with
 * `HOST_OFFLINE`. An intent (a name with a dot, such as `session.submit`)
 * already on its way when the connection drops keeps its request id and is
 * sent again if the connection is back within `RESEND_GRACE_MS`, so the host
 * runs it once; one made while offline is refused at once.
 */
export function createRemoteTransport(local: Transport): Transport {
  const hostHandlers = new Map<string, Set<(event: TransportEvent<unknown>) => void>>();
  let state: ConnectionState = "connecting";
  let reconnected: (() => void)[] = [];
  const files = new Map<string, Promise<string>>();

  void local.listen<ConnectionStatus>("remote-client-status", ({ payload }) => {
    state = payload.state;
    if (state !== "connected") return;
    const waiting = reconnected;
    reconnected = [];
    for (const resume of waiting) resume();
  });
  void local.listen<{ name: string; payload: unknown }>("remote-client-event", ({ payload }) => {
    for (const handler of hostHandlers.get(payload.name) ?? []) handler({ event: payload.name, payload: payload.payload });
  });

  const connected = () => state === "connected" ? Promise.resolve() : new Promise<void>((resume) => reconnected.push(resume));

  /** Resolves true once connected again, false after the grace period. */
  const back = () => new Promise<boolean>((resolve) => {
    const timer = setTimeout(() => resolve(false), RESEND_GRACE_MS);
    void connected().then(() => { clearTimeout(timer); resolve(true); });
  });

  async function intent<T>(cmd: string, args: CallArgs | undefined): Promise<T> {
    if (state === "disconnected") throw new Error(HOST_OFFLINE);
    const requestId = crypto.randomUUID();
    for (;;) {
      try {
        return await local.call<T>("remote_client_call", { cmd, args: args ?? [], requestId });
      } catch (error) {
        if (String(error) !== NOT_CONNECTED) throw error;
        if (!await back()) throw new Error(HOST_OFFLINE);
      }
    }
  }

  async function command<T>(cmd: string, args: CallArgs | undefined): Promise<T> {
    try {
      return await local.call<T>("remote_client_call", { cmd, args: args ?? {} });
    } catch (error) {
      // A read the bridge could not answer from what it kept says so itself.
      throw String(error) === NOT_CONNECTED ? new Error(HOST_OFFLINE) : error;
    }
  }

  const transport: Transport = {
    call<T>(cmd: string, args?: CallArgs): Promise<T> {
      if (CLIENT_LOCAL_COMMANDS.has(cmd)) return local.call<T>(cmd, args);
      // The agent CLIs run only on the host, driven by its window.
      if (cmd.startsWith("harness_")) return Promise.reject(new Error(`${cmd} is not available on a connected device`));
      if (HOST_ROSTER_WRITES.has(cmd)) return Promise.reject(new Error(`${cmd} would overwrite the host's mentors with this window's copy`));
      if (cmd.includes(".")) return intent<T>(cmd, args);
      return command<T>(cmd, args);
    },
    async listen<T>(event: string, handler: (event: TransportEvent<T>) => void): Promise<Unlisten> {
      const handlers = hostHandlers.get(event) ?? new Set();
      hostHandlers.set(event, handlers);
      const forward = handler as (event: TransportEvent<unknown>) => void;
      handlers.add(forward);
      // A name with a dot (`session.feed`) is the host's alone, and not one Tauri accepts.
      const stopLocal = event.includes(".") ? undefined : await local.listen(event, handler);
      return () => { handlers.delete(forward); stopLocal?.(); };
    },
    fileUrl(path: string): Promise<string> {
      let url = files.get(path);
      if (!url) {
        url = transport.call<ArrayBuffer>("read_binary_file", { path }).then((bytes) =>
          URL.createObjectURL(new Blob([bytes], { type: MIME[path.split(".").pop()?.toLowerCase() ?? ""] ?? "" })));
        files.set(path, url);
        void url.catch(() => files.delete(path));
      }
      return url;
    },
  };
  return transport;
}
