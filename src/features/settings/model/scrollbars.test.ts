// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";

const platform = vi.hoisted(() => ({ mac: true }));
vi.mock("../../../platform/tauri/platform", async (importOriginal) => ({
  ...await importOriginal<typeof import("../../../platform/tauri/platform")>(),
  get IS_MAC() { return platform.mac; },
}));
const { applyScrollbarStyle } = await import("./appearance");

/** Scroll bars `width` wide, as the system would lay them out. */
function systemBars(width: number) {
  vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockReturnValue(100);
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockReturnValue(100 - width);
}
const thin = () => document.documentElement.classList.contains("has-legacy-scrollbars");

afterEach(() => { vi.restoreAllMocks(); platform.mac = true; document.documentElement.className = ""; });

it("draws thin bars on macOS only where the system's take room, and follows a change back", () => {
  systemBars(15);
  applyScrollbarStyle();
  expect(thin()).toBe(true);
  systemBars(0);
  applyScrollbarStyle();
  expect(thin()).toBe(false);
  expect(document.querySelector("body > div")).toBeNull();
});

it("leaves other systems to their own thin bars", () => {
  platform.mac = false;
  systemBars(15);
  applyScrollbarStyle();
  expect(thin()).toBe(false);
});
