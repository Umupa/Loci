import { dismissUpdatePrompt, installPendingUpdate, useUpdates } from "../model/updates";
import { UpdateDialog } from "./UpdateDialog";

/** The update prompt, when a check or the rail badge opened it. */
export function UpdatePrompt() {
  const updates = useUpdates();
  if (!updates.promptOpen || !updates.pending) return null;
  return (
    <UpdateDialog
      update={updates.pending}
      progress={updates.progress}
      onLater={dismissUpdatePrompt}
      onInstall={() => void installPendingUpdate()}
    />
  );
}
