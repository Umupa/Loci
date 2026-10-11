import { useEffect, useRef, useState, type ReactNode } from "react";
import { claimTrackpadMagnify } from "../../platform/tauri/trackpadZoom";
import { getImageZoomTarget, IMAGE_ZOOM_EVENT, type ImageZoomAction } from "../lib/imageZoomCommands";
import { clampImageView, IMAGE_ZOOM_STEP, MAX_IMAGE_SCALE, zoomImageAt, type ImageSize, type ImageViewState } from "../lib/imageViewport";
import { Minus, Plus } from "./icons";

type Props = {
  src: string;
  alt: string;
  active?: "modal" | "focused";
  metadata?: ReactNode;
  onBackgroundClick?: () => void;
};
const INITIAL_VIEW: ImageViewState = { scale: 1, x: 0, y: 0, fit: true };
const MAGNIFY_EVENT = "loci:image-magnify";

/** Shared by file panes and full-screen previews so gestures have the same meaning. */
export function ImageViewport(props: Props) {
  // A new source starts at Fit, including when two files have the same dimensions.
  return <ImageViewportContent key={props.src} {...props} />;
}

function ImageViewportContent({ src, alt, active, metadata, onBackgroundClick }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const imageRef = useRef<HTMLImageElement>(null);
  const [natural, setNatural] = useState<ImageSize | null>(null);
  const [view, setView] = useState(INITIAL_VIEW);
  const [dragging, setDragging] = useState(false);
  const viewRef = useRef(view);
  const commands = useRef<(action: ImageZoomAction | "actual") => void>(() => {});
  const backgroundClick = useRef(onBackgroundClick);
  backgroundClick.current = onBackgroundClick;
  const modal = active === "modal";

  useEffect(() => {
    const container = containerRef.current!;
    // Reserve shortcuts during loading too, so they cannot scale the app behind a preview.
    const onCommand = (event: Event) => {
      event.preventDefault();
      commands.current((event as CustomEvent<ImageZoomAction>).detail);
    };
    container.addEventListener(IMAGE_ZOOM_EVENT, onCommand);
    const releaseMagnify = active ? claimTrackpadMagnify((delta) => {
      getImageZoomTarget()?.dispatchEvent(new CustomEvent(MAGNIFY_EVENT, { detail: delta }));
    }) : undefined;
    return () => {
      container.removeEventListener(IMAGE_ZOOM_EVENT, onCommand);
      releaseMagnify?.();
    };
  }, [active]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container || !natural) return;
    const viewport = () => ({ width: Math.max(1, container.clientWidth - 48), height: Math.max(1, container.clientHeight - 48) });
    const update = (next: ImageViewState) => {
      viewRef.current = clampImageView(next, natural, viewport());
      setView(viewRef.current);
    };
    const centerPoint = (clientX: number, clientY: number) => {
      const rect = container.getBoundingClientRect();
      return { x: clientX - rect.left - rect.width / 2, y: clientY - rect.top - rect.height / 2 };
    };
    let pointer = { x: 0, y: 0 };
    const zoom = (scale: number, point = { x: 0, y: 0 }) => update(zoomImageAt(viewRef.current, scale, point, natural, viewport()));
    commands.current = (action) => {
      if (action === "zoom-reset") update(INITIAL_VIEW);
      else zoom(action === "actual" ? 1 : viewRef.current.scale * (action === "zoom-in" ? IMAGE_ZOOM_STEP : 1 / IMAGE_ZOOM_STEP));
    };
    const onMagnify = (event: Event) => zoom(viewRef.current.scale * (1 + (event as CustomEvent<number>).detail), pointer);
    let gestureScale: number | null = null;
    const onGestureStart = (event: Event) => {
      event.preventDefault();
      gestureScale = viewRef.current.scale;
    };
    const onGestureChange = (event: Event) => {
      event.preventDefault();
      const scale = (event as Event & { scale: number }).scale;
      if (gestureScale !== null && Number.isFinite(scale) && scale > 0) zoom(gestureScale * scale, pointer);
    };
    const onGestureEnd = (event: Event) => { event.preventDefault(); gestureScale = null; };
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      event.stopPropagation();
      if (gestureScale !== null) return;
      const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? container.clientHeight : 1;
      if (event.ctrlKey || event.metaKey) {
        zoom(viewRef.current.scale * Math.exp(-event.deltaY * unit * 0.01), centerPoint(event.clientX, event.clientY));
      } else {
        update({ ...viewRef.current, x: viewRef.current.x - event.deltaX * unit, y: viewRef.current.y - event.deltaY * unit });
      }
    };
    let drag: { id: number; startX: number; startY: number; view: ImageViewState; moved: boolean; background: boolean } | null = null;
    const onPointerDown = (event: PointerEvent) => {
      if (event.button !== 0 || !event.isPrimary) return;
      pointer = centerPoint(event.clientX, event.clientY);
      drag = { id: event.pointerId, startX: event.clientX, startY: event.clientY, view: viewRef.current, moved: false, background: event.target === container };
    };
    const onPointerMove = (event: PointerEvent) => {
      pointer = centerPoint(event.clientX, event.clientY);
      if (!drag || drag.id !== event.pointerId) return;
      const dx = event.clientX - drag.startX;
      const dy = event.clientY - drag.startY;
      if (!drag.moved && Math.hypot(dx, dy) < 4) return;
      if (!drag.moved) container.setPointerCapture(event.pointerId);
      drag.moved = true;
      setDragging(true);
      update({ ...drag.view, x: drag.view.x + dx, y: drag.view.y + dy });
    };
    const endDrag = (event: PointerEvent) => {
      if (!drag || drag.id !== event.pointerId) return;
      const close = event.type === "pointerup" && drag.background && !drag.moved;
      drag = null;
      setDragging(false);
      if (container.hasPointerCapture(event.pointerId)) container.releasePointerCapture(event.pointerId);
      if (close) backgroundClick.current?.();
    };
    const onDoubleClick = (event: MouseEvent) => {
      if (event.target !== imageRef.current) return;
      if (viewRef.current.fit) zoom(Math.max(1, viewRef.current.scale * 2.5), centerPoint(event.clientX, event.clientY));
      else update(INITIAL_VIEW);
    };
    const onResize = () => update(viewRef.current);
    const observer = new ResizeObserver(onResize);
    observer.observe(container);
    update(viewRef.current);
    container.addEventListener(MAGNIFY_EVENT, onMagnify);
    container.addEventListener("wheel", onWheel, { passive: false });
    container.addEventListener("gesturestart", onGestureStart, { passive: false });
    container.addEventListener("gesturechange", onGestureChange, { passive: false });
    container.addEventListener("gestureend", onGestureEnd, { passive: false });
    container.addEventListener("pointerdown", onPointerDown);
    container.addEventListener("pointermove", onPointerMove);
    container.addEventListener("pointerup", endDrag);
    container.addEventListener("pointercancel", endDrag);
    container.addEventListener("lostpointercapture", endDrag);
    container.addEventListener("dblclick", onDoubleClick);
    return () => {
      observer.disconnect();
      container.removeEventListener(MAGNIFY_EVENT, onMagnify);
      container.removeEventListener("wheel", onWheel);
      container.removeEventListener("gesturestart", onGestureStart);
      container.removeEventListener("gesturechange", onGestureChange);
      container.removeEventListener("gestureend", onGestureEnd);
      container.removeEventListener("pointerdown", onPointerDown);
      container.removeEventListener("pointermove", onPointerMove);
      container.removeEventListener("pointerup", endDrag);
      container.removeEventListener("pointercancel", endDrag);
      container.removeEventListener("lostpointercapture", endDrag);
      container.removeEventListener("dblclick", onDoubleClick);
      commands.current = () => {};
    };
  }, [natural]);

  const buttonClass = "grid h-7 min-w-7 place-items-center rounded-md px-1.5 hover:bg-current/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-current disabled:opacity-35";
  return (
    <div className={`flex h-full min-h-0 min-w-0 flex-col ${modal ? "text-white/80" : "text-content/60"}`}>
      <div ref={containerRef} data-image-zoom={active} className="relative min-h-0 flex-1 overflow-hidden overscroll-contain"
        style={{ touchAction: "none", cursor: dragging ? "grabbing" : undefined,
          ...(!modal ? { backgroundImage: "conic-gradient(rgba(128,128,128,0.10) 25%, transparent 0 50%, rgba(128,128,128,0.10) 0 75%, transparent 0)", backgroundSize: "16px 16px" } : {}),
        }}>
        <img ref={imageRef} src={src} alt={alt} draggable={false} referrerPolicy="no-referrer"
          onLoad={(event) => {
            const { naturalWidth: width, naturalHeight: height } = event.currentTarget;
            if (width > 0 && height > 0) setNatural({ width, height });
          }}
          className="absolute left-1/2 top-1/2 max-w-none select-none object-contain"
          style={{ width: natural ? natural.width * view.scale : undefined, height: natural ? natural.height * view.scale : undefined,
            visibility: natural ? "visible" : "hidden", transform: `translate(-50%, -50%) translate(${view.x}px, ${view.y}px)`,
            cursor: dragging ? "grabbing" : view.fit ? "zoom-in" : "grab",
          }} />
      </div>
      <footer className={`flex shrink-0 items-center gap-1 px-3 text-[11px] ${modal ? "h-12 justify-center" : "h-8 border-t border-stroke"}`}>
        {!modal && <><span className="mr-2 tabular-nums">{natural ? `${natural.width} × ${natural.height}` : "—"}</span>{metadata}<span className="flex-1" /></>}
        <button type="button" className={buttonClass} aria-label="Zoom out" title="Zoom out" disabled={!natural} onClick={() => commands.current("zoom-out")}><Minus className="size-3.5" /></button>
        <output aria-label="Image zoom" className="w-12 text-center tabular-nums">{Math.round(view.scale * 100)}%</output>
        <button type="button" className={buttonClass} aria-label="Zoom in" title="Zoom in" disabled={!natural || view.scale >= MAX_IMAGE_SCALE} onClick={() => commands.current("zoom-in")}><Plus className="size-3.5" /></button>
        <span className={`mx-2 h-3 border-l ${modal ? "border-white/20" : "border-stroke"}`} />
        <button type="button" className={buttonClass} aria-label="Fit to window" title="Fit to window" aria-pressed={view.fit} disabled={!natural} onClick={() => commands.current("zoom-reset")}>Fit</button>
        <button type="button" className={buttonClass} aria-label="Actual size" title="Actual size (100%)" disabled={!natural} onClick={() => commands.current("actual")}>100%</button>
      </footer>
    </div>
  );
}
