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

it("goes back and forward through the pages a mentor's reader showed, like a browser", async () => {
  await mount();
  const lesson = { kind: "course" as const, course: { courseId: "tour", agentId: "a", title: "Tour" } };
  const main = { kind: "file" as const, path: "/r/main.go", commit: "abcdef0" };
  const vm = { kind: "file" as const, path: "/r/vm.go", commit: "abcdef0" };
  await act(async () => view.show("a", lesson));
  await act(async () => view.setLesson("a", { id: "l3", title: "Three" }));
  expect(view.historyFor("a")).toEqual({ back: 0, forward: 0 });
  await act(async () => view.show("a", main, { fromLine: 12 }));
  await act(async () => view.show("a", vm, { fromLine: 40 }));
  // A jump inside the same file is a step too.
  await act(async () => view.show("a", vm, { fromLine: 7 }));
  // Opening the page already shown, with no jump, is not.
  await act(async () => view.show("a", vm));
  expect(view.historyFor("a")).toEqual({ back: 3, forward: 0 });

  await act(async () => { view.back("a"); });
  await act(async () => { view.back("a"); });
  expect(view.stateFor("a").page).toEqual(main);
  expect(view.historyFor("a")).toEqual({ back: 1, forward: 2 });
  await act(async () => { view.back("a"); });
  // Back to the lesson it was on, not the course's start.
  expect(view.stateFor("a").page).toEqual({ kind: "course", course: { ...lesson.course, itemId: "l3" } });
  expect(view.stateFor("a").lesson).toEqual({ id: "l3", title: "Three" });
  expect(view.back("a")).toBe(false);
  await act(async () => { view.forward("a"); });
  expect(view.stateFor("a").page).toEqual(main);

  // A new page drops what was ahead; closing can be gone back from.
  await act(async () => view.show("a", { kind: "note", id: "n" }));
  expect(view.historyFor("a")).toEqual({ back: 2, forward: 0 });
  await act(async () => view.close("a"));
  await act(async () => { view.back("a"); });
  expect(view.stateFor("a").page).toEqual({ kind: "note", id: "n" });
  // Other mentors keep their own.
  expect(view.historyFor("b")).toEqual({ back: 0, forward: 0 });
});

it("remembers at most fifty pages back", async () => {
  await mount();
  for (let index = 0; index < 60; index++) await act(async () => view.show("a", { kind: "note", id: `n${index}` }));
  expect(view.historyFor("a").back).toBe(50);
});
