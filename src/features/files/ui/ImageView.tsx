import { t, useLocale } from "../../../shared/i18n/locale";
import { useState } from "react";
import { Minus, Plus } from "../../../shared/ui/icons";
import { formatFileSize } from "../../../shared/lib/filePreview";
import { FooterButton } from "./FileCard";

const MIN_ZOOM = 0.1;
const MAX_ZOOM = 16;

export function ImageView({ url, size, mime }: { url: string; size: number; mime: string }) {
  useLocale();
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [zoom, setZoom] = useState<number | "fit">("fit");

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div
        className="grid min-h-0 flex-1 place-items-center overflow-auto overscroll-contain p-4"
        style={{
          // A checkerboard so transparent PNGs read as transparent rather than
          // as whatever the theme background happens to be.
          backgroundImage:
            "linear-gradient(45deg, rgba(128,128,128,0.10) 25%, transparent 25%, transparent 75%, rgba(128,128,128,0.10) 75%), linear-gradient(45deg, rgba(128,128,128,0.10) 25%, transparent 25%, transparent 75%, rgba(128,128,128,0.10) 75%)",
          backgroundSize: "16px 16px",
          backgroundPosition: "0 0, 8px 8px",
        }}
      >
        <img
          src={url}
          alt=""
          draggable={false}
          onLoad={(event) => setNatural({ w: event.currentTarget.naturalWidth, h: event.currentTarget.naturalHeight })}
          onClick={() => setZoom((value) => (value === "fit" ? 1 : "fit"))}
          className={zoom === "fit" ? "max-h-full max-w-full object-contain" : "max-w-none object-contain"}
          style={zoom === "fit" || !natural ? undefined : { width: natural.w * zoom, height: natural.h * zoom }}
        />
      </div>
      <footer className="flex h-8 shrink-0 items-center gap-3 border-t border-stroke px-3 text-[11px] text-content/50">
        <span className="tabular-nums">{natural ? `${natural.w} × ${natural.h}` : "—"}</span>
        <span className="tabular-nums">{formatFileSize(size)}</span>
        <span className="uppercase">{mime.replace(/^image\//, "")}</span>
        <span className="flex-1" />
        <FooterButton label={t("Zoom out")} onClick={() => setZoom((value) => clampZoom((value === "fit" ? 1 : value) / 1.5))}>
          <Minus className="size-3" strokeWidth={1.75} />
        </FooterButton>
        <button type="button" title={t("Fit to window")} onClick={() => setZoom("fit")} className="w-11 rounded text-center tabular-nums hover:text-content">
          {zoom === "fit" ? t("Fit") : `${Math.round(zoom * 100)}%`}
        </button>
        <FooterButton label={t("Zoom in")} onClick={() => setZoom((value) => clampZoom((value === "fit" ? 1 : value) * 1.5))}>
          <Plus className="size-3" strokeWidth={1.75} />
        </FooterButton>
      </footer>
    </div>
  );
}

function clampZoom(value: number): number {
  return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, value));
}
