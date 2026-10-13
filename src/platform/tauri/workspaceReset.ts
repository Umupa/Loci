import { listen } from "@tauri-apps/api/event";
import { invoke, suspendWorkspaceInvokes } from "./core";
import { clearWorkspaceStorage } from "../../features/settings/model/workspaceReset";
import { t } from "../../shared/i18n/locale";

const RESET_HASH = "#workspace-reset";
type ResetStatus = { id: string; phase: string; error: string | null };

function showStatus(text: string, failed = false) {
  document.getElementById("boot-splash")?.remove();
  let overlay = document.getElementById("workspace-reset-status");
  if (!overlay) {
    overlay = document.createElement("div");
    overlay.id = "workspace-reset-status";
    overlay.style.cssText = "position:fixed;inset:0;z-index:2147483647;display:grid;place-content:center;padding:48px;background:#18181b;color:#fafafa;font:14px/1.6 system-ui;white-space:pre-wrap";
    document.body.append(overlay);
  }
  overlay.setAttribute("role", failed ? "alert" : "status");
  overlay.textContent = text;
}

function showFailure(reason: unknown) {
  showStatus(`${t("Could not reset workspace: {0}", String(reason))}\n${t("Restart Loci to finish the reset. Some workspace files may already have been removed. Settings have been kept.")}`, true);
}

let preparing = false;
async function prepareReset() {
  if (preparing) return;
  preparing = true;
  showStatus(t("Resetting workspace…"));
  try {
    let timeout: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([
        suspendWorkspaceInvokes(),
        new Promise<never>((_, reject) => {
          timeout = setTimeout(() => reject(t("A window is still finishing an operation.")), 30_000);
        }),
      ]);
    } finally {
      clearTimeout(timeout);
    }
    // Unload timers, singleton caches and all React effects before acknowledging
    // the barrier. This page must never boot the old workspace again.
    history.replaceState(null, "", RESET_HASH);
    window.location.reload();
  } catch (reason) {
    showFailure(reason);
  }
}

/** Run before importing the workspace, including on a manual webview reload. */
export async function bootWorkspaceReset(): Promise<boolean> {
  await listen("workspace-reset-prepare", () => { void prepareReset(); });
  const status = await invoke<ResetStatus | null>("workspace_reset_status");
  if (!status) {
    if (location.hash === RESET_HASH) history.replaceState(null, "", location.pathname + location.search);
    return preparing;
  }
  if (location.hash !== RESET_HASH) {
    await prepareReset();
    return true;
  }
  showStatus(t("Resetting workspace…"));
  void finishReset(status).catch(showFailure);
  return true;
}

async function finishReset(initial: ResetStatus) {
  await invoke("workspace_reset_ready", { id: initial.id });
  let cleaned = false;
  for (;;) {
    const status = await invoke<ResetStatus | null>("workspace_reset_status");
    if (!status) {
      history.replaceState(null, "", location.pathname + location.search);
      window.location.reload();
      return;
    }
    if (status.phase === "failed") throw new Error(status.error ?? t("Could not reset workspace"));
    if (status.phase === "cleared" && !cleaned) {
      clearWorkspaceStorage(localStorage);
      await invoke("workspace_reset_cleaned", { id: status.id });
      cleaned = true;
    }
    // All pages must clear storage before any of them can boot and write again.
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
