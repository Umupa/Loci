import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { ask, type HostPickOptions } from "../../platform/dialog";
import { homeDir, listDir, statFiles, type FsEntry } from "../../platform/tauri/fs";
import { joinPath, parentPath, slash } from "../../shared/lib/paths";
import { Modal } from "../../shared/ui/Modal";

type Props = HostPickOptions & { onDone: (paths: string[] | null) => void };

const extensionOf = (name: string) => name.includes(".") ? name.split(".").pop()!.toLowerCase() : "";

/** Where the browser opens, and the file name a save starts with. */
export function startingPlace(defaultPath: string | undefined, mode: HostPickOptions["mode"], home: string): { dir: string; name: string } {
  if (!defaultPath) return { dir: home, name: "" };
  const path = slash(defaultPath);
  if (mode === "save") return { dir: parentPath(path), name: path.slice(path.lastIndexOf("/") + 1) };
  // An open may name a folder, or a file in the folder to show.
  return { dir: /\.[^/]+$/.test(path) ? parentPath(path) : path, name: "" };
}

/**
 * Picks files or folders on the host, for a window connected to it: the
 * system's picker would show this device's disk. Folders open with a click;
 * files are chosen, several when `multiple`.
 */
export function HostFileDialog({ mode, title, directory = false, multiple = false, filters, defaultPath, onDone }: Props) {
  const [dir, setDir] = useState<string | null>(null);
  const [typed, setTyped] = useState("");
  const [entries, setEntries] = useState<FsEntry[] | null>(null);
  const [chosen, setChosen] = useState<string[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const extensions = new Set(filters?.flatMap((filter) => filter.extensions.map((ext) => ext.toLowerCase())) ?? []);

  useEffect(() => {
    void homeDir().catch(() => "/").then((home) => {
      const start = startingPlace(defaultPath, mode, home);
      setDir(start.dir);
      setName(start.name);
    });
  }, [defaultPath, mode]);

  useEffect(() => {
    if (!dir) return;
    let current = true;
    setTyped(dir);
    setEntries(null);
    setChosen([]);
    setError(null);
    void listDir(dir).then(
      (list) => { if (current) setEntries(list.filter((entry) => !entry.hidden)); },
      (reason) => { if (current) { setEntries([]); setError(String(reason)); } },
    );
    return () => { current = false; };
  }, [dir]);

  const shown = entries?.filter((entry) => entry.isDir || (!directory && (!extensions.size || extensions.has(extensionOf(entry.name))))) ?? [];
  const pickFile = (path: string) => {
    if (mode === "save") { setName(path.slice(path.lastIndexOf("/") + 1)); return; }
    setChosen((current) => multiple
      ? current.includes(path) ? current.filter((entry) => entry !== path) : [...current, path]
      : [path]);
  };

  const confirm = async () => {
    if (!dir) return;
    if (mode === "save") {
      const target = joinPath(dir, name.trim());
      const [existing] = await statFiles([target]).catch(() => []);
      if (existing?.mtimeMs != null && !await ask(`Replace “${name.trim()}” on the host?`, { title: "Replace file", kind: "warning", okLabel: "Replace", cancelLabel: "Cancel" })) return;
      onDone([target]);
      return;
    }
    onDone(directory ? [dir] : chosen);
  };
  const canConfirm = mode === "save" ? !!name.trim() : directory || chosen.length > 0;
  const confirmLabel = mode === "save" ? "Save" : directory ? "Choose this folder" : "Open";

  return <Modal title={title ?? (mode === "save" ? "Save on the host" : "Choose on the host")} onClose={() => onDone(null)} size="md"
    footer={<div className="flex items-center justify-end gap-2 p-3">
      <button type="button" className="rounded-md px-3 py-1.5 text-sm hover:bg-content/8" onClick={() => onDone(null)}>Cancel</button>
      <button type="button" className="primary-action rounded-md px-3 py-1.5 text-sm font-medium disabled:opacity-50" disabled={!canConfirm} onClick={() => void confirm()}>{confirmLabel}</button>
    </div>}>
    <div className="flex flex-col gap-2 p-3" data-host-file-dialog>
      <form className="flex items-center gap-2" onSubmit={(event) => { event.preventDefault(); if (typed.trim()) setDir(slash(typed.trim())); }}>
        <button type="button" className="rounded-md px-2 py-1 text-sm hover:bg-content/8 disabled:opacity-40" aria-label="Up one folder"
          disabled={!dir || parentPath(dir) === dir} onClick={() => dir && setDir(parentPath(dir))}>↑</button>
        <input aria-label="Folder on the host" className="min-w-0 flex-1 rounded-md border border-stroke bg-transparent px-2 py-1 text-sm" value={typed} onChange={(event) => setTyped(event.target.value)} />
      </form>
      <ul role="listbox" aria-multiselectable={multiple} className="h-72 overflow-auto rounded-md border border-stroke text-sm">
        {entries === null ? <li className="p-2 text-content/60" role="status">Reading the folder…</li> : null}
        {error ? <li className="p-2 text-content/60" role="alert">{error}</li> : null}
        {entries && !error && !shown.length ? <li className="p-2 text-content/60">Nothing here.</li> : null}
        {shown.map((entry) => <li key={entry.path} role="option" aria-selected={chosen.includes(entry.path)}>
          <button type="button" className={`flex w-full items-center gap-2 px-2 py-1 text-left hover:bg-content/8 ${chosen.includes(entry.path) ? "bg-content/10" : ""}`}
            onClick={() => entry.isDir ? setDir(entry.path) : pickFile(entry.path)}>
            <span aria-hidden className="w-4 text-content/50">{entry.isDir ? "▸" : ""}</span>
            <span className="truncate">{entry.name}</span>
          </button>
        </li>)}
      </ul>
      {mode === "save" ? <label className="flex items-center gap-2 text-sm">
        <span className="text-content/60">Name</span>
        <input aria-label="File name" className="min-w-0 flex-1 rounded-md border border-stroke bg-transparent px-2 py-1" value={name} onChange={(event) => setName(event.target.value)} />
      </label> : null}
    </div>
  </Modal>;
}

/** Shows the host's file browser over the window until something is chosen or it is closed. */
export function pickOnHost(options: HostPickOptions): Promise<string[] | null> {
  return new Promise((resolve) => {
    const container = document.createElement("div");
    document.body.append(container);
    const root = createRoot(container);
    const done = (paths: string[] | null) => {
      root.unmount();
      container.remove();
      resolve(paths?.length ? paths : null);
    };
    root.render(<HostFileDialog {...options} onDone={done} />);
  });
}
