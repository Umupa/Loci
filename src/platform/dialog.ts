import { open as systemOpen, save as systemSave } from "@tauri-apps/plugin-dialog";
import { slash } from "../shared/lib/paths";

// Every dialog is opened from here. Confirmations are the system's own, on the
// device showing the app. A file picker chooses where the data is: the
// system's picker on this device, or the host's file browser in a window
// connected to another device.
export { ask, open as openOnThisDevice } from "@tauri-apps/plugin-dialog";

export type FileFilter = { name: string; extensions: string[] };
export type HostPickOptions = {
  mode: "open" | "save";
  title?: string;
  directory?: boolean;
  multiple?: boolean;
  filters?: FileFilter[];
  defaultPath?: string;
};
/** Chosen paths on the host, or `null` when cancelled. */
export type HostPicker = (options: HostPickOptions) => Promise<string[] | null>;

let hostPicker: HostPicker | undefined;

/** A window connected to another device picks the host's files with this. */
export function setHostPicker(picker: HostPicker | undefined): void {
  hostPicker = picker;
}

type OpenOptions = Omit<HostPickOptions, "mode">;

/** A file or folder to open: a path, several when `multiple`, or `null`. */
export async function open(options: OpenOptions = {}): Promise<string | string[] | null> {
  if (!hostPicker) return systemOpen(options);
  const chosen = await hostPicker({ mode: "open", ...options });
  return chosen && (options.multiple ? chosen : chosen[0] ?? null);
}

/** Where to save a file, or `null`. */
export async function save(options: Omit<OpenOptions, "directory" | "multiple"> = {}): Promise<string | null> {
  if (!hostPicker) return systemSave(options);
  return (await hostPicker({ mode: "save", ...options }))?.[0] ?? null;
}

/**
 * Folders chosen from the system picker. Multi-select is on, so several
 * projects can be opened in one pass; the dialog still returns a bare string
 * when only one was taken.
 */
export async function pickFolders(title = "Open projects"): Promise<string[]> {
  const selected = await open({
    directory: true,
    multiple: true,
    title,
  });
  if (Array.isArray(selected)) {
    return selected.filter((path) => !!path).map(slash);
  }
  return typeof selected === "string" && selected ? [slash(selected)] : [];
}

/** One folder chosen from the system picker, starting at `defaultPath`. */
export async function pickFolder(title: string, defaultPath?: string): Promise<string | undefined> {
  const selected = await open({
    directory: true,
    multiple: false,
    title,
    ...(defaultPath ? { defaultPath } : {}),
  });
  const path = Array.isArray(selected) ? selected[0] : selected;
  return typeof path === "string" && path ? slash(path) : undefined;
}

/** Where to save a file, from the system's save dialog. */
export async function pickSavePath(title: string, defaultPath: string, extensions: string[]): Promise<string | undefined> {
  const chosen = await save({ title, defaultPath, filters: [{ name: extensions.join(", "), extensions }] });
  return typeof chosen === "string" && chosen ? slash(chosen) : undefined;
}

/** One file of these extensions, from the system picker. */
export async function pickFile(title: string, extensions: string[]): Promise<string | undefined> {
  const selected = await open({ title, multiple: false, directory: false, filters: [{ name: extensions.join(", "), extensions }] });
  const path = Array.isArray(selected) ? selected[0] : selected;
  return typeof path === "string" && path ? slash(path) : undefined;
}

export async function pickFiles(title = "Attach files"): Promise<string[] | null> {
  const selected = await open({
    multiple: true,
    directory: false,
    title,
  });
  if (Array.isArray(selected)) {
    const paths = selected
      .filter((path): path is string => Boolean(path))
      .map(slash);
    return paths.length > 0 ? paths : null;
  }
  if (typeof selected === "string" && selected) return [slash(selected)];
  return null;
}
