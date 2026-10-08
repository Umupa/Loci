import { t } from "../../../shared/i18n/locale";
import type { ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { reminderTime } from "../model/sessionReminders";

export function sessionReminderPresets(now = new Date()) {
  const timeInHours = (hours: 1 | 3) => {
    const date = new Date(reminderTime(`reminder:${hours}h`, now)!);
    return `${date.getHours()}:${String(date.getMinutes()).padStart(2, "0")}`;
  };

  return [
    { kind: "item", id: "reminder:1h", label: t("In 1 hour ({0})", timeInHours(1)) },
    {
      kind: "item",
      id: "reminder:3h",
      label: t("In 3 hours ({0})", timeInHours(3)),
    },
    {
      kind: "item",
      id: "reminder:evening",
      label: t("This evening (18:00)"),
      disabled: reminderTime("reminder:evening", now) == null,
    },
    { kind: "item", id: "reminder:tomorrow", label: t("Tomorrow (9:00)") },
    { kind: "item", id: "reminder:next-week", label: t("Next week (Mon 9:00)") },
  ] satisfies ContextMenuItem[];
}
