// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { requestOpenAppResource } from "../../shared/lib/appResourceLinks";
import { useAppResourceNavigation } from "./useAppResourceNavigation";

const mocks = vi.hoisted(() => ({ getCanvas: vi.fn(), checkpointCanvasId: vi.fn(), getLearningSource: vi.fn(), getReadingDocument: vi.fn(), getNote: vi.fn() }));
vi.mock("../../features/canvas/canvas", () => ({
  getCanvas: mocks.getCanvas, checkpointCanvasId: mocks.checkpointCanvasId, CANVAS_OPEN_CHECKPOINT_EVENT: "loci-canvas-open-checkpoint",
}));
vi.mock("../../features/learning/model/learningStore", () => ({ getLearningSource: mocks.getLearningSource, getReadingDocument: mocks.getReadingDocument }));
vi.mock("../../features/notes", () => ({ getNote: mocks.getNote }));
vi.mock("../../features/agents/model/agent", () => ({
  findAgent: (id: string) => id === "agent-a" ? { id } : undefined,
  canvasScopeAgentId: (cwd: string) => cwd.startsWith("loci-agent://") ? cwd.slice("loci-agent://".length) : undefined,
}));
let root: Root;
let container: HTMLDivElement;
const view = {
  openSession: vi.fn(async () => undefined), openFile: vi.fn(), fileBase: vi.fn<() => string | undefined>(),
  openCanvas: vi.fn(async () => undefined), openNote: vi.fn(async () => undefined), onError: vi.fn(),
  mentorBase: vi.fn<() => string | undefined>(), openDocument: vi.fn(async (..._args: unknown[]) => true),
};
function Harness() {
  useAppResourceNavigation(view);
  return null;
}
beforeEach(async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  for (const mock of [...Object.values(mocks), ...Object.values(view)]) mock.mockReset();
  view.fileBase.mockReturnValue("/project");
  view.mentorBase.mockReturnValue("agent-a");
  view.openDocument.mockResolvedValue(true);
  mocks.getCanvas.mockImplementation(async (id) => ({ id, cwd: "/project" }));
  mocks.checkpointCanvasId.mockResolvedValue("drawing");
  mocks.getNote.mockImplementation(async (id) => ({ id, agentId: id === "owned" ? "agent-a" : id === "orphan-of-removed" ? "gone" : undefined }));
  container = document.createElement("div"); document.body.append(container);
  root = createRoot(container);
  await act(async () => root.render(createElement(Harness)));
});
afterEach(async () => { await act(async () => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("opens a drawing in the open mentor's reader, or in the reader of the mentor that keeps it", async () => {
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(view.openCanvas).toHaveBeenLastCalledWith(expect.objectContaining({ id: "drawing" }), undefined);
  mocks.getCanvas.mockResolvedValue({ id: "drawing", cwd: "loci-agent://agent-a" });
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(view.openCanvas).toHaveBeenLastCalledWith(expect.objectContaining({ id: "drawing" }), "agent-a");
});
it("resolves old checkpoint buttons through the same navigation", async () => {
  await act(async () => window.dispatchEvent(new CustomEvent("loci-canvas-open-checkpoint", { detail: "old-checkpoint" })));
  expect(mocks.checkpointCanvasId).toHaveBeenCalledWith("old-checkpoint");
  expect(view.openCanvas).toHaveBeenCalledWith(expect.objectContaining({ id: "drawing" }), undefined);
});
it("reports a deleted drawing instead of opening an empty reader", async () => {
  mocks.getCanvas.mockResolvedValue(null);
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "deleted" }));
  expect(view.onError).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining("no longer exists") }));
  expect(view.openCanvas).not.toHaveBeenCalled();
});
it("opens a note in its owner's reader, and a note without a living owner in the open mentor's", async () => {
  await act(async () => requestOpenAppResource({ kind: "note", id: "owned" }));
  expect(view.openNote).toHaveBeenLastCalledWith("owned", "agent-a");
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  expect(view.openNote).toHaveBeenLastCalledWith("plan", undefined);
  await act(async () => requestOpenAppResource({ kind: "note", id: "orphan-of-removed" }));
  expect(view.openNote).toHaveBeenLastCalledWith("orphan-of-removed", undefined);
  mocks.getNote.mockResolvedValue(null);
  await act(async () => requestOpenAppResource({ kind: "note", id: "deleted" }));
  expect(view.onError).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining("no longer exists") }));
});
it("opens a linked conversation through the session route", async () => {
  await act(async () => requestOpenAppResource({ kind: "session", id: "delegated" }));
  expect(view.openSession).toHaveBeenCalledWith("delegated");
});
it("resolves a relative file link against the folder of the conversation on screen", async () => {
  const link = (path: string) => requestOpenAppResource({ kind: "file", id: btoa(path).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "") });
  await act(async () => link("src/main.rs"));
  expect(view.openFile).toHaveBeenCalledWith("/project/src/main.rs");
  view.fileBase.mockReturnValue("~");
  await act(async () => link("src/main.rs"));
  expect(view.openFile).toHaveBeenCalledOnce();
  expect(view.onError).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining("not open here") }));
});
it("does not let an older pending canvas read override a newer note click", async () => {
  let finish!: (canvas: object) => void;
  mocks.getCanvas.mockReturnValue(new Promise((resolve) => { finish = resolve; }));
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "slow" }));
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  await act(async () => finish({ id: "slow", cwd: "/project" }));
  expect(view.openNote).toHaveBeenCalledWith("plan", undefined);
  expect(view.openCanvas).not.toHaveBeenCalled();
});

it.each(["source", "document"])("ignores a pending PDF %s read after a newer note click", async (stage) => {
  let finish!: (value: object) => void;
  const source = { id: "pdf-source", kind: "pdf", title: "PDF source", quote: "Passage", documentId: "book", path: "/book.pdf", anchors: [{ page: 3, rects: [] }] };
  mocks.getLearningSource.mockResolvedValue(source);
  mocks.getReadingDocument.mockResolvedValue({ id: "book", path: "/relocated-book.pdf" });
  (stage === "source" ? mocks.getLearningSource : mocks.getReadingDocument).mockReturnValue(new Promise((resolve) => { finish = resolve; }));
  await act(async () => requestOpenAppResource({ kind: "source", id: source.id }));
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  await act(async () => finish(stage === "source" ? source : { id: "book", path: "/relocated-book.pdf" }));
  expect(view.openNote).toHaveBeenCalledWith("plan", undefined);
  expect(view.openFile).not.toHaveBeenCalled();
  expect(view.onError).not.toHaveBeenCalled();
});

it("opens a current PDF source at its registered location", async () => {
  mocks.getLearningSource.mockResolvedValue({ id: "pdf-source", kind: "pdf", title: "PDF source", quote: "Passage", documentId: "book", path: "/book.pdf", anchors: [{ page: 3, rects: [] }] });
  mocks.getReadingDocument.mockResolvedValue({ id: "book", path: "/relocated-book.pdf" });
  await act(async () => requestOpenAppResource({ kind: "source", id: "pdf-source" }));
  expect(view.openFile).toHaveBeenCalledWith("/relocated-book.pdf");
  expect(view.openNote).not.toHaveBeenCalled();
});

it("opens a source link to a library document of the mentor on screen, at the section and passage it names", async () => {
  mocks.getLearningSource.mockResolvedValue(null);
  await act(async () => requestOpenAppResource({ kind: "source", id: "k8s-pods", place: { section: "Pod phase", quote: "The phase of a Pod" } }));
  expect(view.openDocument).toHaveBeenCalledWith("agent-a", "k8s-pods", { section: "Pod phase", quote: "The phase of a Pod" });
  view.openDocument.mockResolvedValue(false);
  await act(async () => requestOpenAppResource({ kind: "source", id: "missing" }));
  expect(view.onError).toHaveBeenCalledWith(expect.objectContaining({ message: expect.stringContaining("no longer available") }));
});
it("carries a PDF source link's page and quote through to the document", async () => {
  mocks.getLearningSource.mockResolvedValue(null);
  await act(async () => requestOpenAppResource({ kind: "source", id: "firecracker", place: { page: 7, quote: "Sandbox page one" } }));
  expect(view.openDocument).toHaveBeenCalledWith("agent-a", "firecracker", { page: 7, quote: "Sandbox page one" });
});

it("opens a registered document passage at its highlight, and a file passage at its lines with its words", async () => {
  mocks.getLearningSource.mockResolvedValueOnce({ id: "s", kind: "document", agentId: "agent-a", documentId: "pods", title: "Pods", quote: "Pending",
    section: "Pod phase", anchor: { exact: "Pending", prefix: "", suffix: "", start: 0, end: 7 }, annotationId: "mark" });
  await act(async () => requestOpenAppResource({ kind: "source", id: "s" }));
  expect(view.openDocument).toHaveBeenCalledWith("agent-a", "pods", { section: "Pod phase", quote: "Pending", annotationId: "mark" });
  const place = vi.fn();
  window.addEventListener("loci:open-file", place);
  mocks.getLearningSource.mockResolvedValueOnce({ id: "f", kind: "file", path: "/src/main.rs", title: "main.rs", quote: "run()", lines: [2, 2] });
  await act(async () => requestOpenAppResource({ kind: "source", id: "f" }));
  expect(view.openFile).toHaveBeenCalledWith("/src/main.rs");
  window.removeEventListener("loci:open-file", place);
});
