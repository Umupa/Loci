import { beforeEach,describe,expect,it,vi } from "vitest";
import { AcpClient } from "./acp";

const writes = vi.hoisted(() => vi.fn(async (_sessionId: string, _line: string) => undefined));
vi.mock("./child", () => ({ writeChild: writes }));

beforeEach(() => writes.mockClear());

describe("ACP transport", () => {
  it("sends JSON-RPC requests and correlates the server response", async () => {
    const client = new AcpClient("local-session", {});
    const response = client.request("session/new", { cwd: "/project" });
    const request = JSON.parse(writes.mock.calls[0][1]);
    expect(request).toMatchObject({ jsonrpc: "2.0", method: "session/new", params: { cwd: "/project" } });
    client.pushLine(JSON.stringify({ jsonrpc: "2.0", id: request.id, result: { sessionId: "provider-session" } }));
    await expect(response).resolves.toEqual({ sessionId: "provider-session" });
    client.close();
  });

  it("routes permission requests and notifications without a provider adapter", async () => {
    const request = vi.fn();
    const notification = vi.fn();
    const client = new AcpClient("local-session", { onRequest: request, onNotification: notification });
    client.pushLine(JSON.stringify({ jsonrpc: "2.0", id: "12", method: "session/request_permission", params: { toolCall: "read" } }));
    expect(request).toHaveBeenCalledWith(12, "session/request_permission", { toolCall: "read" });
    await client.respond(12, { outcome: { outcome: "selected", optionId: "allow_once" } });
    expect(JSON.parse(writes.mock.calls[0][1])).toEqual({ jsonrpc: "2.0", id: 12, result: { outcome: { outcome: "selected", optionId: "allow_once" } } });
    client.pushLine(JSON.stringify({ jsonrpc: "2.0", method: "session/update", params: { sessionId: "provider-session" } }));
    expect(notification).toHaveBeenCalledWith("session/update", { sessionId: "provider-session" });
    client.close();
  });

  it("rejects pending operations when the transport closes", async () => {
    const client = new AcpClient("local-session", {});
    const request = client.request("session/load", { sessionId: "saved" });
    const rejected = expect(request).rejects.toThrow("transport closed");
    client.close(new Error("transport closed"));
    await rejected;
  });
});
