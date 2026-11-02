// @vitest-environment happy-dom
import { afterEach, beforeEach, expect, it, vi } from "vitest";

const invoke = vi.fn();
vi.mock("@tauri-apps/api/core", () => ({ invoke: (...args: unknown[]) => invoke(...args) }));

import { requestFilePlace } from "../../files/model/filePlace";
import { requestDocumentPlace } from "../../agents/model/documentPlace";
import {
  POSITIONS_KEY, POSITIONS_MAX, POSITIONS_WRITE_MS, flushPositions, loadPositions, placeRequested, positionKey,
  recalledPosition, rememberPosition, resetPositionsForTests,
} from "./readingPositions";

const tauri = window as unknown as Record<string, unknown>;
beforeEach(() => { invoke.mockReset(); resetPositionsForTests(); });
afterEach(() => { delete tauri.__TAURI_INTERNALS__; vi.useRealTimers(); });

it("names each page that has a position, a course by its lesson", () => {
  const course = { kind: "course" as const, course: { courseId: "k8s", agentId: "a", title: "K8s" } };
  expect(positionKey(course)).toBeUndefined();
  expect(positionKey(course, { id: "pods", title: "Pods" })).toBe("course:k8s:pods");
  expect(positionKey({ ...course, course: { ...course.course, itemId: "svc" } })).toBe("course:k8s:svc");
  expect(positionKey({ kind: "file", path: "/r/a.go", commit: "abcdef0" })).toBe("file:/r/a.go@abcdef0");
  expect(positionKey({ kind: "document", document: { id: "d1", title: "D", body: "" } })).toBe("document:d1");
  expect(positionKey({ kind: "note", id: "n1" })).toBe("note:n1");
  expect(positionKey({ kind: "session", id: "s" })).toBeUndefined();
  expect(positionKey({ kind: "canvas", id: "c" })).toBeUndefined();
});

it("keeps each mentor's positions apart", () => {
  rememberPosition("a", "file:/x.pdf", { page: 5, within: 0.25, ratio: 0.4 });
  rememberPosition("b", "file:/x.pdf", { page: 1, within: 0, ratio: 0 });
  expect(recalledPosition("a", "file:/x.pdf")).toEqual({ page: 5, within: 0.25, ratio: 0.4 });
  expect(recalledPosition("b", "file:/x.pdf")).toEqual({ page: 1, within: 0, ratio: 0 });
  expect(recalledPosition("a", "file:/y.pdf")).toBeUndefined();
});

it("forgets the least recently read page past the limit", () => {
  for (let index = 0; index < POSITIONS_MAX; index++) rememberPosition("a", `note:${index}`, { ratio: 0.5 }, 1000 + index);
  // Reading the oldest again makes it recent; the next oldest goes instead.
  rememberPosition("a", "note:0", { ratio: 0.6 }, 5000);
  rememberPosition("a", "note:new", { ratio: 0.1 }, 5001);
  expect(recalledPosition("a", "note:0")).toEqual({ ratio: 0.6 });
  expect(recalledPosition("a", "note:1")).toBeUndefined();
  expect(recalledPosition("a", "note:new")).toEqual({ ratio: 0.1 });
  expect(recalledPosition("a", `note:${POSITIONS_MAX - 1}`)).toBeDefined();
});

it("writes to mentor_state at most once per interval, after loading what was kept", async () => {
  vi.useFakeTimers();
  tauri.__TAURI_INTERNALS__ = {};
  invoke.mockImplementation(async (command: string) => command === "mentor_state_all"
    ? { a: { "note:old": { ratio: 0.3, at: 1 }, "note:n": { ratio: 0.9, at: 1 }, "note:bad": { ratio: 7 } } }
    : undefined);
  rememberPosition("a", "note:n", { ratio: 0.1 }, 10);
  rememberPosition("a", "note:n", { ratio: 0.2 }, 20);
  rememberPosition("a", "note:n", { ratio: 0.25 }, 30);
  expect(invoke).not.toHaveBeenCalledWith("mentor_state_set", expect.anything());
  await vi.advanceTimersByTimeAsync(POSITIONS_WRITE_MS);
  const writes = invoke.mock.calls.filter(([command]) => command === "mentor_state_set");
  expect(writes).toHaveLength(1);
  expect(writes[0][1]).toEqual({ writes: [{ agent: "a", key: POSITIONS_KEY, value: {
    // This window's newer place wins over the kept one; the rest of what was kept stays.
    "note:n": { ratio: 0.25, at: 30 },
    "note:old": { ratio: 0.3, at: 1 },
  } }] });
  expect(recalledPosition("a", "note:old")).toEqual({ ratio: 0.3 });
});

it("reads positions kept by an earlier run", async () => {
  tauri.__TAURI_INTERNALS__ = {};
  invoke.mockResolvedValueOnce({ a: { "file:/x.go": { line: 120, ratio: 0.5, at: 3 } }, b: "garbage" });
  await loadPositions();
  expect(invoke).toHaveBeenCalledWith("mentor_state_all", { key: POSITIONS_KEY });
  expect(recalledPosition("a", "file:/x.go")).toEqual({ line: 120, ratio: 0.5 });
  await flushPositions();
  expect(invoke).toHaveBeenCalledTimes(1);
});

it("lets a requested place win over the remembered one", () => {
  const now = Date.now();
  const file = { kind: "file" as const, path: "/r/paper.pdf" };
  expect(placeRequested("a", file, now - 2000)).toBe(false);
  requestFilePlace(file.path, { page: 7 });
  expect(placeRequested("a", file, now - 2000)).toBe(true);
  // Waiting for the pane to show it, it wins however long the opening took.
  expect(placeRequested("a", file, Date.now() + 10_000)).toBe(true);
  const document = { kind: "document" as const, document: { id: "d9", title: "D", body: "" } };
  expect(placeRequested("a", document, now - 2000)).toBe(false);
  requestDocumentPlace("a", "d9", { section: "Pods" });
  expect(placeRequested("a", document, now - 2000)).toBe(true);
  expect(placeRequested("b", document, now - 2000)).toBe(false);
  expect(placeRequested("a", { kind: "note", id: "n" }, 0)).toBe(false);
});
