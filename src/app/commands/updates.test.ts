import { beforeEach, describe, expect, it, vi } from "vitest";
import { check } from "@tauri-apps/plugin-updater";
import { resetUpdatesForTests } from "../../features/updates/model/updates";
import { runCommand } from "./dispatch";
import { testContext } from "./testContext";

const native = vi.hoisted(() => ({
  identifier: "com.loci.desktop",
  current: "0.2.0",
  available: null as null | Record<string, unknown>,
}));

vi.mock("@tauri-apps/api/app", () => ({
  getIdentifier: vi.fn(async () => native.identifier),
  getVersion: vi.fn(async () => native.current),
}));
vi.mock("@tauri-apps/plugin-updater", () => ({ check: vi.fn(async () => native.available) }));

const external = { requestId: "r1", caller: "external" as const };

beforeEach(() => {
  native.identifier = "com.loci.desktop";
  native.current = "0.2.0";
  native.available = null;
  vi.mocked(check).mockClear();
  resetUpdatesForTests();
});

describe("updates.check", () => {
  it("reports the newer release without opening the prompt", async () => {
    native.available = { version: "0.3.0", currentVersion: "0.2.0", body: "## Added", close: async () => undefined };
    const { ctx } = testContext([]);
    await expect(runCommand(ctx, "updates.check", {}, external)).resolves.toEqual({
      available: true,
      version: "0.3.0",
      current: "0.2.0",
    });
  });

  it("reports the running version when there is nothing newer", async () => {
    const { ctx } = testContext([]);
    await expect(runCommand(ctx, "updates.check", {}, external)).resolves.toEqual({
      available: false,
      version: null,
      current: "0.2.0",
    });
  });

  it("asks nothing of a build from source", async () => {
    native.identifier = "com.loci.desktop.dev";
    native.available = { version: "0.3.0", currentVersion: "0.2.0", close: async () => undefined };
    const { ctx } = testContext([]);
    await expect(runCommand(ctx, "updates.check", {}, external)).resolves.toEqual({
      available: false,
      version: null,
      current: "0.2.0",
    });
    expect(check).not.toHaveBeenCalled();
  });

  it("reports a failed check as a command error", async () => {
    vi.mocked(check).mockRejectedValueOnce(new Error("offline"));
    const { ctx } = testContext([]);
    await expect(runCommand(ctx, "updates.check", {}, external)).rejects.toMatchObject({
      code: "failed",
      message: "Could not check for updates: offline",
    });
  });
});
