import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const cli = vi.hoisted(() => ({
  output: "",
  fails: false,
}));

vi.mock("../../core/child", () => ({
  resolveGrokBinary: async () => ({ path: "/fake/grok" }),
  execChild: async () => {
    if (cli.fails) throw new Error("grok models failed");
    return cli.output;
  },
  spawnChild: async () => {
    throw new Error("ACP probe unavailable in this test");
  },
  killChild: async () => undefined,
  unwatchChild: () => undefined,
  watchChild: () => undefined,
}));

vi.mock("../../../../platform/tauri/fs", () => ({
  homeDir: async () => "/repo",
}));

import {
  defaultModelId,
  modelsFor,
  resetHarnessModelOverlays,
} from "../../../../features/sessions/model/models";
import { discoverGrokModels, refreshGrokCatalog } from "./grokCatalog";
import grokModelsOutput from "./fixtures/grok-models.txt?raw";

describe("grok catalog", () => {
  beforeEach(() => {
    cli.output = grokModelsOutput;
    cli.fails = false;
    vi.spyOn(console, "debug").mockImplementation(() => undefined);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    resetHarnessModelOverlays();
  });

  it("installs the CLI default in the model catalog", async () => {
    await refreshGrokCatalog();

    expect(defaultModelId("grok")).toBe(
      "grok:magpie/sub2api/deepseek-flash",
    );
    expect(modelsFor("grok")).toHaveLength(22);
  });

  it("takes the default model the CLI reports", async () => {
    const catalog = await discoverGrokModels("/repo");

    expect(catalog.defaultModelId).toBe("magpie/sub2api/deepseek-flash");
    expect(catalog.models.map((model) => model.nativeId)).toEqual([
      "grok-4.6",
      "grok-4.5",
      "deepseek-flash",
      "gpt-6.1-sol",
      "gpt-6-astra",
      "gpt-6-sol",
      "gpt-6-luna",
      "gpt-5.6-sol",
      "gpt-5.6-terra",
      "gpt-5.6-luna",
      "magpie/sub2api/deepseek-flash",
      "magpie/deepseek/deepseek-v4-flash",
      "magpie/gemini/gemini-3.1-pro-preview",
      "magpie/gemini/gemini-3-pro-preview",
      "magpie/gemini/gemini-3-flash-preview",
      "magpie/gemini/gemini-3.8-flash",
      "magpie/gemini/gemini-3.5-flash",
      "magpie/gemini/gemini-3.5-flash-lite",
      "magpie/gemini/gemini-3.1-flash-lite",
      "magpie/gemini/gemini-2.5-pro",
      "magpie/gemini/gemini-2.5-flash",
      "magpie/gemini/gemini-2.5-flash-lite",
    ]);
  });

  it("falls back to the bundled catalog when the CLI fails", async () => {
    cli.fails = true;
    const catalog = await discoverGrokModels("/repo");

    expect(catalog.defaultModelId).toBeUndefined();
    expect(catalog.models.map((model) => model.nativeId)).toEqual([
      "grok-4.6",
      "grok-4.5",
    ]);
  });
});
