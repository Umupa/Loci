import { forwardRef } from "react";
import icon from "../../assets/excalidraw/icon.svg";
import type { IconProps } from "./icons";

/** Official application mark; keep its original colors at every chrome size. */
export const ExcalidrawIcon = forwardRef<SVGSVGElement, IconProps>(function ExcalidrawIcon(props, ref) {
  return (
    <svg ref={ref} width={24} height={24} viewBox="0 0 24 24" aria-hidden="true" {...props}>
      <image href={icon} width={24} height={24} />
    </svg>
  );
});
