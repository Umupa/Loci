import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  checkForUpdate,
  dismissUpdatePrompt,
  installPendingUpdate,
  openUpdatePrompt,
  releaseNotesUrl,
  resetUpdatesForTests,
  RELEASE_IDENTIFIER,
  updateDetails,
  updatesItself,
  updatesSnapshot,
  type InstallProgress,
} from "./updates";

const native = vi.hoisted(() => ({
  identifier: "com.loci.desktop",
  current: "0.2.0",
  available: null as null | Record<string, unknown>,
}));
const relaunch = vi.hoisted(() => vi.fn(async () => undefined));

vi.mock("@tauri-apps/api/app", () => ({
  getIdentifier: vi.fn(async () => native.identifier),
  getVersion: vi.fn(async () => native.current),
}));
vi.mock("@tauri-apps/plugin-updater", () => ({ check: vi.fn(async () => native.available) }));
vi.mock("@tauri-apps/plugin-process", () => ({ relaunch }));

type Event = { event: "Started"; data: { contentLength?: number } } | { event: "Progress"; data: { chunkLength: number } } | { event: "Finished" };

function fakeUpdate(overrides: Record<string, unknown> = {}) {
  return {
    version: "0.3.0",
    currentVersion: "0.2.0",
    body: "## Added\n\n- A thing.\n",
    close: vi.fn(async () => undefined),
    downloadAndInstall: vi.fn(async (onEvent: (event: Event) => void) => {
      onEvent({ event: "Started", data: { contentLength: 100 } });
      onEvent({ event: "Progress", data: { chunkLength: 40 } });
      onEvent({ event: "Progress", data: { chunkLength: 60 } });
      onEvent({ event: "Finished" });
    }),
    ...overrides,
  };
}

beforeEach(() => {
  resetUpdatesForTests();
  native.identifier = RELEASE_IDENTIFIER;
  native.current = "0.2.0";
  native.available = null;
  relaunch.mockClear();
});

describe("updates", () => {
  it("only the installed app updates itself", () => {
    expect(updatesItself(RELEASE_IDENTIFIER)).toBe(true);
    expect(updatesItself("com.loci.desktop.dev")).toBe(false);
    expect(updatesItself("com.loci.desktop.feeds")).toBe(false);
  });

  it("takes the release notes as Markdown without their outer whitespace", () => {
    expect(updateDetails({ version: "0.2.0", currentVersion: "0.1.0", body: "### Fixed\n\n- A thing.\n" })).toEqual({
      version: "0.2.0",
      currentVersion: "0.1.0",
      notes: "### Fixed\n\n- A thing.",
    });
    expect(updateDetails({ version: "0.2.0", currentVersion: "0.1.0", body: "  " })).toMatchObject({ notes: "" });
  });

  it("links to the release's tag on GitHub", () => {
    expect(releaseNotesUrl("0.3.0")).toBe("https://github.com/Umupa/Loci/releases/tag/v0.3.0");
    expect(releaseNotesUrl("v0.3.0")).toBe("https://github.com/Umupa/Loci/releases/tag/v0.3.0");
  });

  it("leaves a quiet check's release to the rail badge", async () => {
    native.available = fakeUpdate();
    await expect(checkForUpdate({ interactive: false })).resolves.toEqual({ outcome: "available" });
    expect(updatesSnapshot()).toMatchObject({
      pending: { version: "0.3.0", currentVersion: "0.2.0", notes: "## Added\n\n- A thing." },
      promptOpen: false,
      progress: { phase: "idle" },
    });
  });

  it("opens the prompt for an interactive check", async () => {
    native.available = fakeUpdate();
    await expect(checkForUpdate({ interactive: true })).resolves.toEqual({ outcome: "available" });
    expect(updatesSnapshot().promptOpen).toBe(true);
    expect(updatesSnapshot().pending?.version).toBe("0.3.0");
  });

  it("opens the prompt from the badge", async () => {
    native.available = fakeUpdate();
    await checkForUpdate({ interactive: false });
    openUpdatePrompt();
    expect(updatesSnapshot().promptOpen).toBe(true);
  });

  it("does not let a quiet check re-prompt a version dismissed with Later", async () => {
    const update = fakeUpdate();
    native.available = update;
    await checkForUpdate({ interactive: false });
    dismissUpdatePrompt();
    expect(update.close).toHaveBeenCalled();
    expect(updatesSnapshot()).toEqual({ pending: null, promptOpen: false, progress: { phase: "idle" } });

    await expect(checkForUpdate({ interactive: false })).resolves.toEqual({ outcome: "declined" });
    expect(updatesSnapshot().pending).toBeNull();

    await expect(checkForUpdate({ interactive: true })).resolves.toEqual({ outcome: "available" });
    expect(updatesSnapshot().promptOpen).toBe(true);
  });

  it("keeps quiet checks off a build from source", async () => {
    native.identifier = "com.loci.desktop.dev";
    native.available = fakeUpdate();
    await expect(checkForUpdate({ interactive: false })).resolves.toEqual({ outcome: "disabled" });
    expect(updatesSnapshot().pending).toBeNull();
  });

  it("reports a check failure only when asked", async () => {
    const { check } = await import("@tauri-apps/plugin-updater");
    vi.mocked(check).mockRejectedValueOnce(new Error("offline"));
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    await expect(checkForUpdate({ interactive: false })).resolves.toEqual({ outcome: "failed", error: "offline" });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();

    vi.mocked(check).mockRejectedValueOnce(new Error("offline"));
    await expect(checkForUpdate({ interactive: true })).resolves.toEqual({ outcome: "failed", error: "offline" });
  });

  it("shows the download's share, then that it is installing", async () => {
    let emit: (event: Event) => void = () => undefined;
    let finish: () => void = () => undefined;
    const update = fakeUpdate({
      downloadAndInstall: vi.fn((onEvent: (event: Event) => void) => new Promise<void>((resolve) => {
        emit = onEvent;
        finish = resolve;
      })),
    });
    native.available = update;
    await checkForUpdate({ interactive: true });

    const installing = installPendingUpdate();
    expect(updatesSnapshot().progress).toEqual({ phase: "downloading", percent: null });
    emit({ event: "Started", data: { contentLength: 200 } });
    expect(updatesSnapshot().progress).toEqual({ phase: "downloading", percent: 0 });
    emit({ event: "Progress", data: { chunkLength: 50 } });
    expect(updatesSnapshot().progress).toEqual({ phase: "downloading", percent: 25 });
    emit({ event: "Finished" });
    expect(updatesSnapshot().progress).toEqual({ phase: "installing" });

    finish();
    await installing;
    expect(relaunch).toHaveBeenCalledTimes(1);
    expect(updatesSnapshot().progress).toEqual({ phase: "installing" });
  });

  it("leaves a failed install on screen for Retry", async () => {
    const update = fakeUpdate({ downloadAndInstall: vi.fn(async () => { throw new Error("network down"); }) });
    native.available = update;
    await checkForUpdate({ interactive: true });
    await installPendingUpdate();
    expect(updatesSnapshot().progress).toEqual({ phase: "failed", error: "network down" } satisfies InstallProgress);

    const working = fakeUpdate();
    native.available = working;
    update.downloadAndInstall = working.downloadAndInstall;
    await installPendingUpdate();
    expect(relaunch).toHaveBeenCalledTimes(1);
    expect(updatesSnapshot().progress).toEqual({ phase: "installing" });
  });

  it("keeps the prompt open while the release is installing", async () => {
    let finish: () => void = () => undefined;
    const update = fakeUpdate({
      downloadAndInstall: vi.fn(() => new Promise<void>((resolve) => { finish = resolve; })),
    });
    native.available = update;
    await checkForUpdate({ interactive: true });
    const installing = installPendingUpdate();
    dismissUpdatePrompt();
    expect(updatesSnapshot().promptOpen).toBe(true);
    finish();
    await installing;
  });
});
