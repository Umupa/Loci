// Vite aliases the public core import here so every app IPC write participates
// in reset, including debounced saves and writes queued by harness callbacks.
export * from "../../../node_modules/@tauri-apps/api/core";
import { t } from "../../shared/i18n/locale";
import { invoke as nativeInvoke, type InvokeArgs, type InvokeOptions } from "../../../node_modules/@tauri-apps/api/core";

const pending = new Set<Promise<unknown>>();
let suspended = false;
const pageId = crypto.randomUUID();
let requestSequence = 0;

export function invoke<T>(command: string, args?: InvokeArgs, options?: InvokeOptions): Promise<T> {
  if (command.startsWith("workspace_reset")) return nativeInvoke<T>(command, args, options);
  if (suspended && !command.startsWith("plugin:")) {
    return Promise.reject(new Error(t("Workspace reset in progress")));
  }
  // A destroy cannot acknowledge from the page it just unloaded. Its caller
  // already awaited persistence; closing a window does not write workspace data.
  if (command.startsWith("plugin:") || command === "destroy_window") return nativeInvoke<T>(command, args, options);
  const requestId = `${pageId}:${++requestSequence}`;
  const headers = new Headers(options?.headers);
  headers.set("x-loci-request-id", requestId);
  const request = nativeInvoke<T>(command, args, { ...options, headers: Object.fromEntries(headers) });
  // The backend keeps these tickets across page reloads. If a page disappears
  // before acknowledging a request, reset fails closed instead of trusting a
  // replacement page's empty pending set while Rust may still be writing.
  const settled = request.then(() => undefined, () => undefined).then(() =>
    nativeInvoke<void>("workspace_reset_request_finished", { requestId }));
  pending.add(settled);
  void settled.then(() => pending.delete(settled), () => pending.delete(settled));
  return request.then(
    async (value) => { await settled; return value; },
    async (reason: unknown) => { await settled; throw reason; },
  );
}

export async function suspendWorkspaceInvokes(): Promise<void> {
  suspended = true;
  await Promise.allSettled([...pending]);
}
