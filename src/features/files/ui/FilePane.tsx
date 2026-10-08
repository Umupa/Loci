import { memo, useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { CircleAlert, ExternalLink, Folder, GripVertical, MessageSquarePlus, Pin, X } from "../../../shared/ui/icons";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { basename, openPathWithDefaultApp, readBinaryFile, readDocumentFile, readTextFile, revealPath, writeTextFile } from "../../../platform/tauri/fs";
import { IS_MAC } from "../../../platform/tauri/platform";
import { formatFileSize, sniffImageMime } from "../../../shared/lib/filePreview";
import { displayPath, parentPath } from "../../../shared/lib/paths";
import { lazySurface } from "../../../shared/ui/lazySurface";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { TranscriptSelectionMenu } from "../../sessions/ui/TranscriptSelectionMenu";
import { fileReference, selectionLines, selectionReference, type SelectionPlace } from "../model/fileReference";
import { useFileSelection } from "../hooks/useFileSelection";
import { MarkdownDocumentPreview } from "../../sessions/ui/MarkdownDocumentPreview";
import { fileKind } from "../model/fileKind";
import { syncWatchedMtime, watchFile } from "../model/fileWatch";
import { draftConflicts, editDraft, getFileDraft, setFileDraft, type FileDraft } from "../model/fileDrafts";
import { consumeFilePlace, lineOffset, lineRange, textareaOffsetTop, useFilePlace } from "../model/filePlace";
import { MarkdownModeToggle, useMarkdownMode } from "../../sessions/ui/MarkdownModeToggle";
import { FileCard } from "./FileCard";
import { ImageView } from "./ImageView";

// pdf.js is large and only needed once a PDF is actually opened.
const PdfView = lazySurface(async () => ({ default: (await import("./PdfView")).PdfView }));

type Props = {
  path: string;
  cwd: string;
  /** Opened by a single click: the next file opened replaces this pane. */
  preview: boolean;
  focused: boolean;
  onFocus: () => void;
  onPin: () => void;
  onClose: () => void;
  onOpenFile: (path: string) => void;
  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
};

type Content =
  | { status: "loading" }
  | { status: "text"; text: string }
  | { status: "image"; url: string; mime: string; size: number }
  | { status: "pdf"; bytes: Uint8Array }
  | { status: "unsupported"; detail: string }
  | { status: "error"; message: string };

const REVEAL_LABEL = IS_MAC ? "Reveal in Finder" : "Open containing folder";

function FilePaneComponent({ path, cwd, preview, focused, onFocus, onPin, onClose, onOpenFile, onPaneDragStart }: Props) {
  const name = basename(path);
  const kind = fileKind(name);
  const [content, setContent] = useState<Content>({ status: "loading" });
  const [reloadKey, setReloadKey] = useState(0);
  const [mode, setMode] = useMarkdownMode(`file:${path}`);
  const [draft, setDraftState] = useState<FileDraft | null>(() => getFileDraft(path));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const setDraft = (next: FileDraft | null) => {
    setFileDraft(path, next);
    setDraftState(next);
  };
  const editable = kind === "markdown" && content.status === "text";
  const diskText = content.status === "text" ? content.text : null;
  const conflict = diskText !== null && draftConflicts(draft, diskText);
  const shownText = draft?.text ?? diskText ?? "";
  const editing = editable && mode === "source";
  const reload = useCallback(() => setReloadKey((value) => value + 1), []);
  const folder = displayPath(parentPath(path), cwd);
  const relative = displayPath(path, cwd);
  const bodyRef = useRef<HTMLDivElement>(null);
  const textRef = useRef<HTMLPreElement>(null);
  const { selection, dismiss } = useFileSelection(bodyRef, (content.status === "text" && !editing) || content.status === "pdf");

  /** Page of a PDF selection, or the lines of a plain-text one; markdown has neither. */
  const placeOf = (range: Range): SelectionPlace => {
    if (content.status === "pdf") {
      const node = range.startContainer;
      const element = node instanceof Element ? node : node.parentElement;
      const page = Number(element?.closest<HTMLElement>("[data-page-number]")?.dataset.pageNumber);
      return page > 0 ? { page } : null;
    }
    const pre = textRef.current;
    if (content.status !== "text" || kind !== "text" || !pre || !pre.contains(range.commonAncestorContainer)) return null;
    const offset = (container: Node, within: number) => {
      const before = document.createRange();
      before.selectNodeContents(pre);
      before.setEnd(container, within);
      return before.toString().length;
    };
    return { lines: selectionLines(content.text, offset(range.startContainer, range.startOffset), offset(range.endContainer, range.endOffset)) };
  };
  const edit = (text: string) => {
    if (diskText === null) return;
    const next = editDraft(draft, diskText, text);
    // The first edit keeps this pane: a preview pane is replaced by the next click.
    if (next && !draft) onPin();
    setDraft(next);
  };
  const save = async () => {
    if (!draft || conflict || saving) return;
    setSaving(true);
    setSaveError(null);
    try {
      await writeTextFile(path, draft.text);
      setContent({ status: "text", text: draft.text });
      setDraft(null);
      void syncWatchedMtime(path);
    } catch (cause) {
      setSaveError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setSaving(false);
    }
  };
  const close = () => {
    if (draft && !window.confirm(`Close “${name}” and discard its unsaved changes?`)) return;
    setDraft(null);
    onClose();
  };
  const addSelection = () => {
    if (!selection) return;
    requestAddToChat(selectionReference(selection.text, relative, placeOf(selection.range)), "plain");
    window.getSelection()?.removeAllRanges();
    dismiss();
  };

  // A new path starts blank; a reload of the same file keeps what is shown
  // until the new content is ready, so an agent's edit does not flash.
  useEffect(() => setContent({ status: "loading" }), [path]);

  useEffect(() => {
    let cancelled = false;
    let created: string | null = null;
    const show = (next: Content) => { if (!cancelled) setContent(next); };
    const fail = (cause: unknown) => show({ status: "error", message: cause instanceof Error ? cause.message : String(cause) });

    if (kind === "pdf") {
      readDocumentFile(path).then((bytes) => show({ status: "pdf", bytes }), fail);
    } else if (kind === "image") {
      readBinaryFile(path).then((bytes) => {
        if (cancelled) return;
        // The blob's MIME comes from the bytes, never the extension, so a file
        // named `.png` that holds markup can't become a same-origin document.
        const mime = sniffImageMime(bytes);
        if (!mime) {
          show({ status: "unsupported", detail: `${formatFileSize(bytes.byteLength)} · not a readable image` });
          return;
        }
        created = URL.createObjectURL(new Blob([bytes], { type: mime }));
        show({ status: "image", url: created, mime, size: bytes.byteLength });
      }, fail);
    } else {
      readTextFile(path).then((text) => show({ status: "text", text }), (cause: unknown) => {
        const message = cause instanceof Error ? cause.message : String(cause);
        // Binary and oversized files are not errors, just not ours to render.
        if (/binary|utf-8|too large/i.test(message)) show({ status: "unsupported", detail: "Loci can’t display this kind of file." });
        else fail(cause);
      });
    }
    return () => {
      cancelled = true;
      // Revoked a tick late so the swap to the next image never shows a gap.
      if (created) { const url = created; window.setTimeout(() => URL.revokeObjectURL(url), 1000); }
    };
  }, [path, kind, reloadKey]);

  useEffect(() => {
    let timer = 0;
    const stop = watchFile(path, () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(reload, 50);
    });
    return () => { window.clearTimeout(timer); stop(); };
  }, [path, reload]);

  // A link to lines of this file. Plain text scrolls to the first line; Markdown has no lines in
  // its preview, so the link shows the source and selects them there.
  const placeRequest = useFilePlace(path);
  const shownPlainText = content.status === "text" && kind !== "markdown" ? content.text : null;
  const areaRef = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    if (!placeRequest || !("lines" in placeRequest.place) || content.status !== "text") return;
    const [first, last] = placeRequest.place.lines;
    if (kind === "markdown") {
      if (mode !== "source") { setMode("source"); return; }
      const area = areaRef.current;
      if (!area) return;
      const [from, to] = lineRange(area.value, first, last);
      area.focus({ preventScroll: true });
      area.setSelectionRange(from, to);
      area.scrollTop = Math.max(0, textareaOffsetTop(area, from) - 24);
      consumeFilePlace(path, placeRequest.token);
      return;
    }
    const pre = textRef.current;
    const node = pre?.firstChild;
    if (shownPlainText === null || !pre || node?.nodeType !== Node.TEXT_NODE) return;
    const range = document.createRange();
    range.setStart(node, Math.min(lineOffset(shownPlainText, first), shownPlainText.length));
    range.collapse(true);
    const scroller = pre.parentElement;
    if (scroller) scroller.scrollTop += range.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 24;
    consumeFilePlace(path, placeRequest.token);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [placeRequest, content.status, kind, mode, shownPlainText, path]);

  let body: ReactNode;
  if (content.status === "loading") {
    body = <div className="grid h-full place-items-center text-[12px] text-content/45">Opening {name}…</div>;
  } else if (content.status === "error") {
    body = <FileCard path={path} cwd={cwd} title={`Couldn’t open ${name}`} detail={content.message}
      icon={<CircleAlert className="mx-auto mb-3 size-5 text-red-400" />} onRetry={reload} />;
  } else if (content.status === "unsupported") {
    body = <FileCard path={path} cwd={cwd} title={name} detail={content.detail}
      icon={<div className="mx-auto mb-3 flex justify-center"><FileTypeIcon name={name} isDir={false} size={28} /></div>} />;
  } else if (content.status === "pdf") {
    body = <PdfView bytes={content.bytes} onError={(message) => setContent({ status: "error", message })}
      place={placeRequest && "page" in placeRequest.place ? { page: placeRequest.place.page, token: placeRequest.token } : undefined}
      onPlaced={() => { if (placeRequest) consumeFilePlace(path, placeRequest.token); }} />;
  } else if (content.status === "image") {
    body = <ImageView url={content.url} size={content.size} mime={content.mime} />;
  } else if (kind === "markdown") {
    body = editing ? (
      <textarea
        ref={areaRef}
        aria-label={`Edit ${name}`}
        value={shownText}
        spellCheck={false}
        onChange={(event) => edit(event.target.value)}
        className="block h-full w-full resize-none overflow-auto overscroll-none bg-transparent px-5 py-4 font-mono text-[12.5px] leading-[1.55] text-content/90 outline-none"
      />
    ) : (
      <MarkdownDocumentPreview text={shownText} metadataLabel="Front matter" cwd={parentPath(path)} onOpenFile={onOpenFile} />
    );
  } else {
    body = (
      <div className="h-full overflow-auto overscroll-none">
        <pre ref={textRef} className="min-h-full select-text whitespace-pre-wrap break-words px-5 py-4 font-mono text-[12.5px] leading-[1.55] text-content/90">{content.text}</pre>
      </div>
    );
  }

  return (
    <div className="flex h-full min-h-0 min-w-0 flex-col text-content" onPointerDown={() => { if (!focused) onFocus(); }}
      onKeyDown={(event) => {
        if (!(event.metaKey || event.ctrlKey) || event.altKey || event.shiftKey || event.key.toLowerCase() !== "s") return;
        event.preventDefault();
        void save();
      }}>
      <div className={`flex h-9 shrink-0 select-none items-center gap-1.5 border-b border-stroke px-2 ${onPaneDragStart ? "cursor-grab active:cursor-grabbing touch-none" : ""}`}
        onPointerDown={(event) => {
          if (!(event.target as HTMLElement).closest("[data-no-drag]")) onPaneDragStart?.(event);
        }}
        onDoubleClick={(event) => {
          if (preview && !(event.target as HTMLElement).closest("[data-no-drag]")) onPin();
        }}>
        {onPaneDragStart ? <GripVertical className="size-3.5 shrink-0 text-content/35" /> : null}
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        <span className="shrink-0"><FileTypeIcon name={name} isDir={false} /></span>
        <span className={`min-w-0 shrink truncate text-xs ${preview ? "italic" : ""}`} title={preview ? `${path}\nPreview — double-click to keep this pane` : path}>{name}</span>
        {draft ? <span aria-label="Unsaved changes" title="Unsaved changes" className="size-1.5 shrink-0 rounded-full bg-content/60" /> : null}
        {folder && folder !== "." ? <span className="min-w-0 flex-1 truncate text-[11px] text-content/40">{folder}</span> : <span className="flex-1" />}
        {editable ? <div data-no-drag className="shrink-0"><MarkdownModeToggle mode={mode} onChange={setMode} /></div> : null}
        {draft ? (
          <button type="button" data-no-drag disabled={conflict || saving} onClick={() => void save()} title={conflict ? "Resolve the conflict first" : "Save (Ctrl/Cmd+S)"}
            className="h-6 shrink-0 rounded px-2 text-[11px] text-content hover:bg-content/10 disabled:opacity-40">{saving ? "Saving…" : "Save"}</button>
        ) : null}
        {preview ? <PaneButton label="Keep open" onClick={onPin}><Pin className="size-3.5" /></PaneButton> : null}
        <PaneButton label="Add file to chat" onClick={() => requestAddToChat(fileReference(relative), "plain")}><MessageSquarePlus className="size-3.5" /></PaneButton>
        <PaneButton label="Open with default app" onClick={() => void openPathWithDefaultApp(path).catch(() => {})}><ExternalLink className="size-3.5" /></PaneButton>
        <PaneButton label={REVEAL_LABEL} onClick={() => void revealPath(path).catch(() => {})}><Folder className="size-3.5" /></PaneButton>
        <button type="button" data-no-drag aria-label="Close pane" title="Close pane" onClick={close}
          className="grid size-5 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"><X className="size-3" /></button>
      </div>
      {conflict && draft ? (
        <Banner tone="warn" message="This file changed on disk while you were editing.">
          <BannerButton onClick={() => setDraft({ ...draft, base: diskText ?? draft.base })}>Keep my version</BannerButton>
          <BannerButton onClick={() => setDraft(null)}>Load disk version</BannerButton>
        </Banner>
      ) : null}
      {saveError ? <Banner tone="error" message={`Couldn’t save: ${saveError}`}><BannerButton onClick={() => void save()}>Retry</BannerButton></Banner> : null}
      <div ref={bodyRef} className="min-h-0 min-w-0 flex-1">{body}</div>
      <TranscriptSelectionMenu selection={selection} onAddToChat={addSelection} onDismiss={dismiss} />
    </div>
  );
}

function Banner({ tone, message, children }: { tone: "warn" | "error"; message: string; children: ReactNode }) {
  return (
    <div role="status" className={`flex shrink-0 flex-wrap items-center gap-2 border-b border-stroke px-3 py-1.5 text-[12px] ${tone === "error" ? "text-red-400" : "text-amber-400"}`}>
      <span className="min-w-0 flex-1">{message}</span>
      {children}
    </div>
  );
}

function BannerButton({ onClick, children }: { onClick: () => void; children: ReactNode }) {
  return <button type="button" onClick={onClick} className="h-6 shrink-0 rounded-md bg-content/10 px-2 text-[11px] text-content hover:bg-content/15">{children}</button>;
}

function PaneButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" data-no-drag aria-label={label} title={label} onClick={onClick}
      className="grid size-6 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content">{children}</button>
  );
}

export const FilePane = memo(FilePaneComponent);
