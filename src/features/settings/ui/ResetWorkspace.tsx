import { useRef, useState } from "react";
import { ask } from "@tauri-apps/plugin-dialog";
import { t, useLocale } from "../../../shared/i18n/locale";
import { resetWorkspace } from "../model/workspaceReset";

export function ResetWorkspace() {
  useLocale();
  const running = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const reset = async () => {
    if (running.current) return;
    running.current = true;
    setBusy(true);
    setError(null);
    try {
      if (await ask(t("Stop all running agents and permanently delete all conversations, mentors, courses, sources, notes, canvases and reading history from Loci? All settings and global backgrounds are kept. The mentors' folders under ~/Loci and your own files are kept. All windows will reload. This cannot be undone."), {
        title: t("Reset workspace?"), kind: "warning",
        okLabel: t("Reset workspace"), cancelLabel: t("Cancel"),
      })) await resetWorkspace();
    } catch (reason) {
      setError(t("Could not reset workspace: {0}", String(reason)));
    } finally {
      running.current = false;
      setBusy(false);
    }
  };
  return <div className="py-3">
    <p className="mb-3 text-[12px] text-content/50">{t("Delete all mentors, conversations, courses, sources, notes, canvases and reading history. All settings are kept. This cannot be undone.")}</p>
    <button type="button" disabled={busy} onClick={() => void reset()} className="rounded-lg border border-red-500/30 px-3 py-1.5 text-[12px] text-red-500 hover:bg-red-500/10 disabled:opacity-50">
      {busy ? t("Resetting workspace…") : t("Reset workspace")}
    </button>
    {error && <p role="alert" className="mt-2 text-[12px] text-red-500">{error}</p>}
  </div>;
}
