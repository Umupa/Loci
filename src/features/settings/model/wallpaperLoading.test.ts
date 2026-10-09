// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
  convertFileSrc: (path: string) => `asset://${path}`,
}));

let appearance: typeof import("./appearance");
const pending = new Map<string, { resolve: (path: string) => void; reject: (error: Error) => void }>();
const image = () => document.documentElement.style.getPropertyValue("--chat-background-image");
const flush = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };

beforeEach(async () => {
  vi.resetModules();
  localStorage.clear();
  document.documentElement.removeAttribute("style");
  document.documentElement.className = "";
  pending.clear();
  vi.mocked(invoke).mockReset().mockImplementation((command, args) => {
    if (command !== "download_wallpaper") return Promise.resolve(undefined);
    const key = (args as { cacheKey: string }).cacheKey;
    return new Promise((resolve, reject) => pending.set(key, { resolve, reject }));
  });
  appearance = await import("./appearance");
  appearance.saveNewThreadBackgroundEffect("none");
});

afterEach(() => {
  appearance.applyChatBackground(null);
  localStorage.clear();
});

describe("on-demand theme wallpapers", () => {
  it("shows a thumbnail immediately, downloads the pinned public original, then renders the cache", async () => {
    appearance.setTheme("nord");
    expect(invoke).toHaveBeenCalledWith("download_wallpaper", {
      cdnUrl: "https://cdn.jsdelivr.net/gh/omacom/omarchy@b83d3df0840504299d3099ebf391eb8110527edd/themes/nord/backgrounds/0-black-moon.jpg",
      cacheKey: "nord/0-black-moon.jpg",
    });
    expect(image()).toContain("/themes/nord/0-black-moon.thumb.webp");
    pending.get("nord/0-black-moon.jpg")!.resolve("/cache/nord/0-black-moon.jpg");
    await flush();
    expect(image()).toContain("asset:///cache/nord/0-black-moon.jpg");
    appearance.applyChatBackground("theme:nord/0-black-moon");
    expect(vi.mocked(invoke).mock.calls.filter(([cmd]) => cmd === "download_wallpaper")).toHaveLength(1);
  });

  it("keeps the latest theme when downloads finish in reverse order", async () => {
    appearance.setTheme("nord");
    appearance.setTheme("tokyo-night");
    expect(pending.size).toBe(2);
    pending.get("tokyo-night/0-winding-road.webp")!.resolve("/cache/tokyo.webp");
    await flush();
    expect(image()).toContain("asset:///cache/tokyo.webp");
    pending.get("nord/0-black-moon.jpg")!.resolve("/cache/nord.jpg");
    await flush();
    expect(image()).toContain("asset:///cache/tokyo.webp");
    expect(appearance.loadChatBackgroundPath()).toBe("theme:tokyo-night/0-winding-road");
  });

  it.each([null, "/pictures/custom.png"])("does not restore a startup wallpaper after changing it to %s", async (next) => {
    appearance.saveChatBackgroundPath("theme:nord/0-black-moon");
    appearance.initAppearance();
    expect(pending.has("nord/0-black-moon.jpg")).toBe(true);
    appearance.saveChatBackgroundPath(next);
    appearance.applyChatBackground(next);
    pending.get("nord/0-black-moon.jpg")!.resolve("/cache/nord.jpg");
    await flush();
    expect(appearance.loadChatBackgroundPath()).toBe(next);
    if (next) expect(image()).toContain("asset:///pictures/custom.png");
    else {
      expect(image()).toBe("");
      expect(document.documentElement.classList.contains("has-chat-background")).toBe(false);
    }
  });

  it("shares an in-flight download and retries after failure while keeping the thumbnail", async () => {
    const path = "theme:nord/0-black-moon";
    appearance.setTheme("nord");
    appearance.applyChatBackground(path);
    expect(vi.mocked(invoke).mock.calls.filter(([cmd]) => cmd === "download_wallpaper")).toHaveLength(1);
    pending.get("nord/0-black-moon.jpg")!.reject(new Error("offline"));
    await flush();
    expect(image()).toContain("/themes/nord/0-black-moon.thumb.webp");
    appearance.applyChatBackground(path);
    expect(vi.mocked(invoke).mock.calls.filter(([cmd]) => cmd === "download_wallpaper")).toHaveLength(2);
    pending.get("nord/0-black-moon.jpg")!.resolve("/cache/nord.jpg");
    await flush();
    expect(image()).toContain("asset:///cache/nord.jpg");
  });
});
