import { memo, useCallback, useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import { open as chooseFile } from "@tauri-apps/plugin-dialog";
import { CircleAlert, ExternalLink, Folder, MessageSquarePlus, Pencil, Pin, X } from "../../../shared/ui/icons";
import { PaneHeader } from "../../../shared/ui/PaneHeader";
import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { basename, openPathWithDefaultApp, readBinaryFile, readDocumentFile, readTextFile, revealPath, writeTextFile } from "../../../platform/tauri/fs";
import { IS_MAC } from "../../../platform/tauri/platform";
import { formatFileSize, sniffImageMime } from "../../../shared/lib/filePreview";
import { displayPath, parentPath } from "../../../shared/lib/paths";
import { lazySurface } from "../../../shared/ui/lazySurface";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { fileReference, selectionLines, type SelectionPlace } from "../model/fileReference";
import { ReadingSelectionMenu, type ChatIntent } from "../../learning/ui/ReadingSelectionMenu";
import { chatDraft, useReadingMarks, type MarkSpec } from "../../learning/ui/useReadingMarks";
import { describeRange, quoteInText, rangeAt, textIndex } from "../../learning/model/textAnchor";
import { flashRange } from "../../learning/ui/useTextHighlights";

/** A quoted passage in rendered text, where it best fits. */
function quoteRange(root: HTMLElement, quote: string): Range | null {
  const index = textIndex(root);
  const found = quoteInText(index.text, quote);
  return found ? rangeAt(index, found.start, found.end) : null;
}
import type { FileSelection } from "../hooks/useFileSelection";
import { useFileSelection } from "../hooks/useFileSelection";
import { MarkdownDocumentPreview } from "../../sessions/ui/MarkdownDocumentPreview";
import { fileKind } from "../model/fileKind";
import { syncWatchedMtime, watchFile } from "../model/fileWatch";
import { draftConflicts, editDraft, getFileDraft, setFileDraft, type FileDraft } from "../model/fileDrafts";
import { type OpenFileFn, consumeFilePlace, findHeading, headingAbove, lineOffset, lineRange, requestFilePlace, textareaOffsetTop, useFilePlace } from "../model/filePlace";
import { MarkdownModeToggle, useMarkdownMode } from "../../sessions/ui/MarkdownModeToggle";
import { FileCard } from "./FileCard";
import { ImageView } from "./ImageView";
import type { LoadedPdf } from "./PdfView";
import type { PdfAnnotation, ReadingDocument } from "../../learning/model/types";
import { createPdfAnnotation, pdfSelectionAnchors, pdfSelectionSource } from "../../learning/model/pdfAnnotations";
import { deletePdfAnnotation, getReadingDocumentByPath, listPdfAnnotations, registerLearningSource, registerReadingDocument, relocateReadingDocument, subscribeLearningChanges, upsertPdfAnnotation } from "../../learning/model/learningStore";
import { AnnotationList, AnnotationPopover } from "../../learning/ui/PdfAnnotations";

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
  onOpenFile: OpenFileFn;
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
  const [readingDocument, setReadingDocument] = useState<ReadingDocument | null>(null);
  const [annotations, setAnnotations] = useState<PdfAnnotation[]>([]);
  const [annotationsLoaded, setAnnotationsLoaded] = useState(false);
  const [annotationsOpen, setAnnotationsOpen] = useState(false);
  const [annotationError, setAnnotationError] = useState<string | null>(null);
  const [openAnnotation, setOpenAnnotation] = useState<{ id: string; rect: DOMRect; note?: boolean } | null>(null);
  const [relocating, setRelocating] = useState(false);
  const currentPath = useRef(path);
  currentPath.current = path;
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
  const markdownRef = useRef<HTMLDivElement>(null);
  const { selection, dismiss } = useFileSelection(bodyRef, (content.status === "text" && !editing) || content.status === "pdf");
  // Text and Markdown keep highlights on the file; a PDF keeps its own, on page rectangles.
  const placeOfRef = useRef<(range: Range) => SelectionPlace>(() => null);
  const textMarks = useMemo((): MarkSpec => ({
    target: { kind: "file", path },
    source: (anchor, quote, annotationId) => ({ id: crypto.randomUUID(), kind: "file", path, title: name, quote,
      ...(anchor.lines ? { lines: anchor.lines } : {}), anchor, ...(annotationId ? { annotationId } : {}) }),
    lines: (range) => { const place = placeOfRef.current(range); return place && "lines" in place ? place.lines : undefined; },
  }), [path, name]);
  const marks = useReadingMarks(kind === "markdown" ? markdownRef : textRef, textMarks, { enabled: content.status === "text" && !editing });

  useEffect(() => {
    setReadingDocument(null); setAnnotations([]); setAnnotationsLoaded(false); setOpenAnnotation(null); setAnnotationError(null);
    if (kind !== "pdf") return;
    let cancelled = false;
    void getReadingDocumentByPath(path).then((found) => { if (!cancelled) setReadingDocument(found); }).catch(() => {});
    return () => { cancelled = true; };
  }, [path, kind]);

  const documentId = readingDocument?.id;
  useEffect(() => {
    if (!documentId) return;
    setAnnotations([]);
    let cancelled = false;
    const refresh = () => {
      setAnnotationsLoaded(false);
      void listPdfAnnotations(documentId).then((marks) => {
        if (!cancelled) { setAnnotations(marks); setAnnotationsLoaded(true); setAnnotationError(null); }
      }).catch((cause) => { if (!cancelled) setAnnotationError(String(cause)); });
    };
    refresh();
    const unsubscribe = subscribeLearningChanges(refresh);
    return () => { cancelled = true; unsubscribe(); };
  }, [documentId]);

  const onPdfDocument = useCallback((loaded: LoadedPdf) => {
    void registerReadingDocument(path, loaded.fingerprint, name).then((registered) => {
      if (currentPath.current === path) setReadingDocument(registered);
    }).catch((cause) => { if (currentPath.current === path) setAnnotationError(`Couldn’t load annotations: ${String(cause)}`); });
  }, [path, name]);

  const selectionDetails = () => {
    if (!selection || !readingDocument || !bodyRef.current) throw new Error("The PDF is still opening. Try selecting the passage again.");
    const anchors = pdfSelectionAnchors(bodyRef.current, selection.range);
    if (!anchors.length) throw new Error("This selection has no readable PDF text. Image-only pages aren’t supported yet.");
    return { document: readingDocument, quote: selection.text, anchors };
  };
  const pdfToChat = async (passage: FileSelection, intent: ChatIntent, current: () => boolean) => {
    const details = selectionDetails();
    const source = pdfSelectionSource(details.document, details.quote, details.anchors);
    await registerLearningSource(source);
    if (!current()) return;
    const [text] = chatDraft(intent, passage.text, source);
    requestAddToChat(text, "plain", { sources: [source] });
  };
  const highlightPdfSelection = async (passage: FileSelection, note: boolean) => {
    const details = selectionDetails();
    // The words too, so the mark can be found by them as well as by its rectangles.
    const anchor = bodyRef.current ? describeRange(bodyRef.current, passage.range) : null;
    const created = createPdfAnnotation(details.document, details.quote, details.anchors);
    const annotation = await upsertPdfAnnotation(anchor ? { ...created, anchor } : created);
    setAnnotations((current) => [...current.filter((entry) => entry.id !== annotation.id), annotation]);
    setOpenAnnotation({ id: annotation.id, rect: passage.rect, note });
    onPin();
  };
  const askAnnotation = (annotation: PdfAnnotation) => {
    requestAddToChat(annotation.note ? `Explain this passage.\n\nMy note: ${annotation.note}` : "Explain this passage.", "plain", { sources: [annotation.source] });
    setOpenAnnotation(null);
  };
  const saveAnnotation = async (annotation: PdfAnnotation, note: string) => {
    const updated = await upsertPdfAnnotation({ ...annotation, note, updatedAt: Date.now() });
    setAnnotations((current) => current.map((entry) => entry.id === updated.id ? updated : entry));
  };
  const removeAnnotation = async (annotation: PdfAnnotation) => {
    await deletePdfAnnotation(annotation.id);
    setAnnotations((current) => current.filter((entry) => entry.id !== annotation.id));
  };
  const selectAnnotation = (annotation: PdfAnnotation) => {
    requestFilePlace(path, { page: annotation.anchors[0]?.page ?? 1, annotationId: annotation.id });
  };
  const relocatePdf = async () => {
    if (!readingDocument || relocating) return;
    setRelocating(true); setAnnotationError(null);
    try {
      const selected = await chooseFile({ multiple: false, title: `Locate ${name}`, filters: [{ name: "PDF documents", extensions: ["pdf"] }] });
      if (typeof selected !== "string") return;
      const bytes = await readDocumentFile(selected);
      const { readPdfFingerprint } = await import("./PdfView");
      const fingerprint = await readPdfFingerprint(bytes);
      await relocateReadingDocument(readingDocument.id, selected, fingerprint);
      onOpenFile(selected);
    } catch (cause) { setAnnotationError(`Couldn’t locate this PDF: ${cause instanceof Error ? cause.message : String(cause)}`); }
    finally { setRelocating(false); }
  };

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
  placeOfRef.current = placeOf;
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

  // A link to lines of this file. Plain text scrolls to the first line. Markdown is read in its
  // preview, which has no lines, so the link shows the section they fall in; only a pane that is
  // already showing the source selects the lines there.
  const placeRequest = useFilePlace(path);
  const requestedPdfPlace = placeRequest && "page" in placeRequest.place ? { ...placeRequest.place, token: placeRequest.token } : undefined;
  // A saved source remains navigable after its highlight is deleted. Wait for
  // the listing before deciding whether to open a mark or just its page.
  const pdfPlace = requestedPdfPlace?.annotationId
    ? annotationsLoaded ? { ...requestedPdfPlace, annotationId: annotations.some((entry) => entry.id === requestedPdfPlace.annotationId) ? requestedPdfPlace.annotationId : undefined } : undefined
    : requestedPdfPlace;
  const shownPlainText = content.status === "text" && kind !== "markdown" ? content.text : null;
  const areaRef = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    if (!placeRequest || !("lines" in placeRequest.place) || content.status !== "text") return;
    const [first, last] = placeRequest.place.lines;
    const quote = placeRequest.place.quote;
    if (kind === "markdown" && mode === "source") {
      const area = areaRef.current;
      if (!area) return;
      const [from, to] = lineRange(area.value, first, last);
      area.focus({ preventScroll: true });
      area.setSelectionRange(from, to);
      area.scrollTop = Math.max(0, textareaOffsetTop(area, from) - 24);
      consumeFilePlace(path, placeRequest.token);
      return;
    }
    if (kind === "markdown") {
      const place = headingAbove(shownText, first);
      let timer = 0;
      // The preview may still be laying its blocks out; look again for a moment before settling for the top.
      const show = (tries: number) => {
        const scroller = bodyRef.current?.querySelector<HTMLElement>(".markdown-preview");
        const heading = scroller && place ? findHeading(scroller, place) : null;
        if (place && !heading && tries > 0) { timer = window.setTimeout(() => show(tries - 1), 50); return; }
        if (scroller) scroller.scrollTop = heading ? scroller.scrollTop + heading.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 16 : 0;
        const passage = quote && markdownRef.current ? quoteRange(markdownRef.current, quote) : null;
        if (passage) flashRange(passage);
        consumeFilePlace(path, placeRequest.token);
      };
      show(20);
      return () => window.clearTimeout(timer);
    }
    const pre = textRef.current;
    const node = pre?.firstChild;
    if (shownPlainText === null || !pre || node?.nodeType !== Node.TEXT_NODE) return;
    const range = document.createRange();
    range.setStart(node, Math.min(lineOffset(shownPlainText, first), shownPlainText.length));
    range.collapse(true);
    const scroller = pre.parentElement;
    if (scroller) scroller.scrollTop += range.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 24;
    // The quoted passage near those lines, else the lines themselves, flashes once.
    const index = textIndex(pre);
    const found = quote ? quoteInText(shownPlainText, quote, lineOffset(shownPlainText, first)) : null;
    const [from, to] = found ? [found.start, found.end] : lineRange(shownPlainText, first, last);
    const passage = rangeAt(index, from, to);
    if (passage) flashRange(passage);
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
    body = <div className="flex h-full min-h-0 min-w-0">
      <div className="min-w-0 flex-1"><PdfView bytes={content.bytes} onError={(message) => setContent({ status: "error", message })}
        onDocument={onPdfDocument} annotations={annotations} selectedAnnotationId={openAnnotation?.id}
        onAnnotationClick={(annotation, rect) => setOpenAnnotation({ id: annotation.id, rect })}
        place={pdfPlace}
        onPlaced={(placed, pageRect) => {
          if (currentPath.current !== path || placeRequest?.token !== placed.token) return;
          const annotation = annotations.find((entry) => entry.id === placed.annotationId);
          const rect = annotation?.anchors.find((anchor) => anchor.page === placed.page)?.rects[0];
          if (annotation && rect) setOpenAnnotation({ id: annotation.id, rect: new DOMRect(pageRect.left + rect.x * pageRect.width, pageRect.top + rect.y * pageRect.height, rect.width * pageRect.width, rect.height * pageRect.height) });
          consumeFilePlace(path, placed.token);
        }} />
      </div>
      {annotationsOpen ? <AnnotationList annotations={annotations} selectedId={openAnnotation?.id} onSelect={selectAnnotation} onClose={() => setAnnotationsOpen(false)} /> : null}
    </div>;
  } else if (content.status === "image") {
    body = <ImageView url={content.url} size={content.size} mime={content.mime} focused={focused} />;
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
      <div ref={markdownRef} className="h-full min-h-0" data-reading-text><MarkdownDocumentPreview text={shownText} metadataLabel="Front matter" cwd={parentPath(path)} onOpenFile={onOpenFile} /></div>
    );
  } else {
    body = (
      <div className="h-full overflow-auto overscroll-none">
        <pre ref={textRef} data-reading-text data-reading-lines-from="1" className="min-h-full select-text whitespace-pre-wrap break-words px-5 py-4 font-mono text-[12.5px] leading-[1.55] text-content/90">{content.text}</pre>
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
      <PaneHeader onPaneDragStart={onPaneDragStart}
        onDoubleClick={(event) => {
          if (event.currentTarget.hasAttribute("data-window-titlebar") && !(event.target as HTMLElement).closest("[data-pane-title]")) return;
          if (preview && !(event.target as HTMLElement).closest("[data-no-drag]")) onPin();
        }}>
        <span className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`} />
        <span className="shrink-0"><FileTypeIcon name={name} isDir={false} /></span>
        <span data-pane-title data-tauri-drag-region="false" className={`min-w-0 shrink truncate text-xs ${preview ? "italic" : ""}`} title={preview ? `${path}\nPreview — double-click to keep this pane` : path}>{name}</span>
        {draft ? <span aria-label="Unsaved changes" title="Unsaved changes" className="size-1.5 shrink-0 rounded-full bg-content/60" /> : null}
        {folder && folder !== "." ? <span className="pane-header-secondary min-w-0 flex-1 truncate text-[11px] text-content/40">{folder}</span> : <span className="flex-1" />}
        {editable ? <div data-no-drag className="shrink-0"><MarkdownModeToggle mode={mode} onChange={setMode} /></div> : null}
        {kind === "pdf" || content.status === "text" ? <PaneButton label="Highlights & notes" onClick={() => setAnnotationsOpen((value) => !value)}><Pencil className="size-3.5" /></PaneButton> : null}
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
      </PaneHeader>
      {conflict && draft ? (
        <Banner tone="warn" message="This file changed on disk while you were editing.">
          <BannerButton onClick={() => setDraft({ ...draft, base: diskText ?? draft.base })}>Keep my version</BannerButton>
          <BannerButton onClick={() => setDraft(null)}>Load disk version</BannerButton>
        </Banner>
      ) : null}
      {saveError ? <Banner tone="error" message={`Couldn’t save: ${saveError}`}><BannerButton onClick={() => void save()}>Retry</BannerButton></Banner> : null}
      {annotationError ? <Banner tone="error" message={annotationError}><BannerButton onClick={() => setAnnotationError(null)}>Dismiss</BannerButton></Banner> : null}
      {kind === "pdf" && content.status === "error" && readingDocument ? <Banner tone="warn" message="This PDF may have moved. Locate the same document to restore its annotations.">
        <BannerButton onClick={() => void relocatePdf()}>{relocating ? "Locating…" : "Locate file"}</BannerButton>
      </Banner> : null}
      {content.status === "text" ? <div className="flex min-h-0 min-w-0 flex-1">
        <div ref={bodyRef} className="min-h-0 min-w-0 flex-1">{body}</div>
        {annotationsOpen ? marks.list(() => setAnnotationsOpen(false)) : null}
      </div> : <div ref={bodyRef} className="min-h-0 min-w-0 flex-1" {...(content.status === "pdf" ? { "data-reading-text": "" } : {})}>{body}</div>}
      {content.status === "pdf"
        ? <ReadingSelectionMenu selection={selection} onDismiss={dismiss} resetKey={`pdf:${path}`} toChat={pdfToChat} onMark={highlightPdfSelection} />
        : <ReadingSelectionMenu selection={selection} onDismiss={dismiss} resetKey={`text:${path}:${diskText?.length ?? 0}`} askLabel={marks.askLabel}
          toChat={marks.toChat} onMark={editing ? undefined : marks.onMark} />}
      {content.status === "text" ? marks.popover : null}
      {content.status === "pdf" && openAnnotation && annotations.find((annotation) => annotation.id === openAnnotation.id) ?
        <AnnotationPopover key={openAnnotation.id} annotation={annotations.find((annotation) => annotation.id === openAnnotation.id)!} anchor={openAnnotation.rect} focusNote={openAnnotation.note}
          onDismiss={() => setOpenAnnotation(null)} onAsk={askAnnotation} onSave={saveAnnotation} onDelete={removeAnnotation} /> : null}
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
