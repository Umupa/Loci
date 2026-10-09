// @vitest-environment happy-dom
import { act, createElement, StrictMode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { McpSettings } from "./McpSettings";
import { clearMcpSettingsCache } from "../model/mcpSettingsCache";
import { CANVAS_MCP_ENABLED_KEY } from "../model/builtinMcp";

const invoke = vi.fn();
const connectionCalls = () => invoke.mock.calls.filter(([command]) => command === "mcp_discover" || command === "claude_mcp_list");
const ask = vi.fn(async () => true);
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...args: unknown[]) => invoke(...args),
}));
vi.mock("@tauri-apps/plugin-dialog", () => ({
  ask: (...args: unknown[]) => ask(...args),
}));

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  clearMcpSettingsCache();
  const storage = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
    removeItem: (key: string) => storage.delete(key),
  });
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  container = document.createElement("div");
  document.body.append(container);
  root = createRoot(container);
  invoke.mockReset();
  invoke.mockImplementation(async (command: string) =>
    command === "mcp_discover"
      ? [
          {
            provider: "claude",
            name: "sentry",
            scope: "user",
            configPath: "/home/.claude.json",
            transport: "http",
          },
          {
            provider: "codex",
            name: "docs",
            scope: "user",
            configPath: "/home/.codex/config.toml",
            transport: "http",
          },
        ]
      : command === "claude_mcp_list"
        ? "sentry: https://mcp.example.com - ! Needs authentication"
        : undefined,
  );
});

afterEach(async () => {
  await act(async () => root.unmount());
  clearMcpSettingsCache();
  container.remove();
  vi.unstubAllGlobals();
});

async function selectProject(path: string) {
  await act(async () =>
    container
      .querySelector<HTMLButtonElement>('[aria-label^="Switch project"]')!
      .click(),
  );
  expect(
    document.querySelector('input[placeholder="Search projects..."]'),
  ).not.toBeNull();
  await act(async () =>
    document
      .querySelector<HTMLButtonElement>(
        `[role="dialog"] button[title="${path}"]`,
      )!
      .click(),
  );
}

it("shows the app-owned canvas server and preserves its off switch across settings and projects", async () => {
  await act(async () => root.render(createElement(McpSettings, { cwd: "/repo" })));
  const builtin = () => container.querySelector('[data-setting-id="builtin-excalidraw"]')!;
  const toggle = () => builtin().querySelector<HTMLButtonElement>('[role="switch"]')!;
  expect(builtin().textContent).toContain("Built-in MCP");
  expect(builtin().textContent).toContain("loci_excalidraw · Local · Enabled");
  expect(builtin().textContent).toContain("Claude Code");
  expect(builtin().textContent).toContain("Codex");
  // Agents that call the built-in servers through Loci's CLI are listed with those that attach them.
  for (const id of ["builtin-excalidraw"]) {
    const card = container.querySelector(`[data-setting-id="${id}"]`)!;
    for (const name of ["Claude Code", "Codex", "Antigravity", "Pi"]) expect(card.textContent).toContain(name);
    expect(card.textContent).not.toContain("Cursor");
  }
  expect(builtin().textContent).toContain("next turn");
  expect(toggle().getAttribute("aria-checked")).toBe("true");
  await act(async () => toggle().click());
  expect(toggle().getAttribute("aria-checked")).toBe("false");
  expect(builtin().textContent).toContain("Disabled");
  expect(localStorage.getItem(CANVAS_MCP_ENABLED_KEY)).toBe("0");
  expect(container.textContent).toContain("docs");
  expect(invoke.mock.calls.map(([command]) => command)).not.toContain("mcp_add");
  expect(invoke.mock.calls.map(([command]) => command)).not.toContain("claude_mcp_remove");
  await act(async () => root.unmount());
  root = createRoot(container);
  await act(async () => root.render(createElement(McpSettings, { cwd: "/another-project" })));
  expect(toggle().getAttribute("aria-checked")).toBe("false");
  await act(async () => toggle().click());
  expect(builtin().textContent).toContain("Enabled");
  expect(localStorage.getItem(CANVAS_MCP_ENABLED_KEY)).toBe("1");
});

it("explains a missing runtime and can retry after it is installed", async () => {
  const original = invoke.getMockImplementation()!;
  let available = false;
  invoke.mockImplementation((command: string, args: unknown) => command === "canvas_mcp_server"
    ? available ? Promise.resolve({ command: "node", args: ["bridge.mjs"] }) : Promise.reject("Excalidraw drawing tools need Node.js 20.11 or newer (or Bun) on your PATH.")
    : original(command, args));
  await act(async () => root.render(createElement(McpSettings, { cwd: "/repo" })));
  const builtin = container.querySelector('[data-setting-id="builtin-excalidraw"]')!;
  expect(builtin.textContent).toContain("Unavailable");
  expect(builtin.querySelector('[role="status"]')?.textContent).toContain("Node.js 20.11");
  available = true;
  await act(async () => builtin.querySelector<HTMLButtonElement>('button:not([role="switch"])')!.click());
  expect(builtin.textContent).toContain("Enabled");
  expect(builtin.querySelector('[role="status"]')).toBeNull();
});

it("updates the built-in switch when another window changes it", async () => {
  await act(async () => root.render(createElement(McpSettings, { cwd: "/repo" })));
  await act(async () => {
    localStorage.setItem(CANVAS_MCP_ENABLED_KEY, "0");
    window.dispatchEvent(new StorageEvent("storage", { key: CANVAS_MCP_ENABLED_KEY }));
  });
  expect(container.querySelector('[role="switch"]')?.getAttribute("aria-checked")).toBe("false");
});

it("lists servers and routes sign in through Claude MCP", async () => {
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  expect(container.textContent).toContain("sentry");
  expect(container.textContent).toContain("Needs authentication");
  expect(container.textContent).toContain("Codex");
  const signIn = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Sign in",
  )!;
  await act(async () => signIn.click());
  expect(invoke).toHaveBeenCalledWith("mcp_provider_login", {
    cwd: "/repo",
    provider: "claude",
    name: "sentry",
  });
});

it("filters connections by provider", async () => {
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  const codex = [...container.querySelectorAll("button")].find((button) =>
    button.textContent?.startsWith("Codex"),
  )!;
  await act(async () => codex.click());
  expect(container.textContent).toContain("docs");
  expect(container.textContent).not.toContain("sentry");
  const signIn = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Sign in",
  )!;
  await act(async () => signIn.click());
  expect(invoke).toHaveBeenCalledWith("mcp_provider_login", {
    cwd: "/repo",
    provider: "codex",
    name: "docs",
  });
});

it("shows configured rows while Claude health is still pending", async () => {
  let resolveHealth!: (output: string) => void;
  const discovery = invoke.getMockImplementation()!;
  invoke.mockImplementation((command: string, args: unknown) =>
    command === "claude_mcp_list"
      ? new Promise((resolve) => {
          resolveHealth = resolve;
        })
      : discovery(command, args),
  );
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  expect(container.textContent).toContain("docs");
  expect(container.textContent).toContain("sentry");
  expect(container.textContent).not.toContain("Checking servers…");
  await act(async () =>
    resolveHealth("sentry: https://example.com - Needs authentication"),
  );
  expect(container.textContent).toContain("Needs authentication");
});

it("adds a standard mcpServers entry to the selected provider and project", async () => {
  await act(async () =>
    root.render(
      createElement(McpSettings, {
        cwd: "/repo",
        recents: [{ path: "/other", openedAt: 1 }],
      }),
    ),
  );
  await selectProject("/other");
  await act(async () =>
    container
      .querySelector<HTMLButtonElement>('[aria-label="Add MCP server"]')!
      .click(),
  );
  expect(document.body.textContent).toContain("Add MCP server");
  const provider = document.body.querySelector<HTMLButtonElement>(
    '[aria-label="Provider: Claude Code"]',
  )!;
  await act(async () => provider.click());
  const chosenProvider = [
    ...document.body.querySelectorAll<HTMLButtonElement>('[role="option"]'),
  ].find((button) => button.textContent === "Claude Code")!;
  await act(async () => chosenProvider.click());
  const config = document.body.querySelector<HTMLTextAreaElement>("textarea")!;
  const json =
    '{"mcpServers":{"new-server":{"command":"npx","args":["example"]}}}';
  await act(async () => {
    Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype,
      "value",
    )!.set!.call(config, json);
    config.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await act(async () =>
    document.body
      .querySelector("form")!
      .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true })),
  );
  expect(invoke).toHaveBeenCalledWith("mcp_add", {
    cwd: "/other",
    provider: "claude",
    name: "",
    config: json,
    scope: "local",
  });
  expect(invoke).toHaveBeenLastCalledWith("claude_mcp_list", { cwd: "/other" });
});

it("navigates provider choices with arrow keys", async () => {
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  await act(async () =>
    container
      .querySelector<HTMLButtonElement>('[aria-label="Add MCP server"]')!
      .click(),
  );
  await act(async () =>
    document.body
      .querySelector<HTMLButtonElement>('[aria-label="Provider: Claude Code"]')!
      .click(),
  );
  const list = document.body.querySelector<HTMLElement>(
    '[role="listbox"][aria-label="Provider"]',
  )!;
  const options = list.querySelectorAll<HTMLButtonElement>('[role="option"]');
  await act(async () =>
    list.dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }),
    ),
  );
  expect(document.activeElement).toBe(options[0]);
  await act(async () =>
    options[0].dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }),
    ),
  );
  expect(document.activeElement).toBe(options[options.length - 1]);
});

it("hides Sign in when a server has no known transport", async () => {
  invoke.mockImplementation(async (command: string) =>
    command === "mcp_discover"
      ? [
          {
            provider: "claude",
            name: "unknown",
            scope: "local",
            configPath: "",
            transport: "",
          },
        ]
      : "",
  );
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  expect(container.textContent).toContain("unknown");
  expect(
    [...container.querySelectorAll("button")].some(
      (button) => button.textContent === "Sign in",
    ),
  ).toBe(false);
});

it("shows only configured provider chips until the filter button reveals all", async () => {
 const original = invoke.getMockImplementation()!;
 invoke.mockImplementation(async (...args: unknown[]) => { const result = await original(...args); return args[0] === "mcp_discover" ? result.filter((row: {provider:string})=>row.provider === "claude") : result; });
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  const chips = container.querySelector(
    '[aria-label="Filter MCP servers by provider"]',
  )!;
  expect(chips.textContent).toContain("Claude Code");
  expect(chips.textContent).not.toContain("Codex");
  await act(async () =>
    container
      .querySelector<HTMLButtonElement>('[aria-label="Show all providers"]')!
      .click(),
  );
  expect(chips.textContent).toContain("Codex");
  await act(async () =>
    container
      .querySelector<HTMLButtonElement>(
        '[aria-label="Show available providers"]',
      )!
      .click(),
  );
  expect(chips.textContent).not.toContain("Codex");
});

it("ignores discovery from a previous project after cwd changes", async () => {
  let resolveOld!: (connections: unknown[]) => void;
  invoke.mockImplementation((command: string, args: { cwd: string }) => {
    if (command === "claude_mcp_list") return Promise.resolve("");
    if (args.cwd === "/old")
      return new Promise((resolve) => {
        resolveOld = resolve;
      });
    return Promise.resolve([
      {
        provider: "claude",
        name: "new-project",
        scope: "project",
        configPath: "/new/.claude/mcp.json",
        transport: "stdio",
      },
    ]);
  });
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/old" })),
  );
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/new" })),
  );
  expect(container.textContent).toContain("new-project");
  await act(async () =>
    resolveOld([
      {
        provider: "claude",
        name: "old-project",
        scope: "project",
        configPath: "/old/.claude/mcp.json",
        transport: "stdio",
      },
    ]),
  );
  expect(container.textContent).toContain("new-project");
  expect(container.textContent).not.toContain("old-project");
});

it("reuses the loaded list when returning to the page and reloads on Refresh", async () => {
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  expect(connectionCalls()).toHaveLength(2);
  await act(async () => root.render(null));
  await act(() => root.render(createElement(McpSettings, { cwd: "/repo" })));
  expect(container.textContent).toContain("sentry");
  expect(container.textContent).not.toContain("Checking servers…");
  expect(connectionCalls()).toHaveLength(2);

  invoke.mockImplementation(async (command: string) =>
    command === "mcp_discover"
      ? [
          {
            provider: "claude",
            name: "updated",
            scope: "project",
            configPath: "/repo/.claude/mcp.json",
            transport: "stdio",
          },
        ]
      : "",
  );
  const refresh = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Refresh",
  )!;
  await act(async () => refresh.click());
  expect(connectionCalls()).toHaveLength(4);
  expect(container.textContent).toContain("updated");
  expect(container.textContent).not.toContain("sentry");

  await act(async () => root.render(null));
  await act(() => root.render(createElement(McpSettings, { cwd: "/repo" })));
  expect(container.textContent).toContain("updated");
  expect(container.textContent).not.toContain("Checking servers…");
  expect(connectionCalls()).toHaveLength(4);
});

it("shares the first request across StrictMode and navigation while loading", async () => {
  let resolveDiscovery!: (connections: unknown[]) => void;
  let resolveHealth!: (output: string) => void;
  invoke.mockImplementation((command: string) =>
    command === "mcp_discover"
      ? new Promise((resolve) => {
          resolveDiscovery = resolve;
        })
      : command === "claude_mcp_list" ? new Promise((resolve) => {
          resolveHealth = resolve;
        }) : Promise.resolve(undefined),
  );
  const page = () =>
    createElement(
      StrictMode,
      null,
      createElement(McpSettings, { cwd: "/repo" }),
    );
  await act(async () => root.render(page()));
  expect(connectionCalls()).toHaveLength(1);
  await act(async () => root.render(null));
  await act(async () => root.render(page()));
  expect(connectionCalls()).toHaveLength(1);
  await act(async () => resolveDiscovery([]));
  expect(connectionCalls()).toHaveLength(2);
  await act(async () => root.render(null));
  await act(async () => root.render(page()));
  expect(connectionCalls()).toHaveLength(2);
  await act(async () =>
    resolveHealth("remote: https://mcp.example.com - Connected"),
  );
  expect(container.textContent).toContain("remote");
  expect(container.textContent).toContain("Connected");
  expect(container.textContent).not.toContain("Checking servers…");
});

it("caches an empty list until manually refreshed", async () => {
  invoke.mockImplementation(async (command: string) =>
    command === "mcp_discover" ? [] : "",
  );
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  await act(async () => root.render(null));
  await act(() => root.render(createElement(McpSettings, { cwd: "/repo" })));
  expect(container.textContent).toContain("No MCP servers configured");
  expect(container.textContent).not.toContain("Checking servers…");
  expect(connectionCalls()).toHaveLength(2);
});

it("retries discovery failures when reopened and still supports explicit Refresh", async () => {
  const original = invoke.getMockImplementation()!;
  let failed = false;
  invoke.mockImplementation((command: string, args: unknown) => {
    if (command === "mcp_discover" && !failed) {
      failed = true;
      return Promise.reject(new Error("Discovery failed"));
    }
    return original(command, args);
  });
  await act(async () =>
    root.render(createElement(McpSettings, { cwd: "/repo" })),
  );
  expect(container.textContent).toContain("Discovery failed");
  expect(connectionCalls()).toHaveLength(1);
  await act(async () => root.render(null));
  await act(() => root.render(createElement(McpSettings, { cwd: "/repo" })));
  expect(container.textContent).not.toContain("Discovery failed");
  expect(container.textContent).toContain("sentry");
  expect(connectionCalls()).toHaveLength(3);
  const refresh = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Refresh",
  )!;
  await act(async () => refresh.click());
  expect(container.textContent).toContain("sentry");
  expect(container.textContent).not.toContain("Discovery failed");
  expect(connectionCalls()).toHaveLength(5);
});

it("uses the shared project picker and caches each project's list", async () => {
  invoke.mockImplementation(async (command: string, args: { cwd: string }) =>
    command === "mcp_discover"
      ? [
          {
            provider: "claude",
            name: `${args.cwd.slice(1)}-server`,
            scope: "project",
            configPath: `${args.cwd}/.claude/mcp.json`,
            transport: "stdio",
          },
        ]
      : "",
  );
  await act(async () =>
    root.render(
      createElement(McpSettings, {
        cwd: "/repo",
        recents: [{ path: "/other", openedAt: 1 }],
      }),
    ),
  );
  expect(container.textContent).toContain("repo-server");
  await selectProject("/other");
  expect(container.textContent).toContain("other-server");
  expect(container.textContent).not.toContain("repo-server");
  expect(invoke).toHaveBeenCalledWith("mcp_discover", { cwd: "/other" });
  expect(invoke).toHaveBeenCalledWith("claude_mcp_list", { cwd: "/other" });
  expect(connectionCalls()).toHaveLength(4);
  await selectProject("/repo");
  expect(container.textContent).toContain("repo-server");
  expect(container.textContent).not.toContain("Checking servers…");
  expect(connectionCalls()).toHaveLength(4);
  await selectProject("/other");
  const refresh = [...container.querySelectorAll("button")].find(
    (button) => button.textContent === "Refresh",
  )!;
  await act(async () => refresh.click());
  expect(connectionCalls()).toHaveLength(6);
  expect(invoke).toHaveBeenLastCalledWith("claude_mcp_list", { cwd: "/other" });
});
