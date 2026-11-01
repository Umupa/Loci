import { useUiText } from "../../../shared/i18n/SettingsLanguage";

/**
 * The unobtrusive sign that a quiet check found a release: a dot on the
 * settings button. It opens the prompt; Settings itself stays one click away.
 */
export function UpdateBadge({ version, onOpen }: { version: string; onOpen: () => void }) {
  const { t } = useUiText();
  const label = t("Update available: Loci {0}", version);
  return (
    <button
      type="button"
      data-update-indicator
      aria-label={label}
      title={label}
      onClick={onOpen}
      className="mentor-rail-update"
    >
      <span aria-hidden="true" className="mentor-rail-update-dot" />
    </button>
  );
}
