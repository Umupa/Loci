import { beforeEach, expect, it, vi } from "vitest";
const { nativeInvoke } = vi.hoisted(() => ({ nativeInvoke: vi.fn() }));
vi.mock("../../../node_modules/@tauri-apps/api/core", () => ({ invoke: nativeInvoke }));
beforeEach(() => { vi.resetModules(); nativeInvoke.mockReset().mockResolvedValue(undefined); });
it("drains existing saves and prevents queued snapshots from being written after reset starts", async () => {
  const { invoke, suspendWorkspaceInvokes } = await import("./core");
  let finish!: () => void;
  nativeInvoke.mockReturnValueOnce(new Promise<void>((resolve) => { finish = resolve; }));
  const save = invoke("workspace_set_snapshot", { snapshot: "old" });
  let drained = false;
  const drain = suspendWorkspaceInvokes().then(() => { drained = true; });
  await expect(invoke("session_upsert", { session: "old" })).rejects.toThrow("Workspace reset");
  expect(drained).toBe(false);
  expect(nativeInvoke).toHaveBeenCalledTimes(1);
  finish();
  await save;
  await drain;
  expect(drained).toBe(true);
  await expect(invoke("workspace_set_snapshot")).rejects.toThrow("Workspace reset");
  nativeInvoke.mockResolvedValueOnce(null);
  await expect(invoke("workspace_reset_status")).resolves.toBeNull();
});
it("settles failed requests without a stuck reset, and does not await plugin listeners", async () => {
  const { invoke, suspendWorkspaceInvokes } = await import("./core");
  nativeInvoke.mockImplementation((command: string) => command === "notes_upsert"
    ? Promise.reject(new Error("failed save"))
    : command === "plugin:event|listen" ? new Promise(() => {}) : Promise.resolve());
  await expect(invoke("notes_upsert")).rejects.toThrow("failed save");
  void invoke("plugin:event|listen");
  await suspendWorkspaceInvokes();
  expect(nativeInvoke).toHaveBeenCalledWith("workspace_reset_request_finished", { requestId: expect.any(String) });
});

it("uses serializable tickets for both native IPC transports and preserves caller headers", async () => {
  const { invoke, suspendWorkspaceInvokes } = await import("./core");
  await invoke("session_upsert", { session: "data" }, { headers: new Headers({ "x-existing": "value" }) });
  await suspendWorkspaceInvokes();
  const headers = nativeInvoke.mock.calls[0][2].headers;
  expect(JSON.parse(JSON.stringify(headers))).toEqual({
    "x-existing": "value", "x-loci-request-id": expect.any(String),
  });
  expect(nativeInvoke).toHaveBeenCalledWith("workspace_reset_request_finished", { requestId: headers["x-loci-request-id"] });
});

it("does not wait for an acknowledgement from a destroyed caller page", async () => {
  const { invoke, suspendWorkspaceInvokes } = await import("./core");
  await invoke("destroy_window");
  await suspendWorkspaceInvokes();
  expect(nativeInvoke).toHaveBeenCalledExactlyOnceWith("destroy_window", undefined, undefined);
});
it("acknowledges a save before callers can close their window", async () => {
  const { invoke } = await import("./core");
  let acknowledge!: () => void;
  nativeInvoke.mockImplementation((command: string) => command === "workspace_reset_request_finished"
    ? new Promise<void>((resolve) => { acknowledge = resolve; }) : Promise.resolve("saved"));
  let saved = false;
  const result = invoke("workspace_set_snapshot").then(() => { saved = true; });
  await vi.waitFor(() => expect(acknowledge).toBeDefined());
  expect(saved).toBe(false);
  acknowledge();
  await result;
  expect(saved).toBe(true);
});
