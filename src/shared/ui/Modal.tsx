import { useUiText } from "../i18n/SettingsLanguage";
import { NativePopupHost } from "./NativePopupHost";
import { InDialog } from "./DialogContext";
import { X } from "./icons";
import { useContext, useEffect, useId, useRef, type KeyboardEvent as ReactKeyboardEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useLockOverscroll } from "../hooks/useLockOverscroll";
import { LAYER } from "../lib/layers";
import { GlassBackdrop } from "../../app/shell/GlassBackdrop";

export type ModalSize = "sm" | "md" | "lg";

const TABBABLE =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/** Controls a keyboard user can reach, in document order. */
function tabbableIn(panel: HTMLElement): HTMLElement[] {
  return Array.from(panel.querySelectorAll<HTMLElement>(TABBABLE)).filter(
    (element) => !element.closest('[hidden], [aria-hidden="true"]'),
  );
}

const WIDTH: Record<ModalSize, string> = {
  sm: "w-[min(420px,calc(100vw-24px))]",
  md: "w-[min(560px,calc(100vw-24px))]",
  lg: "w-[min(1080px,calc(100vw-48px))]",
};

const TOP: Record<ModalSize, string> = {
  sm: "top-[22%]",
  md: "top-[10%]",
  lg: "top-[6%]",
};

type Props = {
  onClose: () => void;
  title: string;
  description?: string;
  size?: ModalSize;
  /** Keeps the accessible title while letting focused content own the visual hierarchy. */
  minimalHeader?: boolean;
  /** Extra classes on the panel (fixed height, etc). */
  className?: string;
  /** Keep taller dialogs inside the viewport, scrolling their content. */
  fitViewport?: boolean;
  /** Pinned below the scrolling body, so a long body cannot push it off screen. */
  footer?: ReactNode;
  /** Keep the close button from taking focus, when the primary action should have it. */
  autoFocusClose?: boolean;
  /** Disable the header's close button while a blocking action runs. */
  closeDisabled?: boolean;
  children: ReactNode;
};

export function ModalPanel({
  onClose,
  title,
  description,
  size = "md",
  minimalHeader = false,
  className,
  fitViewport = false,
  footer,
  autoFocusClose = true,
  closeDisabled = false,
  children,
}: Props) {
  const { t, locale } = useUiText();
  const popupHost = useContext(NativePopupHost);
  const panelRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const uid = useId();
  const titleId = `${uid}-title`;
  const descriptionId = description ? `${uid}-desc` : undefined;

  useEffect(() => {
    // Where focus was before the dialog opened; closing puts it back.
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const panel = panelRef.current;
    // A child with its own autoFocus has already taken it; do not pull it back.
    const inside = !!panel && panel.contains(document.activeElement);
    if (minimalHeader) {
      if (panel && !inside) panel.focus();
    } else if (autoFocusClose) closeRef.current?.focus();
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, [minimalHeader, autoFocusClose]);

  // aria-modal promises Tab stays in the dialog, so loop it at both ends.
  const trapTab = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key !== "Tab") return;
    // A dialog opened on top of this one keeps its own loop.
    if (event.target instanceof Element && event.target.closest('[role="dialog"]') !== event.currentTarget) return;
    const panel = panelRef.current;
    if (!panel) return;
    const controls = tabbableIn(panel);
    if (!controls.length) {
      event.preventDefault();
      panel.focus();
      return;
    }
    const first = controls[0];
    const last = controls[controls.length - 1];
    const active = document.activeElement;
    const outside = !panel.contains(active);
    const atStart = active === panel || active === first;
    const atEnd = active === last;
    if (event.shiftKey && (atStart || outside)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (atEnd || outside)) {
      event.preventDefault();
      first.focus();
    }
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (
        event.key !== "Escape" ||
        event.defaultPrevented ||
        (event.target instanceof Element &&
          event.target.closest("[data-dialog-popover]")) ||
        document.querySelector("[data-dialog-popover]")
      )
        return;
      event.preventDefault();
      event.stopPropagation();
      onClose();
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [onClose]);

  return (
    <div
      lang={locale}
      className={
        popupHost
          ? "relative w-full"
          : `absolute left-1/2 ${fitViewport ? "top-1/2 -translate-y-1/2" : TOP[size]} ${WIDTH[size]} -translate-x-1/2`
      }
    >
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descriptionId}
        tabIndex={-1}
        onKeyDown={trapTab}
        onMouseDown={(event) => event.stopPropagation()}
        className={`relative isolate flex flex-col overflow-hidden rounded-2xl border border-content/7 shadow-2xl outline-none ${fitViewport ? "max-h-[calc(100dvh-32px)]" : ""} ${className ?? ""}`}
      >
        <GlassBackdrop className="bg-background-base/55" />
        <div className="modal-panel relative z-[1] flex min-h-0 flex-1 flex-col">
          <header
            className={
              minimalHeader
                ? "absolute top-3 right-3 z-[2]"
                : "flex shrink-0 items-start gap-2 px-4 pt-3"
            }
          >
            <div
              className={minimalHeader ? "sr-only" : "min-w-0 flex-1 pt-0.5"}
            >
              <h2
                id={titleId}
                className="text-xl font-medium leading-tight text-content"
              >
                {title}
              </h2>
              {description ? (
                <p
                  id={descriptionId}
                  className="mt-0.5 truncate text-[12px] leading-snug text-content/50"
                >
                  {description}
                </p>
              ) : null}
            </div>
            <button
              ref={closeRef}
              type="button"
              aria-label={t("Close")}
              onClick={onClose}
              disabled={closeDisabled}
              className="grid size-7 shrink-0 place-items-center rounded-md text-content/45 hover:bg-content/8 hover:text-content focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent-ring disabled:cursor-default disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-content/45"
            >
              <X className="size-3.5" strokeWidth={1.75} />
            </button>
          </header>
          <div
            ref={lockOverscroll}
            className="min-h-0 flex-1 overflow-y-auto overscroll-none"
          >
            <InDialog.Provider value>{children}</InDialog.Provider>
          </div>
          {footer ? <div className="shrink-0">{footer}</div> : null}
        </div>
      </div>
    </div>
  );
}

export function Modal(props: Props) {

  const host = useContext(NativePopupHost);
  if (host) return createPortal(<ModalPanel {...props} />, host);
  return createPortal(
    <div className="fixed inset-0" style={{ zIndex: LAYER.dialog }}>
      <div
        className="modal-backdrop absolute inset-0 bg-black/40"
        onMouseDown={props.onClose}
      />
      <ModalPanel {...props} />
    </div>,
    document.body,
  );
}
