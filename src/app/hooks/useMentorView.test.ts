// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { MENTOR_VIEW_KEY, useMentorView, type MentorView } from "./useMentorView";

let container: HTMLDivElement;
let root: Root;
let view: MentorView;
function Host() { view = useMentorView(); return null; }
async function mount() { root = createRoot(container); await act(async () => root.render(createElement(Host))); }
const stored = () => JSON.parse(localStorage.getItem(MENTOR_VIEW_KEY) ?? "{}");

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  localStorage.clear();
  container = document.createElement("div"); document.body.append(container);
});
afterEach(() => { act(() => root.unmount()); container.remove(); localStorage.clear(); vi.unstubAllGlobals(); });

it("remembers each mentor's library segment and course, but not its filter", async () => {
  await mount();
  await act(async () => view.openLibrary("a", { segment: "notes", filter: "draft" }));
  await act(async () => view.openLibrary("b", { course: "kube" }));
  expect(view.stateFor("a")).toMatchObject({ segment: "notes", filter: { segment: "notes", text: "draft" } });
  expect(view.stateFor("b")).toMatchObject({ course: "kube" });
  expect(view.stateFor("b").segment).toBeUndefined();
  expect(stored().a).toMatchObject({ segment: "notes" });
  expect(stored().a.filter).toBeUndefined();
  act(() => root.unmount());
  await mount();
  expect(view.stateFor("a").segment).toBe("notes");
  expect(view.stateFor("a").filter).toBeUndefined();
  expect(view.stateFor("b").course).toBe("kube");
});

it("follows the course being read and clears an emptied filter", async () => {
  await mount();
  await act(async () => view.show("a", { kind: "course", course: { courseId: "sds", agentId: "a", title: "SDS" } }));
  expect(view.stateFor("a").course).toBe("sds");
  await act(async () => view.show("a", { kind: "note", id: "n" }));
  expect(view.stateFor("a").course).toBe("sds");
  await act(async () => view.openLibrary("a", { segment: "sources", filter: "x" }));
  await act(async () => view.openLibrary("a", { filter: "" }));
  expect(view.stateFor("a").filter).toBeUndefined();
});

it("reads older entries without the new fields, and ignores bad ones", async () => {
  localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify({ a: { library: false }, b: { segment: "canvases", course: "../x" } }));
  await mount();
  expect(view.stateFor("a")).toMatchObject({ library: false });
  expect(view.stateFor("a").segment).toBeUndefined();
  expect(view.stateFor("b").segment).toBeUndefined();
  expect(view.stateFor("b").course).toBeUndefined();
});

it("shows a hidden library when asked to", async () => {
  await mount();
  await act(async () => view.toggleLibrary("a"));
  expect(view.stateFor("a").library).toBe(false);
  await act(async () => view.openLibrary("a", { segment: "files", show: true }));
  expect(view.stateFor("a")).toMatchObject({ library: true, segment: "files" });
});
