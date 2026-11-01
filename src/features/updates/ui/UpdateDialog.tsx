import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useRef } from "react";
import { useUiText } from "../../../shared/i18n/SettingsLanguage";
import { ExternalLink, Loader } from "../../../shared/ui/icons";
import { Modal } from "../../../shared/ui/Modal";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { releaseNotesUrl, type InstallProgress, type PendingUpdate } from "../model/updates";

type Props = {
  update: PendingUpdate;
  progress: InstallProgress;
  onLater: () => void;
  onInstall: () => void;
};

/**
 * The in-app update prompt: the release's notes as Markdown in a scrolling
 * area, with the actions pinned below them so a long changelog can never push
 * them off the window. Return installs; Esc, ✕ and the backdrop are Later.
 */
export function UpdateDialog({ update, progress, onLater, onInstall }: Props) {
  const { t } = useUiText();
  const busy = progress.phase === "downloading" || progress.phase === "installing";
  const primaryRef = useRef<HTMLButtonElement>(null);
  const install = useRef(onInstall);
  install.current = onInstall;

  // The primary button owns the focus, so Return installs from the start. A
  // failure moves focus to Retry, which is then what Return activates.
  const primary = progress.phase === "failed" ? "retry" : "install";
  useEffect(() => {
    primaryRef.current?.focus();
  }, [primary]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Enter" || event.defaultPrevented || event.repeat || busy) return;
      const target = event.target instanceof Element ? event.target : null;
      // Later and the GitHub link keep their own keyboard behaviour.
      if (target?.closest("button, a, input, textarea, select") && target !== primaryRef.current) return;
      event.preventDefault();
      install.current();
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [busy]);

  const openNotes = () => {
    void openUrl(releaseNotesUrl(update.version)).catch((error) => {
      console.error("loci: could not open the release notes", error);
    });
  };

  return (
    <Modal
      title={t("Update Loci")}
      description={t("Loci {0} is available. You have {1}.", update.version, update.currentVersion)}
      size="md"
      fitViewport
      autoFocusClose={false}
      closeDisabled={busy}
      onClose={onLater}
      footer={
        <footer data-update-footer className="border-t border-content/8">
          {progress.phase === "downloading" ? (
            <div data-update-progress className="px-4 pt-3">
              <div
                role="progressbar"
                aria-label={t("Download progress")}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={progress.percent ?? undefined}
                className={`h-1.5 overflow-hidden rounded-full bg-content/10 ${progress.percent == null ? "animate-pulse" : ""}`}
              >
                <div
                  className="h-full rounded-full bg-accent transition-[width] duration-200"
                  style={{ width: progress.percent == null ? "30%" : `${progress.percent}%` }}
                />
              </div>
              <p role="status" className="mt-1.5 text-[12px] text-content/55">
                {progress.percent == null ? t("Downloading…") : t("Downloading… {0}%", progress.percent)}
              </p>
            </div>
          ) : null}

          {progress.phase === "installing" ? (
            <p data-update-progress role="status" className="flex items-center gap-2 px-4 pt-3 text-[12px] text-content/60">
              <Loader className="size-3.5 animate-spin" strokeWidth={1.5} />
              {t("Installing…")}
            </p>
          ) : null}

          {progress.phase === "failed" ? (
            <p data-update-error role="alert" className="px-4 pt-3 text-[12px] leading-relaxed text-red-400">
              {t("Could not install the update: {0}", progress.error)}
            </p>
          ) : null}

          <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3">
            <button
              type="button"
              onClick={openNotes}
              className="flex min-w-0 items-center gap-1.5 rounded-md text-[12px] text-content/50 hover:text-content focus-visible:outline-2 focus-visible:outline-accent-ring"
            >
              <ExternalLink className="size-3.5 shrink-0" strokeWidth={1.5} />
              <span className="truncate">{t("Release notes on GitHub")}</span>
            </button>
            <div className="flex shrink-0 items-center gap-2">
              <SecondaryButton type="button" onClick={onLater} disabled={busy}>
                {t("Later")}
              </SecondaryButton>
              <button
                ref={primaryRef}
                type="button"
                onClick={onInstall}
                disabled={busy}
                className="rounded-md bg-accent px-3 py-1 text-[12px] font-medium text-white hover:opacity-90 focus-visible:outline-2 focus-visible:outline-accent-ring disabled:cursor-default disabled:opacity-50 disabled:hover:opacity-50"
              >
                {progress.phase === "failed" ? t("Retry") : t("Install and Restart")}
              </button>
            </div>
          </div>
        </footer>
      }
    >
      <div className="px-4 py-3" data-update-body>
        {update.notes ? (
          <div
            data-update-notes
            className="max-h-[min(60vh,520px)] overflow-y-auto overscroll-contain rounded-xl border border-content/8 bg-content/3 px-3.5 py-2.5"
          >
            <AgentMarkdown text={update.notes} wholeDocument />
          </div>
        ) : (
          <p className="text-[13px] text-content/55">{t("This release has no notes.")}</p>
        )}
      </div>
    </Modal>
  );
}
