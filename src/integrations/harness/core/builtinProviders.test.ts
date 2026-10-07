import { beforeEach, describe, expect, it, vi } from "vitest";
import { HARNESSES, harnessSupportsAttachments } from "../../../features/sessions/model/session";
import { defaultModelId, modelsFor } from "../../../features/sessions/model/models";
import { supportsBtwHarness } from "../../../features/sessions/model/btw";

const native = vi.hoisted(() => ({ invoke: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: native.invoke }));
import { registerBuiltinHarnesses } from "./register";
import { getHarness, listHarnesses } from "./registry";
import { isHarnessAvailable, probeHarnessAvailability } from "./availability";

const providers = [
  "claude", "codex", "cursor", "grok", "opencode",
  "pi", "omp", "fx", "hermes", "antigravity",
] as const;

beforeEach(() => {
  native.invoke.mockReset();
  registerBuiltinHarnesses();
});

describe("bundled agent CLIs", () => {
  it("registers every selectable provider with its live session lifecycle", () => {
    registerBuiltinHarnesses();
    expect(HARNESSES).toEqual(providers);
    expect(listHarnesses()).toHaveLength(providers.length);
    for (const id of providers) {
      const adapter = getHarness(id)!;
      expect(adapter.live).toBe(true);
      expect(adapter.bindSession).toBeTypeOf("function");
      expect(adapter.sendTurn).toBeTypeOf("function");
      expect(adapter.cancelTurn).toBeTypeOf("function");
      expect(adapter.stopSession).toBeTypeOf("function");
      expect(adapter.forgetSession).toBeTypeOf("function");
      expect(adapter.refreshCatalog).toBeTypeOf("function");
      expect(supportsBtwHarness(id)).toBe(adapter.runTextPrompt != null);
      // Codex deliberately requires a live model catalog.
      if (id !== "codex") {
        expect(modelsFor(id).some((model) => model.id === defaultModelId(id))).toBe(true);
      }
    }
    expect(harnessSupportsAttachments("fx")).toBe(false);
    expect(harnessSupportsAttachments("hermes")).toBe(true);
  });

  it("detects new CLIs independently and clears availability after removal", async () => {
    const installed = new Set(["cursor", "pi", "antigravity"]);
    native.invoke.mockImplementation(async (command: string) => {
      const id = command.replace("harness_resolve_", "");
      if (!installed.has(id)) throw new Error("Not installed");
      return { path: `/cli/${id}`, args: [] };
    });
    await probeHarnessAvailability({ force: true });
    for (const id of providers) {
      expect(native.invoke).toHaveBeenCalledWith(`harness_resolve_${id}`);
      expect(isHarnessAvailable(id)).toBe(installed.has(id));
    }
    installed.delete("pi");
    await probeHarnessAvailability({ force: true });
    expect(isHarnessAvailable("pi")).toBe(false);
    expect(isHarnessAvailable("cursor")).toBe(true);
  });
});
