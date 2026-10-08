import { t, useLocale } from "../../../shared/i18n/locale";
import type { ReactNode } from "react";
import { ExternalLink, Folder, RotateCcw } from "../../../shared/ui/icons";
import { copyText } from "../../../platform/tauri/clipboard";
import { openPathWithDefaultApp, revealPath } from "../../../platform/tauri/fs";
import { displayPath } from "../../../shared/lib/paths";

/** What a file pane shows in place of a file it cannot display. */
export function FileCard({ path, cwd, title, detail, icon, onRetry }: {
  path: string;
  cwd: string;
  title: string;
  detail: string;
  icon: ReactNode;
  onRetry?: () => void;
}) {
  useLocale();
  return (
    <div className="grid h-full place-items-center p-6">
      <div className="max-w-md text-center">
        {icon}
        <p className="text-[13px] text-content">{title}</p>
        <p className="mt-1 text-[12px] leading-5 text-content/50">{detail}</p>
        <p className="mt-1 truncate font-mono text-[11px] text-content/35">{displayPath(path, cwd)}</p>
        <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
          {onRetry ? (
            <CardButton onClick={onRetry}>
              <RotateCcw className="size-3" strokeWidth={1.75} />
              {t("Retry")}</CardButton>
          ) : null}
          <CardButton onClick={() => void openPathWithDefaultApp(path).catch(() => {})}>
            <ExternalLink className="size-3" strokeWidth={1.75} />
            {t("Open with default app")}</CardButton>
          <CardButton onClick={() => void revealPath(path).catch(() => {})}>
            <Folder className="size-3" strokeWidth={1.75} />
            {t("Reveal")}</CardButton>
          <CardButton onClick={() => void copyText(path).catch(() => {})}>{t("Copy path")}</CardButton>
        </div>
      </div>
    </div>
  );
}

function CardButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  useLocale();
  return (
    <button type="button" onClick={onClick}
      className="flex h-7 items-center gap-1.5 rounded-md bg-content/10 px-2.5 text-[12px] text-content hover:bg-content/15">
      {children}
    </button>
  );
}

/** Footer control shared by the image and PDF viewers. */
export function FooterButton({ label, onClick, disabled, children }: {
  label: string;
  onClick: () => void;
  disabled?: boolean;
  children: ReactNode;
}) {
  useLocale();
  return (
    <button type="button" title={label} aria-label={label} disabled={disabled} onClick={onClick}
      className="grid size-5 place-items-center rounded hover:bg-content/10 hover:text-content disabled:opacity-35 disabled:hover:bg-transparent">
      {children}
    </button>
  );
}
