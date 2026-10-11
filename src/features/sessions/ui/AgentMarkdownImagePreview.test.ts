// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { AgentMarkdown } from "./AgentMarkdown";

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(), isTauri: () => false, convertFileSrc: (path: string) => `asset://${path}` }));
vi.mock("@tauri-apps/plugin-opener", () => ({ openUrl: vi.fn(async () => undefined) }));
const highlighter = vi.hoisted(() => ({ highlight: () => null, getThemes: () => ["github-light", "github-dark"], supportsLanguage: () => false }));
vi.mock("../../../shared/hooks/useCodePlugin", () => ({ useCodePlugin: () => highlighter }));
vi.mock("../../../shared/hooks/useColorScheme", () => ({ useColorScheme: () => "light" }));

const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
const data = "data:image/png;base64,iVBORw0KGgoBAgM=";
let container: HTMLDivElement, root: Root;
const image = () => container.querySelector<HTMLImageElement>("img")!;
const dialog = () => document.querySelector<HTMLElement>('[role="dialog"][aria-label^="Image preview:"]');
const show = (text: string, options: { sourceUrl?: string; cwd?: string } = {}) => act(async () => root.render(createElement(AgentMarkdown, { text, wholeDocument: true, ...options })));
const load = (target = image()) => {
  Object.defineProperties(target, { complete: { configurable: true, value: true }, naturalWidth: { configurable: true, value: 500 }, naturalHeight: { configurable: true, value: 300 } });
  act(() => target.dispatchEvent(new Event("load")));
};
const close = () => act(() => document.querySelector<HTMLButtonElement>('button[aria-label="Close image preview"]')!.click());

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.mocked(invoke).mockReset().mockImplementation(async (command) => {
    if (command === "read_binary_file") return png.buffer.slice(0) as never;
    if (command === "notes_image_path") return "/resolved/note.png" as never;
    throw new Error(`Unexpected invoke: ${command}`);
  });
  container = document.createElement("div"); document.body.append(container); root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount()); container.remove(); vi.clearAllMocks(); vi.unstubAllGlobals();
});

it("opens only a decoded image in the shared portal and disables a failed image", async () => {
  await show("Before ![Architecture](assets/figure.png) after.", { cwd: "/reading" });
  act(() => image().click());
  expect(dialog()).toBeNull();
  expect(image().getAttribute("role")).toBeNull();
  load();
  expect(image().getAttribute("aria-label")).toBe("Preview image: Architecture");
  expect(image().getAttribute("role")).toBe("button");
  expect(image().tabIndex).toBe(0);
  act(() => { image().focus(); image().click(); });
  expect(dialog()?.querySelector("img")?.getAttribute("src")).toBe(data);
  expect(container.querySelector('[role="dialog"]')).toBeNull();
  expect(container.querySelector("p")?.contains(image())).toBe(true);
  close();
  expect(document.activeElement).toBe(image());
  act(() => image().dispatchEvent(new Event("error")));
  act(() => image().click());
  expect(dialog()).toBeNull();
  expect(image().getAttribute("role")).toBeNull();
});

it.each(["Enter", " "])("opens a loaded image with the %j key", async (key) => {
  await show("![Diagram](assets/figure.png)", { cwd: "/reading" }); load();
  const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true });
  act(() => { image().focus(); image().dispatchEvent(event); });
  expect(event.defaultPrevented).toBe(true);
  expect(dialog()?.querySelector("img")?.getAttribute("src")).toBe(data);
  close();
});

it("preserves linked image navigation instead of opening a competing preview", async () => {
  await show("[![Diagram](https://example.com/figure.png)](https://example.com/details)", { sourceUrl: "https://example.com/article" });
  load();
  expect(image().getAttribute("role")).toBeNull();
  expect(image().getAttribute("tabindex")).toBeNull();
  act(() => image().click());
  expect(openUrl).toHaveBeenCalledWith("https://example.com/details");
  expect(dialog()).toBeNull();
});

it.each([
  { name: "HTTPS source", text: "![Figure](/figure.png)", options: { sourceUrl: "https://example.com/article" }, expected: "https://example.com/figure.png" },
  { name: "local file", text: "![Figure](assets/figure.png)", options: { cwd: "/reading" }, expected: data },
  { name: "note asset", text: "![Figure](/note-assets/preview-note/figure.png)", options: {}, expected: "asset:///resolved/note.png" },
])("previews a successfully loaded $name using its resolved source", async ({ text, options, expected }) => {
  await show(text, options);
  expect(image().getAttribute("src")).toBe(expected);
  act(() => image().click());
  expect(dialog()).toBeNull();
  load();
  act(() => image().click());
  expect(dialog()?.querySelector("img")?.getAttribute("src")).toBe(expected);
  if (options.sourceUrl) expect(image().getAttribute("referrerpolicy")).toBe("no-referrer");
  close();
});

it("closes an old preview and waits for the replacement source to load", async () => {
  const original = "https://example.com/original.png";
  await show(`![Diagram](${original})`, { sourceUrl: "https://example.com/article" }); load();
  act(() => image().click());
  expect(dialog()).not.toBeNull();
  Object.defineProperties(image(), { complete: { configurable: true, value: false }, naturalWidth: { configurable: true, value: 0 } });
  const replacement = "https://example.com/replacement.png";
  await show(`![Diagram](${replacement})`, { sourceUrl: "https://example.com/article" });
  expect(dialog()).toBeNull();
  act(() => image().click());
  expect(dialog()).toBeNull();
  load();
  act(() => image().click());
  expect(dialog()?.querySelector("img")?.getAttribute("src")).toBe(replacement);
});
