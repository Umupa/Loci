import { getIdentifier } from "@tauri-apps/api/app";
import { ask, message } from "@tauri-apps/plugin-dialog";
import { relaunch } from "@tauri-apps/plugin-process";
import { check, type Update } from "@tauri-apps/plugin-updater";

/**
 * The installed app. Only it updates itself, from GitHub Releases; Loci Dev
 * (`com.loci.desktop.dev`, every debug build) is built from source and has
 * no updater. Must match `RELEASE_IDENTIFIER` in src-tauri/src/flavor.rs.
 */
export const RELEASE_IDENTIFIER = "com.loci.desktop";

/** Long enough that launch work settles first. */
const FIRST_CHECK_DELAY_MS = 10_000;
const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;

export function updatesItself(identifier: string): boolean {
  return identifier === RELEASE_IDENTIFIER;
}

export async function updatesEnabled(): Promise<boolean> {
  try {
    return updatesItself(await getIdentifier());
  } catch {
    return false;
  }
}

/** The confirmation text: the version, then that release's changelog section. */
export function updatePrompt(update: Pick<Update, "version" | "currentVersion" | "body">): string {
  const notes = update.body?.trim();
  const head = `Loci ${update.version} is available. You have ${update.currentVersion}.`;
  return notes ? `${head}\n\n${notes}` : head;
}

let busy = false;
let declined: string | null = null;

export type UpdateCheckResult = "disabled" | "busy" | "current" | "declined" | "installed";

/**
 * Checks GitHub Releases and, once the user agrees, installs the update and
 * restarts. A quiet check skips a version already declined in this run and
 * keeps errors to the console; an interactive one reports them.
 */
export async function checkForUpdate({ interactive }: { interactive: boolean }): Promise<UpdateCheckResult> {
  if (!(await updatesEnabled())) return "disabled";
  if (busy) return "busy";
  busy = true;
  try {
    const update = await check();
    if (!update) {
      if (interactive) await message("You have the latest version of Loci.", { title: "Loci", kind: "info" });
      return "current";
    }
    if (!interactive && declined === update.version) return "declined";
    const install = await ask(updatePrompt(update), {
      title: "Update Loci",
      kind: "info",
      okLabel: "Install and Restart",
      cancelLabel: "Later",
    });
    if (!install) {
      declined = update.version;
      return "declined";
    }
    await update.downloadAndInstall();
    await relaunch();
    return "installed";
  } catch (error) {
    if (interactive) {
      await message(`Could not check for updates: ${String(error)}`, { title: "Loci", kind: "error" });
    } else {
      console.warn("loci: update check failed", error);
    }
    return "current";
  } finally {
    busy = false;
  }
}

/** Checks a little after launch, then every few hours while Loci is open. */
export function startUpdateChecks(): () => void {
  const run = () => void checkForUpdate({ interactive: false });
  const first = window.setTimeout(run, FIRST_CHECK_DELAY_MS);
  const every = window.setInterval(run, CHECK_INTERVAL_MS);
  return () => {
    window.clearTimeout(first);
    window.clearInterval(every);
  };
}
