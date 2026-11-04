import { useRef, useState } from "react";
import { ask } from "../../../platform/dialog";
import { t, useLocale } from "../../../shared/i18n/locale";
import { SecondaryButton } from "../../../shared/ui/SecondaryButton";
import { resetWorkspace } from "../model/workspaceReset";
import { Row } from "./SettingsLayout";

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
      if (await ask(t("Stop all running agents and permanently delete all conversations, mentors, courses, sources, notes and reading history from Loci? All settings and global backgrounds are kept. The mentors' folders under ~/Loci and your own files are kept. All windows will reload. This cannot be undone."), {
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
  return <Row label={t("Delete all mentors, conversations, courses, sources, notes and reading history. All settings are kept. This cannot be undone.")}
    status={error ? <span role="alert" className="text-red-400">{error}</span> : null}>
    <SecondaryButton danger disabled={busy} onClick={() => void reset()}>
      {busy ? t("Resetting workspace…") : t("Reset workspace")}
    </SecondaryButton>
  </Row>;
}
