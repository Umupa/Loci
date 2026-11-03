import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { createRemoteTransport } from "./remoteTransport";

/** What a command takes: named arguments, or raw bytes for a binary body. */
export type CallArgs = Record<string, unknown> | unknown[] | ArrayBuffer | Uint8Array;

export type TransportEvent<T> = { event: string; payload: T };

export type Unlisten = () => void;

/**
 * How the app reaches the machine holding its data: commands, events from the
 * backend, and URLs for files the webview loads directly. This window's own
 * backend, or another device's when the window was opened to connect to one.
 * Window, menu and dialog APIs act on the device showing the app and stay
 * outside it (`./native`, `./dialog`).
 */
export interface Transport {
  call<T>(command: string, args?: CallArgs): Promise<T>;
  listen<T>(event: string, handler: (event: TransportEvent<T>) => void): Promise<Unlisten>;
  /** A URL the webview can load a file from, in place of `convertFileSrc`. */
  fileUrl(path: string): Promise<string>;
}

const tauriTransport: Transport = {
  // Forwarded as given, so a call without arguments stays one.
  call: <T>(...request: [command: string, args?: CallArgs]) => invoke<T>(...(request as Parameters<typeof invoke>)),
  listen: (event, handler) => listen(event, handler),
  fileUrl: async (path) => convertFileSrc(path),
};

export type RemoteTarget = { kind: "loopback" } | { kind: "device"; deviceId: string };

/**
 * The device a window shows, from its `?remote=`: `device:<deviceId>`, a
 * member of this device's group, or `loopback`, this Loci's own host (for
 * development). Nothing for a window showing this device.
 */
export function remoteTarget(search: string): RemoteTarget | undefined {
  const remote = new URLSearchParams(search).get("remote");
  if (remote === "loopback") return { kind: "loopback" };
  const device = remote?.match(/^device:([A-Za-z0-9_-]+)$/)?.[1];
  return device ? { kind: "device", deviceId: device } : undefined;
}

/** Decided while this module loads, so it is in place before any call. */
export const REMOTE_TARGET = typeof location !== "undefined" ? remoteTarget(location.search) : undefined;
export const REMOTE_CLIENT = !!REMOTE_TARGET;

export const transport: Transport = REMOTE_CLIENT ? createRemoteTransport(tauriTransport) : tauriTransport;
