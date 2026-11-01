import { memo, useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import * as pdfjs from "pdfjs-dist/legacy/build/pdf.mjs";
import type { PDFDocumentProxy, RenderTask } from "pdfjs-dist/legacy/build/pdf.mjs";
import PdfWorker from "pdfjs-dist/legacy/build/pdf.worker.mjs?worker";
import { Minus, Plus } from "../../../shared/ui/icons";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import { FooterButton } from "./FileCard";
import type { PdfAnnotation } from "../../learning/model/types";
import { pdfAnnotationAt } from "../../learning/model/pdfAnnotations";

const MIN_ZOOM = 0.25;
const MAX_ZOOM = 5;
const ZOOM_STEP = 1.25;
/** Space around the pages, and between them. */
const GUTTER = 16;
/** Re-rasterising every visible page per frame of a sash drag would stall it. */
const RENDER_SETTLE_MS = 140;
/** Past this a canvas costs more memory than the sharpness is worth. */
const MAX_CANVAS_PIXELS = 4096 * 4096;

function assetUrl(dir: string): string {
  return new URL(`pdfjs/${dir}/`, document.baseURI).href;
}

type PageSize = { w: number; h: number };
export type LoadedPdf = { document: PDFDocumentProxy; fingerprint: string };
type PdfPlace = { page: number; token: number; annotationId?: string };

function documentFingerprint(document: PDFDocumentProxy): string {
  const fingerprint = document.fingerprints[0];
  if (!fingerprint) throw new Error("This PDF has no readable document fingerprint.");
  return fingerprint;
}

export async function readPdfFingerprint(bytes: Uint8Array): Promise<string> {
  const worker = new pdfjs.PDFWorker({ port: new PdfWorker() as never });
  const task = pdfjs.getDocument({ worker, data: bytes.slice() });
  try {
    const loaded = await task.promise;
    return documentFingerprint(loaded);
  } finally { await task.destroy(); worker.destroy(); }
}

/**
 * A PDF as one continuous scroll of pages with selectable text. Pages are only
 * rasterised while they are near the viewport, so a long document costs what
 * is on screen.
 */
export function PdfView({ bytes, onError, onDocument, annotations = [], selectedAnnotationId, onAnnotationClick, place, onPlaced }: {
  bytes: Uint8Array; onError: (message: string) => void; onDocument?: (loaded: LoadedPdf) => void;
  annotations?: PdfAnnotation[]; selectedAnnotationId?: string;
  onAnnotationClick?: (annotation: PdfAnnotation, rect: DOMRect) => void;
  place?: PdfPlace; onPlaced?: (place: PdfPlace, pageRect: DOMRect) => void;
}) {
  const [doc, setDoc] = useState<PDFDocumentProxy | null>(null);
  const [baseSize, setBaseSize] = useState<PageSize | null>(null);
  const [sizes, setSizes] = useState<ReadonlyMap<number, PageSize>>(new Map());
  const [zoom, setZoom] = useState<number | "fit">("fit");
  const [width, setWidth] = useState(0);
  const [page, setPage] = useState(1);
  const [pageDraft, setPageDraft] = useState<string | null>(null);
  const [textPages, setTextPages] = useState<ReadonlyMap<number, boolean>>(new Map());
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const onErrorRef = useRef(onError);
  onErrorRef.current = onError;
  const onDocumentRef = useRef(onDocument);
  onDocumentRef.current = onDocument;
  const onPlacedRef = useRef(onPlaced);
  onPlacedRef.current = onPlaced;

  useEffect(() => {
    let cancelled = false;
    // Each document owns its worker: destroying one document's task must not
    // take down the worker the next one (or a re-mounted effect) is about to use.
    const worker = new pdfjs.PDFWorker({ port: new PdfWorker() as never });
    // pdf.js transfers the buffer to its worker, so it gets its own copy.
    const task = pdfjs.getDocument({
      worker,
      data: bytes.slice(),
      cMapUrl: assetUrl("cmaps"),
      cMapPacked: true,
      standardFontDataUrl: assetUrl("standard_fonts"),
      wasmUrl: assetUrl("wasm"),
      iccUrl: assetUrl("iccs"),
    });
    void task.promise.then(async (loaded) => {
      const first = await loaded.getPage(1);
      if (cancelled) return;
      const viewport = first.getViewport({ scale: 1 });
      setSizes(new Map());
      setTextPages(new Map());
      setBaseSize({ w: viewport.width, h: viewport.height });
      setDoc(loaded);
      onDocumentRef.current?.({ document: loaded, fingerprint: documentFingerprint(loaded) });
    }).catch((cause: unknown) => {
      if (cancelled) return;
      onErrorRef.current(cause instanceof Error ? cause.message : String(cause));
    });
    return () => {
      cancelled = true;
      void task.destroy().finally(() => worker.destroy());
    };
  }, [bytes]);

  useLayoutEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const observer = new ResizeObserver(() => setWidth(el.clientWidth));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const fitScale = baseSize && width > 0 ? clampZoom((width - GUTTER * 2) / baseSize.w) : 1;
  const scale = zoom === "fit" ? fitScale : zoom;
  // Layout follows `scale` at once; the bitmaps catch up after it settles.
  const [renderScale, setRenderScale] = useState(scale);
  useEffect(() => {
    const timer = window.setTimeout(() => setRenderScale(scale), RENDER_SETTLE_MS);
    return () => window.clearTimeout(timer);
  }, [scale]);

  const onSize = useCallback((number: number, size: PageSize) => {
    setSizes((current) => {
      const known = current.get(number);
      if (known && known.w === size.w && known.h === size.h) return current;
      return new Map(current).set(number, size);
    });
  }, []);
  const onTextAvailable = useCallback((number: number, available: boolean) => {
    setTextPages((current) => current.get(number) === available ? current : new Map(current).set(number, available));
  }, []);

  const pageElement = (number: number) =>
    scrollRef.current?.querySelector<HTMLElement>(`[data-page-number="${number}"]`) ?? null;

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el || !doc) return;
    const middle = el.scrollTop + el.clientHeight / 2;
    let current = 1;
    for (const node of el.querySelectorAll<HTMLElement>("[data-page-number]")) {
      if (node.offsetTop > middle) break;
      current = Number(node.dataset.pageNumber);
    }
    setPage(current);
  };

  const goToPage = (number: number, within = 0) => {
    if (!doc) return;
    const target = Math.max(1, Math.min(doc.numPages, Math.round(number)));
    const node = pageElement(target);
    if (node && scrollRef.current) scrollRef.current.scrollTop = node.offsetTop + within * node.offsetHeight - GUTTER;
    return node;
  };

  // A link to a page of this document: go there once the pages are laid out.
  const placePage = place?.page;
  const placeToken = place?.token;
  const placeAnnotationId = place?.annotationId;
  const placeAnchor = annotations.find((annotation) => annotation.id === placeAnnotationId)?.anchors.find((anchor) => anchor.page === placePage);
  useEffect(() => {
    if (!doc || !baseSize || placePage === undefined || placeToken === undefined) return;
    // Annotation metadata can arrive before or after the PDF. Both are needed
    // before consuming the request or measuring its popover anchor.
    if (placeAnnotationId && !placeAnchor) return;
    const frame = requestAnimationFrame(() => {
      const node = goToPage(placePage, placeAnchor?.rects[0]?.y ?? 0);
      if (node) onPlacedRef.current?.({ page: placePage, token: placeToken, ...(placeAnnotationId ? { annotationId: placeAnnotationId } : {}) }, node.getBoundingClientRect());
    });
    return () => cancelAnimationFrame(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [doc, baseSize, placePage, placeToken, placeAnnotationId, placeAnchor]);

  // Zooming keeps the page being read in view rather than the scroll offset.
  const zoomTo = (next: number | "fit") => {
    const el = scrollRef.current;
    const node = pageElement(page);
    const within = el && node && node.offsetHeight > 0 ? (el.scrollTop - node.offsetTop) / node.offsetHeight : 0;
    setZoom(next);
    requestAnimationFrame(() => {
      const anchor = pageElement(page);
      if (el && anchor) el.scrollTop = anchor.offsetTop + within * anchor.offsetHeight;
    });
  };

  return (
    <div className="flex h-full min-h-0 flex-col">
      {textPages.get(page) === false ? <p role="status" className="shrink-0 border-b border-stroke px-3 py-2 text-[11px] text-content/55">This page has no selectable text. Image-only pages need a text version before you can ask about or highlight a passage.</p> : null}
      <div
        ref={(el) => { scrollRef.current = el; lockOverscroll(el); }}
        onScroll={onScroll}
        className="loci-pdf relative min-h-0 flex-1 overflow-auto overscroll-none bg-content/[0.04]"
      >
        {doc && baseSize ? (
          <div className="mx-auto flex w-max min-w-full flex-col items-center" style={{ padding: GUTTER, gap: GUTTER }}>
            {Array.from({ length: doc.numPages }, (_, index) => (
              <PdfPage key={index + 1} doc={doc} number={index + 1} size={sizes.get(index + 1) ?? baseSize}
                scale={scale} renderScale={renderScale} root={scrollRef} onSize={onSize}
                annotations={annotations} selectedAnnotationId={selectedAnnotationId} onAnnotationClick={onAnnotationClick} onTextAvailable={onTextAvailable} />
            ))}
          </div>
        ) : (
          <div className="grid h-full place-items-center text-[12px] text-content/45">Opening…</div>
        )}
      </div>
      <footer className="flex h-8 shrink-0 items-center gap-2 border-t border-stroke px-3 text-[11px] text-content/50">
        <span>Page</span>
        <input
          aria-label="Page number"
          inputMode="numeric"
          value={pageDraft ?? String(page)}
          disabled={!doc}
          onFocus={(event) => { setPageDraft(String(page)); event.currentTarget.select(); }}
          onChange={(event) => setPageDraft(event.target.value.replace(/\D/g, ""))}
          onBlur={() => setPageDraft(null)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              if (pageDraft) goToPage(Number(pageDraft));
              event.currentTarget.blur();
            } else if (event.key === "Escape") {
              event.preventDefault();
              event.currentTarget.blur();
            }
          }}
          className="h-5 w-10 rounded bg-content/10 px-1 text-center tabular-nums text-content outline-none focus:ring-1 focus:ring-accent-ring"
        />
        <span className="tabular-nums">/ {doc?.numPages ?? "—"}</span>
        <span className="flex-1" />
        <FooterButton label="Zoom out" disabled={!doc} onClick={() => zoomTo(clampZoom(scale / ZOOM_STEP))}>
          <Minus className="size-3" strokeWidth={1.75} />
        </FooterButton>
        <button type="button" title="Fit to width" disabled={!doc} onClick={() => zoomTo("fit")}
          className="w-11 rounded text-center tabular-nums hover:text-content">
          {zoom === "fit" ? "Fit" : `${Math.round(zoom * 100)}%`}
        </button>
        <FooterButton label="Zoom in" disabled={!doc} onClick={() => zoomTo(clampZoom(scale * ZOOM_STEP))}>
          <Plus className="size-3" strokeWidth={1.75} />
        </FooterButton>
      </footer>
    </div>
  );
}

const PdfPage = memo(function PdfPage({ doc, number, size, scale, renderScale, root, onSize, annotations, selectedAnnotationId, onAnnotationClick, onTextAvailable }: {
  doc: PDFDocumentProxy;
  number: number;
  size: PageSize;
  scale: number;
  renderScale: number;
  root: { current: HTMLDivElement | null };
  onSize: (number: number, size: PageSize) => void;
  annotations: PdfAnnotation[];
  selectedAnnotationId?: string;
  onAnnotationClick?: (annotation: PdfAnnotation, rect: DOMRect) => void;
  onTextAvailable: (number: number, available: boolean) => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const canvasSlot = useRef<HTMLDivElement>(null);
  const textSlot = useRef<HTMLDivElement>(null);
  const [near, setNear] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(([entry]) => setNear(entry.isIntersecting), {
      root: root.current,
      rootMargin: "150% 0px",
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, [root]);

  useEffect(() => {
    const canvasHost = canvasSlot.current;
    const textHost = textSlot.current;
    if (!near || !canvasHost || !textHost) return;
    let cancelled = false;
    let renderTask: RenderTask | null = null;
    let textLayer: pdfjs.TextLayer | null = null;

    void doc.getPage(number).then(async (page) => {
      if (cancelled) return;
      const base = page.getViewport({ scale: 1 });
      onSize(number, { w: base.width, h: base.height });
      const viewport = page.getViewport({ scale: renderScale });
      const ratio = Math.min(
        window.devicePixelRatio || 1,
        Math.sqrt(MAX_CANVAS_PIXELS / (viewport.width * viewport.height)),
      );
      const canvas = document.createElement("canvas");
      canvas.width = Math.max(1, Math.floor(viewport.width * ratio));
      canvas.height = Math.max(1, Math.floor(viewport.height * ratio));
      renderTask = page.render({ canvas, viewport, transform: ratio === 1 ? undefined : [ratio, 0, 0, ratio, 0, 0] });
      await renderTask.promise;
      if (cancelled) return;
      // Swap the finished bitmap in, so a re-render never blanks the page.
      canvasHost.replaceChildren(canvas);

      const layer = document.createElement("div");
      layer.className = "textLayer";
      textLayer = new pdfjs.TextLayer({ textContentSource: page.streamTextContent(), container: layer, viewport });
      await textLayer.render();
      if (cancelled) return;
      textHost.replaceChildren(layer);
      onTextAvailable(number, !!layer.textContent?.trim());
    }).catch(() => {
      /* a cancelled render rejects; a broken page just stays blank */
    });

    return () => {
      cancelled = true;
      renderTask?.cancel();
      textLayer?.cancel();
    };
  }, [doc, number, near, renderScale, onSize, onTextAvailable]);

  // Bitmaps of pages scrolled far away are released, keeping only their box.
  useEffect(() => {
    if (near) return;
    canvasSlot.current?.replaceChildren();
    textSlot.current?.replaceChildren();
  }, [near]);

  return (
    <div
      ref={ref}
      data-page-number={number}
      onClick={(event) => {
        // Marks never intercept pointer events: dragging across a highlight
        // still selects the native PDF text. A collapsed click opens its note.
        if (window.getSelection()?.toString().trim()) return;
        const pageRect = event.currentTarget.getBoundingClientRect();
        if (!pageRect.width || !pageRect.height) return;
        const annotation = pdfAnnotationAt(annotations, number,
          (event.clientX - pageRect.left) / pageRect.width, (event.clientY - pageRect.top) / pageRect.height);
        if (annotation) onAnnotationClick?.(annotation, new DOMRect(event.clientX, event.clientY, 1, 1));
      }}
      className="loci-pdf-page relative shrink-0 bg-white shadow-[0_1px_3px_rgb(0_0_0/0.25)]"
      style={{
        width: Math.floor(size.w * scale),
        height: Math.floor(size.h * scale),
        "--total-scale-factor": scale,
        "--scale-round-x": "1px",
        "--scale-round-y": "1px",
      } as React.CSSProperties}
    >
      <div ref={canvasSlot} className="loci-pdf-canvas absolute inset-0" />
      <div aria-hidden="true" className="pointer-events-none absolute inset-0">
        {annotations.flatMap((annotation) => annotation.anchors.filter((anchor) => anchor.page === number).flatMap((anchor) =>
          anchor.rects.map((rect, index) => <div key={`${annotation.id}:${index}`} data-pdf-annotation={annotation.id}
            className={`absolute rounded-[2px] ${selectedAnnotationId === annotation.id ? "bg-amber-400/45 ring-1 ring-amber-500/70" : "bg-yellow-300/45"}`}
            style={{ left: `${rect.x * 100}%`, top: `${rect.y * 100}%`, width: `${rect.width * 100}%`, height: `${rect.height * 100}%` }} />)))}
      </div>
      <div ref={textSlot} className="absolute inset-0" />
    </div>
  );
});

function clampZoom(value: number): number {
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
}
