import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import { CLIENT_LOCAL_COMMANDS, createRemoteTransport, HOST_ROSTER_WRITES } from "./remoteTransport";
import { remoteTarget, type Transport, type TransportEvent } from "./transport";

function bridge() {
  const handlers = new Map<string, (event: TransportEvent<unknown>) => void>();
  const local = {
    call: vi.fn(async (..._request: unknown[]): Promise<unknown> => "local"),
    listen: vi.fn(async (event: string, handler: (event: TransportEvent<unknown>) => void) => {
      handlers.set(event, handler);
      return () => handlers.delete(event);
    }),
    fileUrl: vi.fn(),
  };
  const emit = (event: string, payload: unknown) => handlers.get(event)?.({ event, payload });
  return { local, emit, transport: createRemoteTransport(local as unknown as Transport) };
}

describe("createRemoteTransport", () => {
  it("runs the window's own commands here and everything else on the host", async () => {
    const { local, transport } = bridge();
    await transport.call("set_dock_badge", { count: 2 });
    await transport.call("notes_get", { id: "n" });
    await transport.call("home_dir");
    expect(local.call.mock.calls).toEqual([
      ["set_dock_badge", { count: 2 }],
      ["remote_client_call", { cmd: "notes_get", args: { id: "n" } }],
      ["remote_client_call", { cmd: "home_dir", args: {} }],
    ]);
  });

  it("never writes this window's copy of the mentor roster back to the host", async () => {
    const { local, transport } = bridge();
    expect([...HOST_ROSTER_WRITES].sort()).toEqual(["mentor_state_set", "mentors_remove", "mentors_sync", "storage_migrate"]);
    for (const cmd of HOST_ROSTER_WRITES) {
      await expect(transport.call(cmd, { roster: [] })).rejects.toThrow("would overwrite the host's mentors");
    }
    expect(local.call).not.toHaveBeenCalled();
    // Reading the host's roster is how a window gets it.
    await transport.call("mentors_load");
    expect(local.call).toHaveBeenCalledWith("remote_client_call", { cmd: "mentors_load", args: {} });
  });

  it("sends an intent with a request id and its arguments in order", async () => {
    const { local, transport } = bridge();
    await transport.call("session.stop", ["s"]);
    expect(local.call).toHaveBeenCalledWith("remote_client_call", { cmd: "session.stop", args: ["s"], requestId: expect.any(String) });
  });

  it("passes on the host's events by name, beside the window's own", async () => {
    const { local, emit, transport } = bridge();
    const feed = vi.fn();
    const zoom = vi.fn();
    const stop = await transport.listen("session.feed", feed);
    await transport.listen("zoom_in", zoom);
    emit("remote-client-event", { name: "session.feed", payload: { seq: 1 } });
    emit("remote-client-event", { name: "other", payload: {} });
    emit("zoom_in", null);
    expect(feed).toHaveBeenCalledExactlyOnceWith({ event: "session.feed", payload: { seq: 1 } });
    // Tauri refuses event names with a dot; the host's events never reach it.
    expect(local.listen.mock.calls.map(([event]) => event)).not.toContain("session.feed");
    expect(zoom).toHaveBeenCalledOnce();
    stop();
    emit("remote-client-event", { name: "session.feed", payload: { seq: 2 } });
    expect(feed).toHaveBeenCalledOnce();
  });

  it("loads a host file into an object URL once", async () => {
    const { local, transport } = bridge();
    local.call.mockResolvedValue(new Uint8Array([1, 2]).buffer);
    const created = vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:one");
    await expect(transport.fileUrl("/notes/a.png")).resolves.toBe("blob:one");
    await expect(transport.fileUrl("/notes/a.png")).resolves.toBe("blob:one");
    expect(local.call).toHaveBeenCalledExactlyOnceWith("remote_client_call", { cmd: "read_binary_file", args: { path: "/notes/a.png" } });
    expect((created.mock.calls[0][0] as Blob).type).toBe("image/png");
    created.mockRestore();
  });

  it("keeps the same commands on this device as the command catalog does", () => {
    const catalog = readFileSync(new URL("../../src-tauri/src/remote_catalog.rs", import.meta.url), "utf8");
    const clientLocal = [...catalog.matchAll(/\("([a-z_]+)", ClientLocal\)/g)].map((match) => match[1]);
    expect(clientLocal.length).toBeGreaterThan(10);
    expect([...CLIENT_LOCAL_COMMANDS].sort()).toEqual(clientLocal.sort());
  });
});

describe("remoteTarget", () => {
  it("reads which device a window shows from its address", () => {
    expect(remoteTarget("?remote=loopback")).toEqual({ kind: "loopback" });
    expect(remoteTarget("?remote=device:Ab9_-x")).toEqual({ kind: "device", deviceId: "Ab9_-x" });
    expect(remoteTarget("?remote=device:")).toBeUndefined();
    expect(remoteTarget("?remote=device:a%26b")).toBeUndefined();
    expect(remoteTarget("")).toBeUndefined();
  });
});
