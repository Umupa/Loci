import { t, useLocale, getLocale } from "../../../shared/i18n/locale";
import {
  ChevronDown,
  ChevronRight,
  Eye,
  EyeOff,
  FilePlus,
  FolderOpen,
  FolderPlus,
  FoldVertical,
  Search,
  X,
} from "../../../shared/ui/icons";
import {
  createContext,
  memo,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent as ReactMouseEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";
import {
  leafName,
  validateFileName,
  wellFormedFileName,
  type NameIssue,
} from "../../../shared/lib/fileName";
import { useLockOverscroll } from "../../../shared/hooks/useLockOverscroll";
import {
  createParentOf,
  dirsTouchedByCreate,
  dirsTouchedByMove,
  forgetDir,
  listCachedDir,
  loadExpanded,
  loadSelected,
  notifyDirsChanged,
  peekDir,
  refreshDir,
  saveExpanded,
  saveSelected,
  subscribeDirsChanged,
} from "../model/fileTree";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { dragPointToClient } from "../../../shared/lib/dragPoint";
import {
  basename,
  clipboardFilePaths,
  copyPath,
  createPath,
  movePath,
  openPathWithDefaultApp,
  pickFiles,
  renamePath,
  revealPath,
  trashPath,
  type FsEntry,
} from "../../../platform/tauri/fs";
import { displayPath, parentPath, rebasePath } from "../../../shared/lib/paths";
import { IS_MAC, IS_WIN, MOD, SHIFT } from "../../../platform/tauri/platform";
import {
  emitFilePointerDrag,
  setGrabbing,
  suppressTextSelection,
} from "../../../shared/lib/drag";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { fileReference } from "../model/fileReference";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { MatchText } from "../../../shared/ui/MatchText";
import { findFiles, forgetProjectFiles, loadProjectFiles, type FileMatch } from "../model/fileIndex";
import type { ProjectFile } from "../../../platform/tauri/fs";

/** Open a file in the workspace; `pin` keeps its pane instead of previewing. */
export type OpenFileFn = (path: string, pin?: boolean) => void;

const SHOW_HIDDEN_KEY = "loci.files.showHidden";

type Props = {
  cwd: string;
  /** Display identity for the root when it differs from the physical folder. */
  rootLabel?: string;
  onOpenFile: OpenFileFn;
  onFileMoved?: (from: string, to: string) => void;
  onFileDeleted?: (path: string) => void;
};

type Creating = { id: number; parent: string; isDir: boolean };
type Clip = { mode: "copy" | "cut"; path: string; isDir: boolean };
type MenuTarget = { path: string; isDir: boolean; isRoot: boolean };
type MenuState = { x: number; y: number; target: MenuTarget };

const REVEAL_LABEL = IS_MAC
  ? "Reveal in Finder"
  : IS_WIN
    ? "Reveal in File Explorer"
    : "Open Containing Folder";

type TreeCtxValue = {
  expanded: Set<string>;
  selectedPath: string | null;
  creating: Creating | null;
  renaming: string | null;
  cutPath: string | null;
  dragOverPath: string | null;
  epoch: number;
  showHidden: boolean;
  onToggle: (path: string) => void;
  onSelect: (path: string) => void;
  onEntryPointerDown: (
    entry: { path: string; isDir: boolean },
    event: ReactPointerEvent<HTMLButtonElement>,
  ) => void;
  consumeFileClick: () => boolean;
  onOpenFile: OpenFileFn;
  onCreateCommit: (id: number, raw: string) => Promise<void>;
  onCreateCancel: (id: number) => void;
  onRenameCommit: (path: string, raw: string) => Promise<void>;
  onRenameCancel: () => void;
  onItemContextMenu: (
    entry: { path: string; isDir: boolean },
    e: ReactMouseEvent,
  ) => void;
};

const TreeCtx = createContext<TreeCtxValue | null>(null);

function useTree(): TreeCtxValue {
  useLocale();
  const ctx = useContext(TreeCtx);
  if (!ctx) throw new Error("TreeCtx missing");
  return ctx;
}

function isDirAt(cwd: string, path: string): boolean {
  if (path === cwd) return true;
  return (
    peekDir(parentPath(path))?.find((entry) => entry.path === path)?.isDir ??
    peekDir(path) != null
  );
}

async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const el = document.createElement("textarea");
    el.value = text;
    el.style.position = "fixed";
    el.style.left = "-9999px";
    document.body.appendChild(el);
    el.select();
    document.execCommand("copy");
    el.remove();
  }
}

/** Non-Latin layouts put the local letter in `key`, so fall back to the physical key. */
function shortcutLetter(e: ReactKeyboardEvent): string {
  const key = e.key.toLowerCase();
  if (/^[a-z]$/.test(key)) return key;
  return /^Key[A-Z]$/.test(e.code) ? e.code.slice(3).toLowerCase() : key;
}

function treeMenuItems(target: MenuTarget, clip: Clip | null): ContextMenuItem[] {
  const pasteParent = target.isDir ? target.path : parentPath(target.path);
  const pasteBlocked =
    !!clip?.isDir &&
    (pasteParent === clip.path || pasteParent.startsWith(`${clip.path}/`));
  return [
    ...(target.isDir
      ? []
      : [
          { kind: "item" as const, id: "open", label: t("Open") },
          { kind: "item" as const, id: "open-pinned", label: t("Open in Its Own Pane") },
          { kind: "item" as const, id: "open-default", label: t("Open with Default App") },
          { kind: "sep" as const },
        ]),
    { kind: "item", id: "new-file", label: t("New File") },
    { kind: "item", id: "new-folder", label: t("New Folder") },
    { kind: "sep" },
    {
      kind: "item",
      id: "cut",
      label: t("Cut"),
      shortcut: `${MOD}X`,
      disabled: target.isRoot,
    },
    {
      kind: "item",
      id: "copy",
      label: t("Copy"),
      shortcut: `${MOD}C`,
      disabled: target.isRoot,
    },
    {
      kind: "item",
      id: "paste",
      label: t("Paste"),
      shortcut: `${MOD}V`,
      disabled: pasteBlocked,
    },
    {
      kind: "item",
      id: "duplicate",
      label: t("Duplicate"),
      disabled: target.isRoot,
    },
    { kind: "sep" },
    {
      kind: "item",
      id: "add-to-chat",
      label: t("Add to Chat"),
      disabled: target.isRoot,
    },
    {
      kind: "item",
      id: "copy-path",
      label: t("Copy Path"),
      shortcut: `${MOD}${SHIFT}C`,
    },
    { kind: "item", id: "copy-relative-path", label: t("Copy Relative Path") },
    { kind: "sep" },
    {
      kind: "item",
      id: "rename",
      label: t("Rename"),
      shortcut: "F2",
      disabled: target.isRoot,
    },
    {
      kind: "item",
      id: "delete",
      label: t("Move to Trash"),
      shortcut: "⌫",
      disabled: target.isRoot,
      danger: true,
    },
    { kind: "sep" },
    { kind: "item", id: "reveal", label: REVEAL_LABEL },
  ];
}

// Chat updates rerender the sidebar even when Files is hidden. Keep its tree
// intact unless file-tree props, local state, or subscriptions actually change.
export const FileTree = memo(function FileTree({
  cwd,
  rootLabel,
  onOpenFile,
  onFileMoved,
  onFileDeleted,
}: Props) {
  useLocale();
  const [expanded, setExpanded] = useState(() => loadExpanded(cwd));
  const [selectedPath, setSelectedPath] = useState(() => loadSelected(cwd));
  const [children, setChildren] = useState<FsEntry[] | null>(() =>
    peekDir(cwd),
  );
  const [error, setError] = useState<string | null>(null);
  const [creating, setCreating] = useState<Creating | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  const [clip, setClip] = useState<Clip | null>(null);
  const [menu, setMenu] = useState<MenuState | null>(null);
  const [dragOverPath, setDragOverPath] = useState<string | null>(null);
  const [opError, setOpError] = useState<string | null>(null);
  const [epoch, setEpoch] = useState(0);
  // Whatever changed the folder also outdated its name index.
  const bumpEpoch = () => {
    forgetProjectFiles(cwd);
    setEpoch((n) => n + 1);
  };
  const [showHidden, setShowHidden] = useState(readShowHidden);
  const [query, setQuery] = useState("");
  const [index, setIndex] = useState<ProjectFile[] | null>(null);
  const [activeMatch, setActiveMatch] = useState(0);
  const searching = query.trim().length > 0;
  const matches = useMemo(
    () => (searching && index ? findFiles(index, query) : []),
    [getLocale(), index, query, searching],
  );
  const creatingRef = useRef(creating);
  creatingRef.current = creating;
  const fileDragCleanup = useRef<(() => void) | null>(null);
  const suppressFileClickUntil = useRef(0);
  const rootRef = useRef<HTMLDivElement>(null);
  const lockOverscroll = useLockOverscroll<HTMLDivElement>();
  const name = rootLabel?.trim() || basename(cwd);
  const rootOpen = expanded.has(cwd);

  const toggle = (path: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      saveExpanded(cwd, next);
      return next;
    });
  };

  const onSelect = (path: string) => {
    setSelectedPath(path);
    saveSelected(cwd, path);
  };

  // One gesture serves both drops: onto a folder in this tree to move the
  // entry there, or (files only) onto a workspace pane to open it there.
  const onEntryPointerDown = (
    { path, isDir }: { path: string; isDir: boolean },
    event: ReactPointerEvent<HTMLButtonElement>,
  ) => {
    if (event.button !== 0 || fileDragCleanup.current) return;
    let moveTarget: string | null = null;
    const emit = (detail: Parameters<typeof emitFilePointerDrag>[0]) => {
      if (!isDir) emitFilePointerDrag(detail);
    };
    const trackMoveTarget = () => {
      const over = treeFolderAt(lastX, lastY);
      const blocked =
        !over ||
        over === parentPath(path) ||
        over === path ||
        over.startsWith(`${path}/`);
      moveTarget = blocked ? null : over;
      setDragOverPath(moveTarget);
    };
    const handle = event.currentTarget;
    const pointerId = event.pointerId;
    const startX = event.clientX;
    const startY = event.clientY;
    let lastX = startX;
    let lastY = startY;
    let active = false;
    let restoreSelection: (() => void) | undefined;
    let preview: HTMLDivElement | null = null;

    const movePreview = () => {
      if (!preview) return;
      const edge = 8;
      const grabX = 12;
      const grabY = 13;
      const width = preview.offsetWidth;
      const height = preview.offsetHeight;
      const x = Math.min(
        Math.max(edge, lastX - grabX),
        Math.max(edge, window.innerWidth - width - edge),
      );
      const y = Math.min(
        Math.max(edge, lastY - grabY),
        Math.max(edge, window.innerHeight - height - edge),
      );
      preview.style.transform = `translate3d(${Math.round(x)}px, ${Math.round(
        y,
      )}px, 0)`;
    };

    const createPreview = () => {
      preview = document.createElement("div");
      preview.setAttribute("aria-hidden", "true");
      preview.classList.add("file-drag-preview");

      // Keep the useful identity of the row without dragging its full-width
      // layout, indentation spacer, selection state, or button behavior.
      const icon = handle.children.item(1)?.cloneNode(true);
      const label = handle.children.item(2)?.cloneNode(true);
      if (icon) preview.append(icon);
      if (label) preview.append(label);

      document.body.append(preview);
      movePreview();
    };

    const release = () => {
      delete handle.dataset.fileDragging;
      preview?.remove();
      preview = null;
      document.documentElement.classList.remove("is-file-dragging");
      if (restoreSelection) {
        restoreSelection();
        restoreSelection = undefined;
        setGrabbing(false);
      }
      try {
        if (handle.hasPointerCapture(pointerId))
          handle.releasePointerCapture(pointerId);
      } catch {
        /* already released */
      }
    };

    const reset = () => {
      window.removeEventListener("pointermove", onMove);
      window.removeEventListener("pointerup", onUp);
      window.removeEventListener("pointercancel", onCancel);
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("blur", onCancel);
      release();
      if (active) emit({ type: "end", path });
      setDragOverPath(null);
      fileDragCleanup.current = null;
    };

    const activate = () => {
      active = true;
      onSelect(path);
      restoreSelection = suppressTextSelection();
      setGrabbing(true);
      createPreview();
      document.documentElement.classList.add("is-file-dragging");
      handle.dataset.fileDragging = "true";
      try {
        handle.setPointerCapture(pointerId);
      } catch {
        /* window listeners still track the gesture */
      }
    };

    function onMove(moveEvent: PointerEvent) {
      if (moveEvent.pointerId !== pointerId) return;
      lastX = moveEvent.clientX;
      lastY = moveEvent.clientY;
      if (!active) {
        if (Math.hypot(lastX - startX, lastY - startY) < 5) return;
        activate();
      }
      moveEvent.preventDefault();
      movePreview();
      trackMoveTarget();
      emit({ type: "move", path, x: lastX, y: lastY });
    }

    function finish(commit: boolean, upEvent?: PointerEvent) {
      if (commit && upEvent) onMove(upEvent);
      if (active) {
        suppressFileClickUntil.current = performance.now() + 400;
        const dest = moveTarget;
        if (commit && dest) void run(() => moveInto(path, isDir, dest));
        else if (commit) emit({ type: "drop", path, x: lastX, y: lastY });
      }
      reset();
    }

    function onUp(upEvent: PointerEvent) {
      if (upEvent.pointerId === pointerId) finish(true, upEvent);
    }
    function onCancel() {
      finish(false);
    }
    function onKey(keyEvent: KeyboardEvent) {
      if (keyEvent.key !== "Escape") return;
      keyEvent.preventDefault();
      finish(false);
    }

    fileDragCleanup.current = onCancel;
    window.addEventListener("pointermove", onMove);
    window.addEventListener("pointerup", onUp);
    window.addEventListener("pointercancel", onCancel);
    window.addEventListener("keydown", onKey);
    window.addEventListener("blur", onCancel);
  };

  /** The tree entry under a point, or the project root over empty tree space. */
  const treeEntryAt = (x: number, y: number): string | null => {
    const root = rootRef.current;
    if (!root) return null;
    const el = document.elementFromPoint(x, y);
    if (!el || !root.contains(el)) return null;
    return el.closest<HTMLElement>("[role='treeitem']")?.title ?? cwd;
  };
  const treeFolderAt = (x: number, y: number): string | null => {
    const entry = treeEntryAt(x, y);
    return entry ? createParentOf(cwd, entry) : null;
  };

  const openMatch = (match: FileMatch, pin = false) => {
    const { file } = match;
    onSelect(file.path);
    if (!file.isDir) {
      onOpenFile(file.path, pin);
      return;
    }
    // A folder match leaves search and shows that folder in the tree.
    const open = [cwd, file.path];
    for (let dir = parentPath(file.path); dir.length > cwd.length; dir = parentPath(dir)) open.push(dir);
    expandDirs(open);
    setQuery("");
  };

  const consumeFileClick = () =>
    performance.now() < suppressFileClickUntil.current;

  useEffect(() => () => fileDragCleanup.current?.(), []);

  const expandDirs = (dirs: string[]) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      for (const dir of dirs) next.add(dir);
      saveExpanded(cwd, next);
      return next;
    });
  };

  const refreshTouched = async (touched: string[], forget: string[] = []) => {
    for (const path of forget) forgetDir(path);
    await Promise.all([...new Set(touched)].map((path) => refreshDir(path)));
    bumpEpoch();
  };

  const remapTreePaths = (from: string, to: string) => {
    setExpanded((prev) => {
      const next = new Set<string>();
      for (const path of prev) next.add(rebasePath(path, from, to));
      saveExpanded(cwd, next);
      return next;
    });
    setSelectedPath((prev) => {
      const next = prev ? rebasePath(prev, from, to) : prev;
      saveSelected(cwd, next);
      return next;
    });
    setClip((cur) =>
      cur && (cur.path === from || cur.path.startsWith(`${from}/`))
        ? { ...cur, path: rebasePath(cur.path, from, to) }
        : cur,
    );
  };

  const startCreate = (
    isDir: boolean,
    atPath: string | null = selectedPath,
  ) => {
    const parent = createParentOf(cwd, atPath);
    setRenaming(null);
    expandDirs([cwd, parent]);
    setCreating({ id: Date.now(), parent, isDir });
  };

  const startRename = (path: string) => {
    if (path === cwd) return;
    setCreating(null);
    setMenu(null);
    onSelect(path);
    setRenaming(path);
  };

  const onCreateCancel = (id: number) => {
    setCreating((cur) => (cur?.id === id ? null : cur));
  };

  const onCreateCommit = async (id: number, raw: string) => {
    const session = creatingRef.current;
    if (!session || session.id !== id) return;
    const asFolder = session.isDir || /[/\\]$/.test(raw);
    const fileName = wellFormedFileName(raw);
    const created = await createPath(session.parent, fileName, asFolder);
    const touched = dirsTouchedByCreate(session.parent, fileName);
    await refreshTouched(touched);
    setCreating((cur) => (cur?.id === id ? null : cur));
    expandDirs(touched);
    setSelectedPath(created);
    saveSelected(cwd, created);
    if (!asFolder) onOpenFile(created);
  };

  const onRenameCancel = () => setRenaming(null);

  const onRenameCommit = async (path: string, raw: string) => {
    const fileName = wellFormedFileName(raw);
    if (!fileName || (fileName === basename(path) && !/[/\\]/.test(raw))) {
      setRenaming(null);
      return;
    }
    const next = await renamePath(path, fileName);
    const wasDir = isDirAt(cwd, path);
    const parent = parentPath(path);
    await refreshTouched(
      [...dirsTouchedByCreate(parent, fileName), parent],
      wasDir ? [path] : [],
    );
    setRenaming(null);
    expandDirs(dirsTouchedByCreate(parent, fileName));
    remapTreePaths(path, next);
    onFileMoved?.(path, next);
  };

  const moveInto = async (from: string, isDir: boolean, destParent: string) => {
    const moved = await movePath(from, destParent);
    await refreshTouched(dirsTouchedByMove(from, moved), isDir ? [from] : []);
    remapTreePaths(from, moved);
    expandDirs([destParent]);
    setSelectedPath(moved);
    saveSelected(cwd, moved);
    onFileMoved?.(from, moved);
  };

  const removeEntry = async (path: string) => {
    if (path === cwd) return;
    const isDir = isDirAt(cwd, path);
    const label = basename(path);
    const ok = window.confirm(
      isDir
        ? t("Move folder “{0}” and everything inside it to the Trash?", label)
        : t("Move “{0}” to the Trash?", label),
    );
    if (!ok) return;
    await trashPath(path);
    await refreshTouched([parentPath(path)], isDir ? [path] : []);
    setSelectedPath((prev) => {
      if (!prev || prev === path || prev.startsWith(`${path}/`)) {
        const parent = parentPath(path);
        saveSelected(cwd, parent);
        return parent;
      }
      return prev;
    });
    setClip((cur) =>
      cur && (cur.path === path || cur.path.startsWith(`${path}/`))
        ? null
        : cur,
    );
    onFileDeleted?.(path);
  };

  const copyExternalFiles = async (paths: string[], destParent: string) => {
    let created: string | null = null;
    try {
      for (const from of paths) created = await copyPath(from, destParent);
    } finally {
      if (created) {
        await refreshTouched([destParent]);
        expandDirs([destParent]);
        setSelectedPath(created);
        saveSelected(cwd, created);
      }
    }
  };

  const pasteAt = async (targetPath: string) => {
    const destParent = createParentOf(cwd, targetPath);
    if (!clip) {
      await copyExternalFiles(await clipboardFilePaths(), destParent);
      return;
    }
    if (
      clip.isDir &&
      (destParent === clip.path || destParent.startsWith(`${clip.path}/`))
    ) {
      throw new Error(t("Cannot paste a folder into itself."));
    }
    const from = clip.path;
    const mode = clip.mode;
    const isDir = clip.isDir;
    const created =
      mode === "cut"
        ? await movePath(from, destParent)
        : await copyPath(from, destParent);
    if (mode === "cut") {
      await refreshTouched(
        dirsTouchedByMove(from, created),
        isDir ? [from] : [],
      );
      remapTreePaths(from, created);
      onFileMoved?.(from, created);
      setClip(null);
    } else {
      await refreshTouched([destParent]);
    }
    expandDirs([destParent]);
    setSelectedPath(created);
    saveSelected(cwd, created);
  };

  const duplicateAt = async (path: string) => {
    if (path === cwd) return;
    const destParent = parentPath(path);
    const created = await copyPath(path, destParent);
    await refreshTouched([destParent]);
    setSelectedPath(created);
    saveSelected(cwd, created);
  };

  const run = async (work: () => Promise<void>) => {
    setOpError(null);
    try {
      await work();
    } catch (err: unknown) {
      setOpError(err instanceof Error ? err.message : String(err));
    }
  };

  const dropFiles = (paths: string[], targetPath: string) =>
    run(() => copyExternalFiles(paths, createParentOf(cwd, targetPath)));
  const dropFilesRef = useRef(dropFiles);
  dropFilesRef.current = dropFiles;

  const openMenu = (target: MenuTarget, x: number, y: number) => {
    setCreating(null);
    setRenaming(null);
    onSelect(target.path);
    setMenu({ x, y, target });
  };

  const runAction = async (id: string, target: MenuTarget) => {
    switch (id) {
      case "open":
        onOpenFile(target.path);
        return;
      case "open-pinned":
        onOpenFile(target.path, true);
        return;
      case "open-default":
        await run(() => openPathWithDefaultApp(target.path));
        return;
      case "new-file":
        startCreate(false, target.path);
        return;
      case "new-folder":
        startCreate(true, target.path);
        return;
      case "cut":
        if (target.isRoot) return;
        setClip({ mode: "cut", path: target.path, isDir: target.isDir });
        return;
      case "copy":
        if (target.isRoot) return;
        setClip({ mode: "copy", path: target.path, isDir: target.isDir });
        return;
      case "paste":
        await run(() => pasteAt(target.path));
        return;
      case "duplicate":
        await run(() => duplicateAt(target.path));
        return;
      case "add-to-chat":
        if (target.isRoot) return;
        requestAddToChat(
          fileReference(displayPath(target.path, cwd) + (target.isDir ? "/" : "")),
          "plain",
        );
        return;
      case "copy-path":
        await copyText(target.path);
        return;
      case "copy-relative-path":
        await copyText(displayPath(target.path, cwd));
        return;
      case "rename":
        startRename(target.path);
        return;
      case "delete":
        await run(() => removeEntry(target.path));
        return;
      case "reveal":
        await run(() => revealPath(target.path));
        return;
    }
  };

  const onItemContextMenu = (
    entry: { path: string; isDir: boolean },
    e: ReactMouseEvent,
  ) => {
    e.preventDefault();
    e.stopPropagation();
    openMenu(
      { path: entry.path, isDir: entry.isDir, isRoot: false },
      e.clientX,
      e.clientY,
    );
  };

  const onBackgroundMenu = (e: ReactMouseEvent) => {
    if ((e.target as HTMLElement).closest("input")) return;
    e.preventDefault();
    openMenu({ path: cwd, isDir: true, isRoot: true }, e.clientX, e.clientY);
  };

  const onKeyDown = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    if ((e.target as HTMLElement).closest("input")) return;
    if (
      (e.target as HTMLElement).closest("button") &&
      !(e.target as HTMLElement).closest(
        "[role='treeitem'], [data-explorer-root]",
      )
    ) {
      return;
    }
    const path = selectedPath ?? cwd;
    const isRoot = path === cwd;
    const isDir = isDirAt(cwd, path);
    const mod = e.metaKey || e.ctrlKey;
    const key = shortcutLetter(e);
    if (mod && !e.altKey && e.shiftKey && key === "c") {
      e.preventDefault();
      void copyText(path);
      return;
    }
    if (mod && !e.altKey && !e.shiftKey && key === "c") {
      if (isRoot) return;
      e.preventDefault();
      setClip({ mode: "copy", path, isDir });
      return;
    }
    if (mod && !e.altKey && !e.shiftKey && key === "x") {
      if (isRoot) return;
      e.preventDefault();
      setClip({ mode: "cut", path, isDir });
      return;
    }
    if (mod && !e.altKey && !e.shiftKey && key === "v") {
      e.preventDefault();
      void run(() => pasteAt(path));
      return;
    }
    if (e.key === "F2") {
      e.preventDefault();
      startRename(path);
      return;
    }
    if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      void run(() => removeEntry(path));
      return;
    }
    if (e.key === "Escape" && clip?.mode === "cut") {
      e.preventDefault();
      setClip(null);
    }
  };

  useEffect(() => {
    if (!menu) return;
    const onScroll = () => setMenu(null);
    const scrollParent = rootRef.current?.closest(".overflow-y-auto") ?? window;
    scrollParent.addEventListener("scroll", onScroll, true);
    return () => scrollParent.removeEventListener("scroll", onScroll, true);
  }, [menu]);

  useEffect(() => {
    const treePathAt = (x: number, y: number): string | null => {
      const point = dragPointToClient(x, y);
      return treeEntryAt(point.x, point.y);
    };

    let cancelled = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWebview()
      .onDragDropEvent((event) => {
        if (event.payload.type === "leave") {
          setDragOverPath(null);
          return;
        }
        const { x, y } = event.payload.position;
        const target = treePathAt(x, y);
        if (event.payload.type !== "drop") {
          setDragOverPath(target ? createParentOf(cwd, target) : null);
          return;
        }
        setDragOverPath(null);
        if (target) void dropFilesRef.current(event.payload.paths, target);
      })
      .then((fn) => {
        if (cancelled) fn();
        else unlisten = fn;
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [cwd]);

  useEffect(() => {
    const unsub = subscribeDirsChanged(() => bumpEpoch());
    const onResume = () => {
      if (!document.hidden) notifyDirsChanged();
    };
    window.addEventListener("focus", onResume);
    document.addEventListener("visibilitychange", onResume);
    return () => {
      unsub();
      window.removeEventListener("focus", onResume);
      document.removeEventListener("visibilitychange", onResume);
    };
  }, []);

  // The name index is only walked while the search field is in use, and again
  // whenever the tree learns the folder changed underneath it.
  useEffect(() => {
    if (!searching) return;
    let cancelled = false;
    void loadProjectFiles(cwd)
      .then((files) => {
        if (!cancelled) setIndex(files);
      })
      .catch((err: unknown) => {
        if (!cancelled) setOpError(err instanceof Error ? err.message : String(err));
      });
    return () => {
      cancelled = true;
    };
  }, [cwd, searching, epoch]);

  useEffect(() => setActiveMatch(0), [query]);

  useEffect(() => {
    const hit = peekDir(cwd);
    if (hit) {
      setChildren(hit);
      setError(null);
      return;
    }
    let cancelled = false;
    setChildren(null);
    setError(null);
    void listCachedDir(cwd)
      .then((entries) => {
        if (!cancelled) setChildren(entries);
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
          setChildren([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [cwd, epoch]);

  return (
    <TreeCtx.Provider
      value={{
        expanded,
        selectedPath,
        creating,
        renaming,
        cutPath: clip?.mode === "cut" ? clip.path : null,
        dragOverPath,
        epoch,
        showHidden,
        onToggle: toggle,
        onSelect,
        onEntryPointerDown,
        consumeFileClick,
        onOpenFile,
        onCreateCommit,
        onCreateCancel,
        onRenameCommit,
        onRenameCancel,
        onItemContextMenu,
      }}
    >
      <div
        ref={rootRef}
        tabIndex={-1}
        className="flex h-full min-h-0 flex-col outline-none"
        onKeyDown={onKeyDown}
        onContextMenu={onBackgroundMenu}
      >
        <div
          className="flex h-9 shrink-0 items-center gap-px overflow-visible border-b border-stroke px-2"
          onContextMenu={(e) => e.stopPropagation()}
        >
          <HeaderIcon label={t("New File")} onClick={() => startCreate(false)}>
            <FilePlus className="size-3.5" strokeWidth={1.75} />
          </HeaderIcon>
          <HeaderIcon label={t("New Folder")} onClick={() => startCreate(true)}>
            <FolderPlus className="size-3.5" strokeWidth={1.75} />
          </HeaderIcon>
          <HeaderIcon label={t("Import Files")} onClick={async () => {
            const files = await pickFiles(t("Import files to project"));
            if (files) {
              for (const file of files) {
                try {
                  await copyPath(file, cwd);
                } catch (err) {
                  console.error(t("Failed to import {0}:", file), err);
                }
              }
              notifyDirsChanged();
            }
          }}>
            <FolderOpen className="size-3.5" strokeWidth={1.75} />
          </HeaderIcon>
          <HeaderIcon
            label={t("Collapse All")}
            onClick={() => {
              setCreating(null);
              setRenaming(null);
              const next = new Set([cwd]);
              saveExpanded(cwd, next);
              setExpanded(next);
            }}
          >
            <FoldVertical className="size-3.5" strokeWidth={1.75} />
          </HeaderIcon>
          <HeaderIcon
            label={showHidden ? t("Hide Hidden Files") : t("Show Hidden Files")}
            active={showHidden}
            onClick={() => {
              writeShowHidden(!showHidden);
              setShowHidden(!showHidden);
            }}
          >
            {showHidden ? (
              <Eye className="size-3.5" strokeWidth={1.75} />
            ) : (
              <EyeOff className="size-3.5" strokeWidth={1.75} />
            )}
          </HeaderIcon>
        </div>
        <div
          className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2"
          onContextMenu={(e) => e.stopPropagation()}
        >
          <div className="relative flex h-7 min-w-0 flex-1 items-center">
            <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
            <input
              type="text"
              value={query}
              placeholder={t("Search files...")}
              aria-label={t("Search files by name or path")}
              spellCheck={false}
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={(event) => {
                if (event.nativeEvent.isComposing) return;
                if (event.key === "Escape") {
                  event.preventDefault();
                  event.stopPropagation();
                  setQuery("");
                } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                  event.preventDefault();
                  const step = event.key === "ArrowDown" ? 1 : -1;
                  setActiveMatch((current) =>
                    Math.max(0, Math.min(matches.length - 1, current + step)),
                  );
                } else if (event.key === "Enter") {
                  const hit = matches[activeMatch];
                  if (!hit) return;
                  event.preventDefault();
                  openMatch(hit, event.shiftKey);
                }
              }}
              className="h-full w-full min-w-0 rounded-md bg-transparent py-0 pl-7 pr-6 text-[12px] text-content outline-none placeholder:text-content/35"
            />
            {query ? (
              <button
                type="button"
                aria-label={t("Clear search")}
                title={t("Clear search")}
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => setQuery("")}
                className="absolute right-1 grid size-5 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"
              >
                <X className="size-3" />
              </button>
            ) : null}
          </div>
        </div>
        {searching ? (
          <FileMatches
            matches={matches}
            loading={index === null}
            active={activeMatch}
            lockRef={lockOverscroll}
            onActive={setActiveMatch}
            onOpen={openMatch}
            onContextMenu={onItemContextMenu}
          />
        ) : (
        <>
        <div
          ref={lockOverscroll}
          className="min-h-0 flex-1 overflow-y-auto overscroll-none"
        >
          {opError ? (
            <p className="px-3 py-1 text-[12px] leading-4 text-red-400">
              {opError}
            </p>
          ) : null}
          {rootOpen ? (
            <div role="tree" aria-label={t("{0} files", name)}>
              <TreeChildren
                parent={cwd}
                depth={0}
                entries={children}
                loading={children === null && !error}
                error={error}
              />
            </div>
          ) : null}
        </div>
        </>
        )}
      </div>
      {menu ? (
        <ContextMenu
          x={menu.x}
          y={menu.y}
          ariaLabel={t("File actions")}
          items={treeMenuItems(menu.target, clip)}
          onPick={(id) => {
            const target = menu.target;
            setMenu(null);
            void runAction(id, target);
          }}
          onClose={() => setMenu(null)}
        />
      ) : null}
    </TreeCtx.Provider>
  );
});

function HeaderIcon({
  label,
  onClick,
  active = false,
  children,
}: {
  label: string;
  onClick?: () => void;
  active?: boolean;
  children: ReactNode;
}) {
  useLocale();
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      aria-pressed={active || undefined}
      onMouseDown={(e) => e.preventDefault()}
      onClick={onClick}
      className={`flex h-6 min-w-0 flex-1 items-center justify-center self-center rounded-md ${
        active
          ? "bg-selection text-content"
          : "text-content/50 hover:bg-content/5 hover:text-content"
      }`}
    >
      {children}
    </button>
  );
}

function TreeChildren({
  parent,
  depth,
  entries,
  loading,
  error,
}: {
  parent: string;
  depth: number;
  entries: FsEntry[] | null;
  loading: boolean;
  error: string | null;
}) {
  useLocale();
  const ctx = useTree();
  const creating = ctx.creating;
  const show = creating?.parent === parent;
  const row =
    show && creating ? (
      <NameRow
        key={creating.id}
        depth={depth}
        isDir={creating.isDir}
        siblings={(entries ?? []).map((entry) => entry.name)}
        onCommit={(raw) => ctx.onCreateCommit(creating.id, raw)}
        onCancel={() => ctx.onCreateCancel(creating.id)}
      />
    ) : null;
  const visible = ctx.showHidden
    ? entries
    : entries?.filter((e) => !e.hidden);
  const folders = visible?.filter((e) => e.isDir) ?? [];
  const files = visible?.filter((e) => !e.isDir) ?? [];
  const pad = { paddingLeft: 28 + depth * 12 };

  return (
    <>
      {error ? (
        <p className="truncate pr-2 text-[12px] text-content/50" style={pad}>
          {error}
        </p>
      ) : null}
      {show && ctx.creating?.isDir ? row : null}
      {loading && !error ? (
        <p className="pr-2 text-[12px] text-content/50" style={pad}>
          …
        </p>
      ) : null}
      {folders.map((child) => (
        <TreeNode key={child.path} entry={child} depth={depth} />
      ))}
      {show && ctx.creating && !ctx.creating.isDir ? row : null}
      {files.map((child) => (
        <TreeNode key={child.path} entry={child} depth={depth} />
      ))}
    </>
  );
}

function TreeNode({ entry, depth }: { entry: FsEntry; depth: number }) {
  useLocale();
  const {
    expanded,
    selectedPath,
    renaming,
    cutPath,
    dragOverPath,
    epoch,
    onToggle,
    onSelect,
    onEntryPointerDown,
    consumeFileClick,
    onOpenFile,
    onRenameCommit,
    onRenameCancel,
    onItemContextMenu,
  } = useTree();
  const open = expanded.has(entry.path);
  const [children, setChildren] = useState<FsEntry[] | null>(() =>
    entry.isDir ? peekDir(entry.path) : null,
  );
  const [error, setError] = useState<string | null>(null);
  const selected = selectedPath === entry.path;
  const editing = renaming === entry.path;

  useEffect(() => {
    if (!entry.isDir || !open) return;
    const hit = peekDir(entry.path);
    if (hit) {
      setChildren(hit);
      setError(null);
      return;
    }
    let cancelled = false;
    void listCachedDir(entry.path)
      .then((entries) => {
        if (!cancelled) {
          setChildren(entries);
          setError(null);
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : String(err));
          setChildren([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [entry.isDir, entry.path, open, epoch]);

  const onClick = () => {
    if (consumeFileClick()) return;
    onSelect(entry.path);
    if (entry.isDir) onToggle(entry.path);
    else onOpenFile(entry.path);
  };

  const siblings = (peekDir(parentPath(entry.path)) ?? [])
    .map((child) => child.name)
    .filter((name) => name !== entry.name);

  return (
    <div>
      {editing ? (
        <NameRow
          depth={depth}
          isDir={entry.isDir}
          initial={entry.name}
          selectStem={!entry.isDir}
          siblings={siblings}
          onCommit={(raw) => onRenameCommit(entry.path, raw)}
          onCancel={onRenameCancel}
        />
      ) : (
        <button
          type="button"
          role="treeitem"
          title={entry.path}
          aria-expanded={entry.isDir ? open : undefined}
          onClick={onClick}
          onDoubleClick={() => {
            if (!entry.isDir) onOpenFile(entry.path, true);
          }}
          onPointerDown={(event) => onEntryPointerDown(entry, event)}
          onContextMenu={(e) => onItemContextMenu(entry, e)}
          style={{ paddingLeft: 8 + depth * 12 }}
          className={`flex h-7.5 w-full cursor-default items-center gap-1 pr-2 text-left text-[14px] leading-none data-[file-dragging]:opacity-50 ${
            selected
              ? "bg-selection text-content"
              : "text-content hover:bg-content/5"
          } ${cutPath === entry.path ? "opacity-50" : ""} ${
            dragOverPath === entry.path ? "bg-selection" : ""
          }`}
        >
          <span className="grid size-4 shrink-0 place-items-center text-content/50">
            {entry.isDir ? (
              open ? (
                <ChevronDown className="size-3.5" strokeWidth={1.75} />
              ) : (
                <ChevronRight className="size-3.5" strokeWidth={1.75} />
              )
            ) : null}
          </span>
          <span className="shrink-0">
            <FileTypeIcon name={entry.name} isDir={entry.isDir} isOpen={open} />
          </span>
          <span
            className={`min-w-0 truncate leading-label ${
              entry.hidden ? "text-content/50" : ""
            }`}
          >
            {entry.name}
          </span>
        </button>
      )}
      {entry.isDir && open ? (
        <TreeChildren
          parent={entry.path}
          depth={depth + 1}
          entries={children}
          loading={children === null && !error}
          error={error}
        />
      ) : null}
    </div>
  );
}

function FileMatches({
  matches,
  loading,
  active,
  lockRef,
  onActive,
  onOpen,
  onContextMenu,
}: {
  matches: FileMatch[];
  loading: boolean;
  active: number;
  lockRef: (el: HTMLDivElement | null) => void;
  onActive: (index: number) => void;
  onOpen: (match: FileMatch, pin?: boolean) => void;
  onContextMenu: TreeCtxValue["onItemContextMenu"];
}) {
  useLocale();
  return (
    <div
      ref={lockRef}
      role="listbox"
      aria-label={t("Matching files")}
      className="min-h-0 flex-1 overflow-y-auto overscroll-none"
    >
      {matches.length === 0 ? (
        <p className="px-3 py-2 text-[12px] text-content/50">
          {loading ? "…" : t("No matching files")}
        </p>
      ) : null}
      {matches.map((match, index) => {
        const { file } = match;
        const folder = parentPath(file.relative);
        return (
          <button
            key={file.path}
            type="button"
            role="option"
            aria-selected={index === active}
            title={file.path}
            ref={index === active ? scrollIntoViewIfNeeded : undefined}
            onMouseMove={() => onActive(index)}
            onClick={() => onOpen(match)}
            onDoubleClick={() => onOpen(match, true)}
            onContextMenu={(e) =>
              onContextMenu({ path: file.path, isDir: !!file.isDir }, e)
            }
            className={`flex h-7.5 w-full cursor-default items-center gap-1.5 pl-3 pr-2 text-left text-[14px] leading-none ${
              index === active ? "bg-selection text-content" : "text-content"
            }`}
          >
            <span className="shrink-0">
              <FileTypeIcon name={file.name} isDir={!!file.isDir} />
            </span>
            <span className="shrink-0 truncate leading-label">
              <MatchText text={file.name} positions={match.namePositions} active />
            </span>
            {folder ? (
              <span className="min-w-0 truncate text-[12px] leading-label text-content/45">
                {folder}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}

function scrollIntoViewIfNeeded(el: HTMLElement | null) {
  el?.scrollIntoView({ block: "nearest" });
}

function readShowHidden(): boolean {
  try {
    return localStorage.getItem(SHOW_HIDDEN_KEY) === "1";
  } catch {
    return false;
  }
}

function writeShowHidden(show: boolean) {
  try {
    localStorage.setItem(SHOW_HIDDEN_KEY, show ? "1" : "0");
  } catch {
    /* the toggle still applies for this session */
  }
}

export function NameRow({
  depth,
  isDir,
  initial = "",
  selectStem = false,
  siblings,
  onCommit,
  onCancel,
}: {
  depth: number;
  isDir: boolean;
  initial?: string;
  selectStem?: boolean;
  siblings: string[];
  onCommit: (raw: string) => Promise<void>;
  onCancel: () => void;
}) {
  useLocale();
  const inputRef = useRef<HTMLInputElement>(null);
  const finished = useRef(false);
  const [value, setValue] = useState(initial);
  const [attempted, setAttempted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const issue = validateFileName(value, siblings);
  const leaf = leafName(value);

  useEffect(() => {
    const input = inputRef.current;
    if (!input) return;
    input.focus();
    input.scrollIntoView({ block: "nearest" });
    if (!selectStem) return;
    const dot = initial.lastIndexOf(".");
    if (dot > 0) input.setSelectionRange(0, dot);
    else input.select();
  }, [initial, selectStem]);

  const finish = (success: boolean) => {
    if (finished.current) return;
    if (success) {
      const current = validateFileName(value, siblings);
      if (current && current.severity === "error") {
        setAttempted(true);
        return;
      }
      finished.current = true;
      setBusy(true);
      setSubmitError(null);
      void onCommit(value).catch((err: unknown) => {
        finished.current = false;
        setBusy(false);
        setSubmitError(err instanceof Error ? err.message : String(err));
      });
      return;
    }
    finished.current = true;
    onCancel();
  };

  const showIssue =
    submitError ||
    (issue &&
      (issue.severity === "warning" ||
        (issue.kind !== "empty" && value.length > 0) ||
        (issue.kind === "empty" && attempted)));

  return (
    <div>
      <div
        style={{ paddingLeft: 8 + depth * 12 }}
        className="flex h-7.5 w-full items-center gap-1 bg-content/10 pr-2"
      >
        <span className="grid size-4 shrink-0 place-items-center text-content/50">
          {isDir ? (
            <ChevronRight className="size-3.5" strokeWidth={1.75} />
          ) : null}
        </span>
        <span className="shrink-0">
          <FileTypeIcon name={leaf} isDir={isDir} />
        </span>
        <input
          ref={inputRef}
          value={value}
          disabled={busy}
          spellCheck={false}
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
          aria-label={t("Type file name. Press Enter to confirm or Escape to cancel.")}
          onChange={(e) => {
            setValue(e.target.value);
            setSubmitError(null);
          }}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return;
            if (e.key === "Enter") {
              e.preventDefault();
              e.stopPropagation();
              finish(true);
            } else if (e.key === "Escape") {
              e.preventDefault();
              e.stopPropagation();
              finish(false);
            }
          }}
          onBlur={() => finish(issue === null || issue.severity !== "error")}
          className="h-5 min-w-0 flex-1 rounded-sm bg-content/10 px-1 text-[14px] leading-none text-content outline-none ring-1 ring-accent"
        />
      </div>
      {showIssue ? (
        <NameIssueView depth={depth} issue={issue} fallback={submitError} />
      ) : null}
    </div>
  );
}

function NameIssueView({
  depth,
  issue,
  fallback,
}: {
  depth: number;
  issue: NameIssue | null;
  fallback: string | null;
}) {
  useLocale();
  let body: ReactNode = null;
  if (fallback) {
    body = fallback;
  } else if (issue) {
    switch (issue.kind) {
      case "empty":
        body = t("A file or folder name must be provided.");
        break;
      case "slash":
        body = t("A file or folder name cannot start with a slash.");
        break;
      case "exists":
        body = (
          t("A file or folder “{0}” already exists at this location. Please choose a different name.", issue.name)
        );
        break;
      case "invalid":
        body = (
          t("“{0}” is not a valid file or folder name. Please choose a different name.", issue.name)
        );
        break;
      case "whitespace":
        body =
          t("Leading or trailing whitespace detected in file or folder name.");
        break;
    }
  }
  if (!body) return null;
  const error = Boolean(fallback) || !issue || issue.severity === "error";
  return (
    <p
      className={`pr-2 pb-1 text-[12px] leading-4 ${
        error ? "text-red-400" : "text-amber-400"
      }`}
      style={{ paddingLeft: 28 + depth * 12 }}
    >
      {body}
    </p>
  );
}
