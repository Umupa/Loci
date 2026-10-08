import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { McpConnection } from "./mcp";
import {
  clearMcpSettingsCache,
  getCachedMcpSettings,
  loadMcpSettings,
  subscribeMcpSettings,
} from "./mcpSettingsCache";

const invoke = vi.hoisted(() => vi.fn());
vi.mock("@tauri-apps/api/core", () => ({ invoke }));

const configured: McpConnection[] = [
  {
    provider: "claude",
    name: "docs",
    scope: "project",
    configPath: "/repo/.mcp.json",
    transport: "stdio",
  },
];

beforeEach(() => {
  clearMcpSettingsCache();
  invoke.mockReset();
});
afterEach(clearMcpSettingsCache);

it("retries a failed discovery on the next access without a forced refresh", async () => {
  invoke.mockRejectedValueOnce(new Error("temporary discovery failure")).mockResolvedValue(configured);
  const failed = await loadMcpSettings("/retry", false, { claudeHealth: false });
  expect(failed.error).toContain("temporary discovery failure");
  const recovered = await loadMcpSettings("/retry", false, { claudeHealth: false });
  expect(recovered.error).toBe("");
  expect(recovered.servers[0].name).toBe("docs");
  expect(invoke).toHaveBeenCalledTimes(2);
});

it("shares concurrent retries after a discovery failure", async () => {
  invoke.mockRejectedValueOnce(new Error("offline"));
  await loadMcpSettings("/concurrent", false, { claudeHealth: false });
  let finish!: (servers: McpConnection[]) => void;
  invoke.mockImplementation(() => new Promise((resolve) => { finish = resolve; }));
  const consumers = Array.from({ length: 20 }, () => loadMcpSettings("/concurrent", false, { claudeHealth: false }));
  expect(invoke).toHaveBeenCalledTimes(2);
  finish(configured);
  const results = await Promise.all(consumers);
  expect(results.every((snapshot) => snapshot.servers[0].name === "docs" && !snapshot.error)).toBe(true);
});

it("retries failed health while continuing to share successful discovery", async () => {
  let healthCalls = 0;
  invoke.mockImplementation(async (command: string) => {
    if (command === "mcp_discover") return configured;
    if (++healthCalls === 1) throw new Error("temporary health failure");
    return "docs: local - Connected";
  });
  await loadMcpSettings("/retry-health");
  await vi.waitFor(() => expect(getCachedMcpSettings("/retry-health")?.claudeError).toContain("temporary health failure"));
  await loadMcpSettings("/retry-health");
  await vi.waitFor(() => expect(getCachedMcpSettings("/retry-health")?.claudeError).toBe(""));
  expect(getCachedMcpSettings("/retry-health")?.servers[0].status).toBe("Connected");
  expect(invoke.mock.calls.filter(([command]) => command === "mcp_discover")).toHaveLength(1);
  expect(healthCalls).toBe(2);
});

it("publishes discovery before slow health and shares both requests across consumers", async () => {
  let resolveHealth!: (output: string) => void;
  invoke.mockImplementation((command: string) =>
    command === "mcp_discover"
      ? Promise.resolve(configured)
      : new Promise((resolve) => {
          resolveHealth = resolve;
        }),
  );
  const onChange = vi.fn();
  const stop = subscribeMcpSettings("/repo", onChange);
  try {
    const [picker, settings] = await Promise.all([
      loadMcpSettings("/repo", false, { claudeHealth: false }),
      loadMcpSettings("/repo"),
    ]);
    expect(picker.servers[0].status).toBe("Configured");
    expect(settings.servers[0].name).toBe("docs");
    expect(invoke).toHaveBeenCalledTimes(2);
    await loadMcpSettings("/repo");
    expect(invoke).toHaveBeenCalledTimes(2);
    resolveHealth(
      "docs: local - Connected\nremote: https://example.com - Needs authentication",
    );
    await vi.waitFor(() =>
      expect(getCachedMcpSettings("/repo")?.servers).toHaveLength(2),
    );
    expect(onChange.mock.calls.at(-1)?.[0].servers[0].status).toBe("Connected");
  } finally {
    stop();
  }
});

it("loads non-Claude pickers without running Claude and lets a later Claude consumer request health", async () => {
  invoke.mockImplementation(async (command: string) =>
    command === "mcp_discover" ? configured : "docs: local - Connected",
  );
  await loadMcpSettings("/repo", false, { claudeHealth: false });
  await loadMcpSettings("/repo", false, { claudeHealth: false });
  expect(invoke).toHaveBeenCalledTimes(1);
  await loadMcpSettings("/repo");
  await vi.waitFor(() =>
    expect(getCachedMcpSettings("/repo")?.servers[0].status).toBe("Connected"),
  );
  expect(invoke).toHaveBeenCalledTimes(2);
});

it("ignores health from a request superseded by refresh", async () => {
  const health: ((output: string) => void)[] = [];
  invoke.mockImplementation((command: string) =>
    command === "mcp_discover"
      ? Promise.resolve(configured)
      : new Promise((resolve) => {
          health.push(resolve);
        }),
  );
  await loadMcpSettings("/repo");
  await loadMcpSettings("/repo", true);
  health[1]("docs: local - Connected");
  await vi.waitFor(() =>
    expect(getCachedMcpSettings("/repo")?.servers[0].status).toBe("Connected"),
  );
  health[0]("docs: local - Failed\nstale: local - Connected");
  await Promise.resolve();
  expect(
    getCachedMcpSettings("/repo")?.servers.map((server) => server.name),
  ).toEqual(["docs"]);
  expect(getCachedMcpSettings("/repo")?.servers[0].status).toBe("Connected");
});

it("keeps configured rows when health fails and preserves disabled status", async () => {
  invoke.mockImplementation((command: string) =>
    command === "mcp_discover"
      ? Promise.resolve([{ ...configured[0], enabled: false }])
      : Promise.reject(new Error("Health unavailable")),
  );
  await loadMcpSettings("/repo");
  await vi.waitFor(() =>
    expect(getCachedMcpSettings("/repo")?.claudeError).toContain(
      "Health unavailable",
    ),
  );
  expect(getCachedMcpSettings("/repo")?.servers[0].status).toBe("Disabled");
  expect(getCachedMcpSettings("/repo")?.error).toBe("");
});
