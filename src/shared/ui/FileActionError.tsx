import { useUiText } from "../i18n/SettingsLanguage";
import { LAYER } from "../lib/layers";

export function FileActionError({
  message,
  onDismiss,
}: {
  message: string;
  onDismiss: () => void;
}) {
  const { t } = useUiText();
  return (
    <div
      role="alert"
      className="fixed bottom-4 right-4 flex max-w-sm items-start gap-3 rounded-xl border border-danger/30 bg-content/10 px-3 py-2 text-xs text-danger shadow-xl backdrop-blur-xl"
      style={{ zIndex: LAYER.toast }}
    >
      <span className="min-w-0 break-words">{message}</span>
      <button
        type="button"
        aria-label={t("Dismiss file action error")}
        className="shrink-0 text-content/60 hover:text-content"
        onClick={onDismiss}
      >
        {t("Dismiss")}</button>
    </div>
  );
}
