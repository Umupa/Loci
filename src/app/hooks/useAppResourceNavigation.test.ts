// @vitest-environment happy-dom
import { act, createElement } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { requestOpenAppResource } from "../../shared/lib/appResourceLinks";
import { useAppResourceNavigation } from "./useAppResourceNavigation";

const mocks = vi.hoisted(() => ({ getCanvas: vi.fn(), checkpointCanvasId: vi.fn(), getLearningSource: vi.fn(), getReadingDocument: vi.fn() }));
vi.mock("../../features/canvas/canvas", () => ({
  ...mocks, CANVAS_OPEN_CHECKPOINT_EVENT: "loci-canvas-open-checkpoint",
}));
vi.mock("../../features/learning/model/learningStore", () => ({ getLearningSource: mocks.getLearningSource, getReadingDocument: mocks.getReadingDocument }));
let root: Root;
let container: HTMLDivElement;
const workspace = {
  projectCwdRef: { current: "/project" },
  isCanvasOpen: vi.fn(), openCanvas: vi.fn(), showCanvas: vi.fn(), setError: vi.fn(),
  openSession: vi.fn(), openFile: vi.fn(),
};
const openNote = vi.fn();
function Harness({ notesEnabled = true }: { notesEnabled?: boolean }) {
  useAppResourceNavigation({ workspace, notesEnabled, onOpenNote: openNote });
  return null;
}
beforeEach(async () => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  for (const mock of [...Object.values(mocks), workspace.isCanvasOpen, workspace.openCanvas, workspace.showCanvas, workspace.setError, workspace.openSession, workspace.openFile, openNote]) mock.mockReset();
  workspace.isCanvasOpen.mockReturnValue(false);
  mocks.getCanvas.mockImplementation(async (id) => ({ id, cwd: "/project" }));
  mocks.checkpointCanvasId.mockResolvedValue("drawing");
  container = document.createElement("div"); document.body.append(container);
  root = createRoot(container);
  await act(async () => root.render(createElement(Harness)));
});
afterEach(async () => { await act(async () => root.unmount()); container.remove(); vi.unstubAllGlobals(); });

it("opens a same-project drawing in the current pane and focuses it", async () => {
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(workspace.showCanvas).toHaveBeenCalledWith("drawing");
  expect(workspace.openCanvas).not.toHaveBeenCalled();
});
it("opens an agent library drawing beside the current conversation", async () => {
  mocks.getCanvas.mockResolvedValue({ id: "drawing", cwd: "loci-agent://agent-a" });
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(workspace.showCanvas).toHaveBeenCalledWith("drawing");
  expect(workspace.openCanvas).not.toHaveBeenCalled();
});
it("focuses an existing drawing tab instead of duplicating it", async () => {
  workspace.isCanvasOpen.mockReturnValue(true);
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(workspace.openCanvas).toHaveBeenCalledWith("drawing", "/project");
  expect(workspace.showCanvas).not.toHaveBeenCalled();
});
it("opens a cross-project drawing in its own project tab", async () => {
  mocks.getCanvas.mockResolvedValue({ id: "drawing", cwd: "/other" });
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "drawing" }));
  expect(workspace.openCanvas).toHaveBeenCalledWith("drawing", "/other");
});
it("resolves old checkpoint buttons through the same navigation", async () => {
  await act(async () => window.dispatchEvent(new CustomEvent("loci-canvas-open-checkpoint", { detail: "old-checkpoint" })));
  expect(mocks.checkpointCanvasId).toHaveBeenCalledWith("old-checkpoint");
  expect(workspace.showCanvas).toHaveBeenCalledWith("drawing");
});
it("reports a deleted drawing instead of creating an empty tab", async () => {
  mocks.getCanvas.mockResolvedValue(null);
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "deleted" }));
  expect(workspace.setError).toHaveBeenCalledWith(expect.stringContaining("no longer exists"));
  expect(workspace.openCanvas).not.toHaveBeenCalled();
  expect(workspace.showCanvas).not.toHaveBeenCalled();
});
it("opens a note without changing the chat workspace", async () => {
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  expect(openNote).toHaveBeenCalledWith("plan");
  expect(workspace.projectCwdRef.current).toBe("/project");
  expect(workspace.openCanvas).not.toHaveBeenCalled();
});
it("uses current settings and reports disabled notes", async () => {
  await act(async () => root.render(createElement(Harness, { notesEnabled: false })));
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  expect(openNote).not.toHaveBeenCalled();
  expect(workspace.setError).toHaveBeenCalledWith(expect.stringContaining("disabled"));
});
it("does not let an older pending canvas read override a newer note click", async () => {
  let finish!: (canvas: object) => void;
  mocks.getCanvas.mockReturnValue(new Promise((resolve) => { finish = resolve; }));
  await act(async () => requestOpenAppResource({ kind: "canvas", id: "slow" }));
  await act(async () => requestOpenAppResource({ kind: "note", id: "plan" }));
  await act(async () => finish({ id: "slow", cwd: "/project" }));
  expect(openNote).toHaveBeenCalledWith("plan");
  expect(workspace.showCanvas).not.toHaveBeenCalled();
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
  expect(openNote).toHaveBeenCalledWith("plan");
  expect(workspace.openFile).not.toHaveBeenCalled();
  expect(workspace.setError).not.toHaveBeenCalled();
});

it("opens a current PDF source at its registered location", async () => {
  mocks.getLearningSource.mockResolvedValue({ id: "pdf-source", kind: "pdf", title: "PDF source", quote: "Passage", documentId: "book", path: "/book.pdf", anchors: [{ page: 3, rects: [] }] });
  mocks.getReadingDocument.mockResolvedValue({ id: "book", path: "/relocated-book.pdf" });
  await act(async () => requestOpenAppResource({ kind: "source", id: "pdf-source" }));
  expect(workspace.openFile).toHaveBeenCalledWith("/relocated-book.pdf", true);
  expect(openNote).not.toHaveBeenCalled();
});
