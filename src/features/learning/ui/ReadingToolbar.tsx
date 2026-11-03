import type { ReactNode } from "react";
import "./ReadingToolbar.css";

/*
 * The small bar beside a passage, the same in every reader: on a selection,
 * and on a highlight already kept. Each action is one button; a bar for a
 * kind of passage adds its own (a table or a figure, later) the same way.
 */

const keepSelection = (event: { preventDefault(): void }) => event.preventDefault();

export function ToolbarButton({ icon, label, title, onClick, disabled, iconOnly = false, pressed, danger = false }: {
  icon: ReactNode; label: string; title?: string; onClick: () => void; disabled?: boolean;
  /** A label a tooltip says, for actions that are clear from their icon. */
  iconOnly?: boolean;
  pressed?: boolean;
  /** It removes something the reader kept. */
  danger?: boolean;
}) {
  return <button type="button" className={`reading-toolbar__button${danger ? " reading-toolbar__button--danger" : ""}`} disabled={disabled} title={title ?? label}
    aria-label={iconOnly ? label : undefined} aria-pressed={pressed} onMouseDown={keepSelection} onClick={onClick}>
    {icon}{iconOnly ? null : <span>{label}</span>}
  </button>;
}

export const ToolbarDivider = () => <span aria-hidden="true" className="reading-toolbar__divider" />;
