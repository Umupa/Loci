import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { LAYER } from "../lib/layers";
import { X } from "./icons";
import { ImageViewport } from "./ImageViewport";

type Props = {
  src: string;
  alt: string;
  onClose: () => void;
};

export function ImageLightbox({ src, alt, onClose }: Props) {
  const closeRef = useRef<HTMLButtonElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const previouslyFocused = document.activeElement;
    closeRef.current?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      event.stopPropagation();
      onCloseRef.current();
    };

    window.addEventListener("keydown", onKeyDown, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      if (previouslyFocused instanceof HTMLElement) previouslyFocused.focus();
    };
  }, []);

  return createPortal(
    <div
      role="dialog"
      aria-modal="true"
      aria-label={`Image preview: ${alt}`}
      className="fixed inset-0 bg-black/85 backdrop-blur-sm"
      style={{ zIndex: LAYER.dialog }}
      onMouseDown={(event) => {
        event.stopPropagation();
      }}
      onClick={(event) => event.stopPropagation()}
    >
      <button
        ref={closeRef}
        type="button"
        aria-label="Close image preview"
        title="Close"
        onClick={onClose}
        className="absolute right-4 top-4 z-10 grid size-9 place-items-center rounded-full border border-white/15 bg-black/45 text-white/80 shadow-lg backdrop-blur-md hover:bg-black/65 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/80"
      >
        <X className="size-4" strokeWidth={2} />
      </button>
      <ImageViewport src={src} alt={alt} active="modal" onBackgroundClick={onClose} />
    </div>,
    document.body,
  );
}
