import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { canvasMcpProblem, canvasMcpServer, canvasMcpTool, canvasToolAutoAllowed, claudeCanvasMcpConfig, codexCanvasApprovalTool, codexCanvasMcpArgs } from "./mcpServer";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
beforeEach(() => vi.mocked(invoke).mockReset());

describe("the built-in Excalidraw MCP server", () => {
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
    expect(JSON.parse(claudeCanvasMcpConfig(server))).toEqual({ mcpServers: { excalidraw: { type: "stdio", ...server } } });
    const args = codexCanvasMcpArgs(server);
    expect(args.filter((_, index) => index % 2 === 0)).toEqual(["-c", "-c", "-c", "-c"]);
    // Each override is `key=<TOML value>`; JSON strings and string arrays are valid TOML.
    const overrides = Object.fromEntries(args.filter((_, index) => index % 2 === 1).map((entry) => {
      const split = entry.indexOf("=");
      return [entry.slice(0, split), JSON.parse(entry.slice(split + 1))];
    }));
    expect(overrides).toEqual({
      "mcp_servers.excalidraw.command": server.command,
      "mcp_servers.excalidraw.args": server.args,
      // Codex forwards only listed variables to an MCP server.
      "mcp_servers.excalidraw.env_vars": ["LOCI_APP_ENDPOINT", "LOCI_APP_TOKEN"],
      // Upstream marks drawing read-only; Codex must ask so the permission mode can decide.
      "mcp_servers.excalidraw.tools.create_view.approval_mode": "prompt",
    });
    expect([claudeCanvasMcpConfig(server), ...args].join(" ")).not.toMatch(/TOKEN=|"env"/);
  });

  it("recognizes its tools under each CLI's naming and nothing else", () => {
    expect(canvasMcpTool("mcp__excalidraw__create_view")).toBe("create_view");
    expect(canvasMcpTool("Read mcp__excalidraw__read_me")).toBe("read_me");
    expect(canvasMcpTool("excalidraw:read_widget_context")).toBe("read_widget_context");
    expect(canvasMcpTool("excalidraw.create_view")).toBe("create_view");
    for (const other of [undefined, "", "create_view", "mcp__excalidraw__save_checkpoint", "mcp__claude_ai_Excalidraw__create_view",
      "mcp__excalidraw__create_view_extra", "notexcalidraw:create_view", "echo mcp__excalidraw__create_view done"])
      expect(canvasMcpTool(other), String(other)).toBeUndefined();
  });

  it("recognizes a Codex approval request for its own drawing tool only", () => {
    const request = { serverName: "excalidraw", mode: "form", _meta: { codex_approval_kind: "mcp_tool_call" }, message: 'Allow the excalidraw MCP server to run tool "create_view"?' };
    expect(codexCanvasApprovalTool(request)).toBe("create_view");
    expect(codexCanvasApprovalTool({ ...request, serverName: "github" })).toBeUndefined();
    expect(codexCanvasApprovalTool({ ...request, _meta: {} })).toBeUndefined();
    expect(codexCanvasApprovalTool({ ...request, message: 'Allow the excalidraw MCP server to run tool "export_to_excalidraw"?' })).toBeUndefined();
    // An unfamiliar wording falls back to asking the user.
    expect(codexCanvasApprovalTool({ ...request, message: "Sign in to continue" })).toBeUndefined();
    expect(codexCanvasApprovalTool(null)).toBeUndefined();
  });

  it("asks before drawing only where edits are asked for", () => {
    for (const mode of ["supervised", "auto-accept-edits", "auto", "full-access"]) {
      expect(canvasToolAutoAllowed("read_me", mode)).toBe(true);
      expect(canvasToolAutoAllowed("read_widget_context", mode)).toBe(true);
      expect(canvasToolAutoAllowed("create_view", mode)).toBe(mode !== "supervised");
    }
  });
});
