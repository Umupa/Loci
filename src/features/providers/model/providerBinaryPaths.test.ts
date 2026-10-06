import { afterEach,beforeEach,describe,expect,it,vi } from "vitest";

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(),
}));

vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));

import {
loadProviderBinaryPath,
saveProviderBinaryPath,
} from "./providerBinaryPaths";

const key = "loci.providerBinaryPaths.v1";

beforeEach(() => {
  mocks.invoke.mockReset();
  vi.stubGlobal("localStorage", {
    getItem: vi.fn(() => null),
    setItem: vi.fn(),
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("provider binary paths", () => {
  it("repairs malformed storage when saving a path", () => {
    let stored = "not json";
    vi.mocked(localStorage.getItem).mockImplementation(() => stored);
    vi.mocked(localStorage.setItem).mockImplementation((_key, value) => {
      stored = value;
    });
    expect(saveProviderBinaryPath("codex", "/opt/codex")).toBe(true);
    expect(loadProviderBinaryPath("codex")).toBe("/opt/codex");
  });

  it("filters non-string paths before runtime initialization", async () => {
    const stored = JSON.stringify({ codex: null, codex: "/opt/codex" });
    vi.mocked(localStorage.getItem).mockImplementation(() => stored);
    mocks.invoke.mockResolvedValue({ codex: "/opt/codex" });

    vi.resetModules();
    const providerPaths = await import("./providerBinaryPaths");
    await providerPaths.initializeProviderBinaryPaths();

    expect(mocks.invoke).toHaveBeenCalledWith("harness_runtime_binary_paths", {
      paths: { codex: "/opt/codex" },
    });
    expect(providerPaths.runtimeProviderBinaryPath("claude")).toBeNull();
    expect(providerPaths.runtimeProviderBinaryPath("codex")).toBe("/opt/codex");
  });

  it("keeps the active path unchanged across windows until restart", async () => {
    let stored = JSON.stringify({ codex: "/opt/codex/old" });
    vi.mocked(localStorage.getItem).mockImplementation(() => stored);
    vi.mocked(localStorage.setItem).mockImplementation((_key, value) => {
      stored = value;
    });
    mocks.invoke.mockResolvedValue({ codex: "/opt/codex/old" });

    vi.resetModules();
    const firstWindow = await import("./providerBinaryPaths");
    await firstWindow.initializeProviderBinaryPaths();
    expect(firstWindow.runtimeProviderBinaryPath("codex")).toBe("/opt/codex/old");

    firstWindow.saveProviderBinaryPath("codex", "/opt/codex/new");
    expect(firstWindow.runtimeProviderBinaryPath("codex")).toBe("/opt/codex/old");
    expect(firstWindow.providerBinaryPathChangePending("codex")).toBe(true);

    vi.resetModules();
    const secondWindow = await import("./providerBinaryPaths");
    await secondWindow.initializeProviderBinaryPaths();
    expect(secondWindow.runtimeProviderBinaryPath("codex")).toBe("/opt/codex/old");
    expect(secondWindow.providerBinaryPathChangePending("codex")).toBe(true);

    mocks.invoke.mockResolvedValue({ codex: "/opt/codex/new" });
    vi.resetModules();
    const restartedWindow = await import("./providerBinaryPaths");
    await restartedWindow.initializeProviderBinaryPaths();
    expect(restartedWindow.runtimeProviderBinaryPath("codex")).toBe("/opt/codex/new");
    expect(restartedWindow.providerBinaryPathChangePending("codex")).toBe(false);
  });

  it("reports storage failures without claiming the path was saved", () => {
    vi.mocked(localStorage.setItem).mockImplementation(() => {
      throw new Error("storage full");
    });
    expect(saveProviderBinaryPath("claude", "/opt/claude")).toBe(false);
  });
});
