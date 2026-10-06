import { forwardRef } from "react";
import { EXCALIDRAW_MARK_PATH, EXCALIDRAW_MARK_TRANSFORM } from "../../assets/excalidraw/mark";
import type { IconProps } from "./icons";

/** Official glyph, using the same monochrome treatment as the other chrome icons. */
export const ExcalidrawIcon = forwardRef<SVGSVGElement, IconProps>(function ExcalidrawIcon(props, ref) {
  return (
    <svg ref={ref} width={24} height={24} viewBox="0 0 107 101" aria-hidden="true" {...props}>
      <path d={EXCALIDRAW_MARK_PATH} transform={EXCALIDRAW_MARK_TRANSFORM} fill="currentColor" />
    </svg>
  );
});
