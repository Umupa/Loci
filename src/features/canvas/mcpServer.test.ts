import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { canvasMcpProblem, canvasMcpServer, canvasMcpTool, canvasToolAutoAllowed, claudeCanvasMcpConfig, codexCanvasApprovalTool, codexCanvasMcpArgs } from "./mcpServer";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
beforeEach(() => vi.mocked(invoke).mockReset());
afterEach(() => vi.unstubAllGlobals());

describe("the built-in Excalidraw MCP server", () => {
  it("does not resolve or inject a server when the user has turned it off", async () => {
    vi.stubGlobal("localStorage", { getItem: () => "0" });
    expect(await canvasMcpServer()).toBeNull();
    expect(await canvasMcpProblem()).toBe("The built-in Excalidraw MCP is disabled in Settings → MCP.");
    expect(invoke).not.toHaveBeenCalled();
  });
  it("is offered when the app can start it and retried after a failure", async () => {
    vi.mocked(invoke).mockRejectedValueOnce("Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH.");
    expect(await canvasMcpServer()).toBeNull();
    vi.mocked(invoke).mockResolvedValue({ command: "node", args: ["bridge.mjs"] });
    expect(await canvasMcpServer()).toEqual({ command: "node", args: ["bridge.mjs"] });
    expect(await canvasMcpProblem()).toBeNull();
    vi.mocked(invoke).mockRejectedValue("Loci's Excalidraw MCP files are missing from this build.");
    expect(await canvasMcpProblem()).toBe("Loci's Excalidraw MCP files are missing from this build.");
    // Outside the desktop app there is nothing to report.
    vi.mocked(invoke).mockRejectedValue(new TypeError("Cannot read properties of undefined (reading 'invoke')"));
    expect(await canvasMcpProblem()).toBeNull();
    vi.mocked(invoke).mockResolvedValue(undefined);
    expect(await canvasMcpServer()).toBeNull();
  });

  it("is configured for both CLIs without putting the session credential on a command line", () => {
    const server = { command: 'C:\\Program Files\\nodejs\\node.exe', args: ['C:\\Users\\Zoë "Z"\\Loci\\loci-bridge.mjs'] };
    expect(JSON.parse(claudeCanvasMcpConfig(server))).toEqual({ mcpServers: { loci_excalidraw: { type: "stdio", ...server } } });
    const args = codexCanvasMcpArgs(server);
    expect(args.filter((_, index) => index % 2 === 0)).toEqual(["-c", "-c", "-c", "-c", "-c"]);
    // Each override is `key=<TOML value>`; JSON strings and string arrays are valid TOML.
    const overrides = Object.fromEntries(args.filter((_, index) => index % 2 === 1).map((entry) => {
      const split = entry.indexOf("=");
      return [entry.slice(0, split), JSON.parse(entry.slice(split + 1))];
    }));
    expect(overrides).toEqual({
      "mcp_servers.loci_excalidraw.command": server.command,
      "mcp_servers.loci_excalidraw.args": server.args,
      // Codex forwards only listed variables to an MCP server.
      "mcp_servers.loci_excalidraw.env_vars": ["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"],
      // Upstream marks drawing read-only; Codex must ask so the permission mode can decide.
      "mcp_servers.loci_excalidraw.tools.create_view.approval_mode": "prompt",
      "mcp_servers.loci_excalidraw.tools.update_elements.approval_mode": "prompt",
    });
    expect([claudeCanvasMcpConfig(server), ...args].join(" ")).not.toMatch(/TOKEN=|"env"/);
  });

  it("keeps a user's remote Excalidraw server separate from the built-in stdio server", () => {
    const userServers: Record<string, Record<string, unknown>> = {
      excalidraw: { url: "http://127.0.0.1:1/mcp" },
      other: { command: "/user/tool", args: ["serve"] },
    };
    for (const entry of codexCanvasMcpArgs({ command: "/usr/bin/node", args: ["/app/bridge.mjs"] }).filter((_, i) => i % 2 === 1)) {
      const [path, ...value] = entry.split("=");
      const [, name, field] = path.split(".");
      userServers[name] ??= {};
      userServers[name][field] = JSON.parse(value.join("="));
    }
    expect(userServers.excalidraw).toEqual({ url: "http://127.0.0.1:1/mcp" });
    expect(userServers.other).toEqual({ command: "/user/tool", args: ["serve"] });
    expect(userServers.loci_excalidraw).toMatchObject({ command: "/usr/bin/node", args: ["/app/bridge.mjs"] });
    expect(userServers.loci_excalidraw).not.toHaveProperty("url");
  });

  it("recognizes its tools under each CLI's naming and nothing else", () => {
    expect(canvasMcpTool("mcp__loci_excalidraw__create_view")).toBe("create_view");
    expect(canvasMcpTool("Read mcp__loci_excalidraw__read_me")).toBe("read_me");
    expect(canvasMcpTool("loci_excalidraw:read_widget_context")).toBe("read_widget_context");
    expect(canvasMcpTool("mcp__loci_excalidraw__get_elements")).toBe("get_elements");
    expect(canvasMcpTool("loci_excalidraw:update_elements")).toBe("update_elements");
    expect(canvasMcpTool("loci_excalidraw.create_view")).toBe("create_view");
    for (const other of [undefined, "", "create_view", "mcp__excalidraw__create_view", "excalidraw:create_view", "mcp__loci_excalidraw__save_checkpoint", "mcp__claude_ai_Excalidraw__create_view",
      "mcp__loci_excalidraw__create_view_extra", "notexcalidraw:create_view", "echo mcp__loci_excalidraw__create_view done"])
      expect(canvasMcpTool(other), String(other)).toBeUndefined();
  });

  it("recognizes a Codex approval request for its own drawing tool only", () => {
    const request = { serverName: "loci_excalidraw", mode: "form", _meta: { codex_approval_kind: "mcp_tool_call" }, message: 'Allow the loci_excalidraw MCP server to run tool "create_view"?' };
    expect(codexCanvasApprovalTool(request)).toBe("create_view");
    expect(codexCanvasApprovalTool({ ...request, serverName: "github" })).toBeUndefined();
    expect(codexCanvasApprovalTool({ ...request, serverName: "excalidraw" })).toBeUndefined();
    expect(codexCanvasApprovalTool({ ...request, _meta: {} })).toBeUndefined();
    expect(codexCanvasApprovalTool({ ...request, message: 'Allow the loci_excalidraw MCP server to run tool "export_to_excalidraw"?' })).toBeUndefined();
    // An unfamiliar wording falls back to asking the user.
    expect(codexCanvasApprovalTool({ ...request, message: "Sign in to continue" })).toBeUndefined();
    expect(codexCanvasApprovalTool(null)).toBeUndefined();
  });

  it("asks before drawing only where edits are asked for", () => {
    for (const mode of ["supervised", "auto-accept-edits", "auto", "full-access"]) {
      expect(canvasToolAutoAllowed("read_me", mode)).toBe(true);
      expect(canvasToolAutoAllowed("read_widget_context", mode)).toBe(true);
      expect(canvasToolAutoAllowed("create_view", mode)).toBe(mode !== "supervised");
      expect(canvasToolAutoAllowed("update_elements", mode)).toBe(mode !== "supervised");
      expect(canvasToolAutoAllowed("get_elements", mode)).toBe(true);
    }
  });
});
