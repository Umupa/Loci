// @vitest-environment happy-dom
import { act, createElement, Fragment } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { readDocumentFile } from "../../../platform/tauri/fs";
import type { PdfAnnotation } from "../../learning/model/types";
import { createPdfAnnotation } from "../../learning/model/pdfAnnotations";
import { consumeFilePlace, requestFilePlace, useFilePlace, type FilePlaceRequest } from "../model/filePlace";
import { FilePane } from "./FilePane";

const pdf = vi.hoisted(() => {
  const page = { getViewport: ({ scale }: { scale: number }) => ({ width: 100 * scale, height: 100 * scale }),
    render: () => ({ promise: Promise.resolve(), cancel: vi.fn() }), streamTextContent: () => "Readable passage" };
  const document = { numPages: 3, fingerprints: ["fingerprint", null], getPage: async () => page };
  return { document, load: () => Promise.resolve(document) };
});
vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => ({
  PDFWorker: class { destroy() {} },
  getDocument: () => ({ promise: pdf.load(), destroy: async () => {} }),
  TextLayer: class {
    constructor(private options: { container: HTMLElement }) {}
    async render() { this.options.container.textContent = "Readable passage"; }
    cancel() {}
  },
}));
vi.mock("pdfjs-dist/legacy/build/pdf.worker.mjs?worker", () => ({ default: class {} }));
vi.mock("../../../platform/tauri/fs", () => ({ basename: (path: string) => path.split("/").pop(), readDocumentFile: vi.fn(),
  readBinaryFile: vi.fn(), readTextFile: vi.fn(), writeTextFile: vi.fn(), openPathWithDefaultApp: vi.fn(), revealPath: vi.fn() }));
vi.mock("../model/fileWatch", () => ({ watchFile: () => () => {}, syncWatchedMtime: vi.fn() }));
vi.mock("../../learning/model/learningStore", () => ({
  getReadingDocumentByPath: async (path: string) => ({ ...record, path }),
  registerReadingDocument: async (path: string) => ({ ...record, path }),
  listPdfAnnotations: () => loadMarks(),
  subscribeLearningChanges: () => () => {}, registerLearningSource: vi.fn(),
  upsertPdfAnnotation: vi.fn(), deletePdfAnnotation: vi.fn(), listAnnotations: vi.fn(async () => []), upsertAnnotation: vi.fn(), deleteAnnotation: vi.fn(), relocateReadingDocument: vi.fn(),
}));
// Inspect the anchor handed to the real annotation UI after the real PDF view scrolls.
vi.mock("../../learning/ui/PdfAnnotations", () => ({
  AnnotationList: () => null,
  AnnotationPopover: ({ annotation, anchor }: { annotation: PdfAnnotation; anchor: DOMRect }) =>
    createElement("output", { "data-open-annotation": annotation.id, "data-anchor": JSON.stringify({ x: anchor.x, y: anchor.y, width: anchor.width, height: anchor.height }) }),
}));

const record = { id: "document", path: "/book.pdf", title: "Book", fingerprint: "fingerprint", createdAt: 1, updatedAt: 1 };
let marks: PdfAnnotation[];
let loadMarks: () => Promise<PdfAnnotation[]>;
let host: HTMLDivElement;
let root: Root;
let pending: FilePlaceRequest | undefined;
let currentPath: string;
let frames: Map<number, FrameRequestCallback>;
let frameId: number;

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
function ObservePlace({ path }: { path: string }) { pending = useFilePlace(path); return null; }
async function show(path = record.path) {
  currentPath = path;
  await act(async () => root.render(createElement(Fragment, null, createElement(ObservePlace, { path }),
    createElement(FilePane, { path, cwd: "/", preview: false, focused: true, onFocus: vi.fn(), onPin: vi.fn(), onClose: vi.fn(), onOpenFile: vi.fn() }))));
  await act(async () => vi.dynamicImportSettled());
}
async function flushFrames() {
  await act(async () => {
    const scheduled = [...frames.values()]; frames.clear();
    for (const callback of scheduled) callback(0);
  });
}
const scroller = () => host.querySelector<HTMLElement>(".loci-pdf")!;
const popover = () => host.querySelector<HTMLElement>("[data-open-annotation]");
function expectPlaced(mark = marks[0]) {
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(300 + mark.anchors[0].rects[0].y * 100 - 16);
  expect(popover()?.dataset.openAnnotation).toBe(mark.id);
  // Scrolling aligns the passage below the scroller's y=200 edge and 16px gutter.
  expect(JSON.parse(popover()!.dataset.anchor!)).toEqual({ x: 110, y: 216, width: 40, height: 10 });
}

beforeEach(() => {
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT", true);
  vi.stubGlobal("ResizeObserver", class { observe() {} disconnect() {} });
  vi.stubGlobal("IntersectionObserver", class {
    constructor(private callback: (entries: Array<{ isIntersecting: boolean }>) => void) {}
    observe() { this.callback([{ isIntersecting: true }]); } disconnect() {}
  });
  frames = new Map(); frameId = 0;
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => { frames.set(++frameId, callback); return frameId; });
  vi.stubGlobal("cancelAnimationFrame", (id: number) => frames.delete(id));
  vi.spyOn(HTMLElement.prototype, "offsetTop", "get").mockImplementation(function (this: HTMLElement) { return this.dataset.pageNumber === "2" ? 300 : this.dataset.pageNumber === "3" ? 600 : 0; });
  vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockReturnValue(100);
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(function (this: HTMLElement) {
    return this.dataset.pageNumber ? new DOMRect(100, 200 + this.offsetTop - (this.closest<HTMLElement>(".loci-pdf")?.scrollTop ?? 0), 100, 100) : new DOMRect(0, 0, 500, 500);
  });
  marks = [createPdfAnnotation(record, "Later passage", [{ page: 2, rects: [{ x: 0.1, y: 0.8, width: 0.4, height: 0.1 }] }])];
  loadMarks = async () => marks;
  vi.mocked(readDocumentFile).mockReset().mockResolvedValue(new Uint8Array([1]));
  pdf.load = () => Promise.resolve(pdf.document);
  currentPath = record.path; pending = undefined;
  host = document.createElement("div"); document.body.append(host); root = createRoot(host);
});
afterEach(async () => {
  await act(async () => { if (pending) consumeFilePlace(currentPath, pending.token); root.unmount(); });
  host.remove(); vi.unstubAllGlobals(); vi.restoreAllMocks();
});

it.each(["bytes", "document"] as const)("retains an annotation request while PDF %s loads and anchors its popover after scrolling", async (stage) => {
  const bytes = deferred<Uint8Array>();
  const document = deferred<typeof pdf.document>();
  if (stage === "bytes") vi.mocked(readDocumentFile).mockReturnValue(bytes.promise);
  else pdf.load = () => document.promise;
  requestFilePlace(record.path, { page: 2, annotationId: marks[0].id });
  await show(); await flushFrames();
  expect(host.querySelector("[data-page-number]")).toBeNull();
  expect(pending?.place).toEqual({ page: 2, annotationId: marks[0].id });
  expect(popover()).toBeNull();
  await act(async () => { if (stage === "bytes") bytes.resolve(new Uint8Array([1])); else document.resolve(pdf.document); });
  await act(async () => vi.dynamicImportSettled());
  await flushFrames();
  expectPlaced();
});

it("opens an annotation in an already loaded PDF using its position after scrolling", async () => {
  await show();
  expect(host.querySelector('[data-page-number="2"]')).not.toBeNull();
  await act(async () => requestFilePlace(record.path, { page: 2, annotationId: marks[0].id }));
  await flushFrames();
  expectPlaced();
});

it("waits for annotation metadata even when its passage is at the top of an already loaded page", async () => {
  const annotations = deferred<PdfAnnotation[]>();
  loadMarks = () => annotations.promise;
  marks[0].anchors[0].rects[0].y = 0;
  requestFilePlace(record.path, { page: 2, annotationId: marks[0].id });
  await show(); await flushFrames();
  expect(host.querySelector('[data-page-number="2"]')).not.toBeNull();
  expect(pending?.place).toEqual({ page: 2, annotationId: marks[0].id });
  expect(popover()).toBeNull();
  await act(async () => annotations.resolve(marks));
  await flushFrames();
  expectPlaced();
});

it("opens the saved page when a source snapshot refers to a highlight that has been deleted", async () => {
  loadMarks = async () => [];
  requestFilePlace(record.path, { page: 2, annotationId: marks[0].id });
  await show(); await flushFrames();
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(284);
  expect(popover()).toBeNull();
});

it.each(["bytes", "document"] as const)("keeps ordinary page placement working while PDF %s loads", async (stage) => {
  const bytes = deferred<Uint8Array>();
  const document = deferred<typeof pdf.document>();
  if (stage === "bytes") vi.mocked(readDocumentFile).mockReturnValue(bytes.promise);
  else pdf.load = () => document.promise;
  requestFilePlace(record.path, { page: 2 });
  await show(); await flushFrames();
  expect(pending?.place).toEqual({ page: 2 });
  await act(async () => { if (stage === "bytes") bytes.resolve(new Uint8Array([1])); else document.resolve(pdf.document); });
  await act(async () => vi.dynamicImportSettled());
  await flushFrames();
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(284);
  expect(popover()).toBeNull();
});

it("cancels the old placement frame when a newer page request replaces it", async () => {
  await show();
  await act(async () => requestFilePlace(record.path, { page: 2, annotationId: marks[0].id }));
  await act(async () => requestFilePlace(record.path, { page: 3 }));
  expect(pending?.place).toEqual({ page: 3 });
  await flushFrames();
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(584);
  expect(popover()).toBeNull();
});

it("cancels an old path's scheduled annotation placement without consuming the next path's request", async () => {
  await show();
  await act(async () => requestFilePlace(record.path, { page: 2, annotationId: marks[0].id }));
  const oldToken = pending!.token;
  const nextPath = "/next.pdf";
  requestFilePlace(nextPath, { page: 3 });
  await show(nextPath);
  expect(pending?.place).toEqual({ page: 3 });
  await flushFrames();
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(584);
  expect(popover()).toBeNull();
  consumeFilePlace(record.path, oldToken);
});

it("leaves a new path's request intact when the previous path's PDF read completes", async () => {
  const oldBytes = deferred<Uint8Array>();
  const newBytes = deferred<Uint8Array>();
  vi.mocked(readDocumentFile).mockImplementation((path) => path === record.path ? oldBytes.promise : newBytes.promise);
  requestFilePlace(record.path, { page: 2, annotationId: marks[0].id });
  await show();
  const oldToken = pending!.token;
  const nextPath = "/next.pdf";
  requestFilePlace(nextPath, { page: 3 });
  await show(nextPath);
  await act(async () => oldBytes.resolve(new Uint8Array([1])));
  await flushFrames();
  expect(pending?.place).toEqual({ page: 3 });
  expect(popover()).toBeNull();
  await act(async () => newBytes.resolve(new Uint8Array([2])));
  await act(async () => vi.dynamicImportSettled());
  await flushFrames();
  expect(pending).toBeUndefined();
  expect(scroller().scrollTop).toBe(584);
  consumeFilePlace(record.path, oldToken);
});
