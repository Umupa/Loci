import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";
import { defaultValueCtx, Editor, editorViewCtx, editorViewOptionsCtx, rootCtx, serializerCtx } from "@milkdown/kit/core";
import { clipboard } from "@milkdown/kit/plugin/clipboard";
import { history } from "@milkdown/kit/plugin/history";
import { commonmark, imageSchema } from "@milkdown/kit/preset/commonmark";
import { gfm } from "@milkdown/kit/preset/gfm";
import { Plugin, Selection } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import { $prose, $view, getMarkdown, insert, replaceAll } from "@milkdown/kit/utils";
import { useEffect, useImperativeHandle, useRef, type Ref } from "react";
import { readBinaryFile } from "../../../platform/tauri/fs";
import { imageDataUrl } from "../../../shared/lib/filePreview";
import { relativeImagePath } from "../../../shared/lib/markdown/markdownLocalImages";
import { isNoteImagePath } from "../noteImages";
import "./NoteWysiwyg.css";

/*
 * Typora-style editing: the note is written as it reads — `# `, `**`, `- `,
 * `> `, ``` and the rest turn into their shapes as they are typed — and the
 * file on disk stays markdown. The editor only writes markdown back once the
 * text is edited, so opening a note the mentor wrote never reformats it.
 */

export type NoteWysiwygHandle = {
  /** Insert markdown (images, say) where the caret is. */
  insertMarkdown: (markdown: string) => void;
  focus: () => void;
};

const noteAssetSrc = new Map<string, string>();

/** Point an <img> at a picture saved with a note, beside it, or on the web. */
function showImage(img: HTMLImageElement, src: string, imageCwd: string | undefined) {
  const url = src.trim();
  img.dataset.src = url;
  img.removeAttribute("src");
  const set = (next: string) => { if (img.dataset.src === url) img.src = next; };
  if (/^(https:|data:image\/)/i.test(url)) { set(url); return; }
  if (isNoteImagePath(url)) {
    const cached = noteAssetSrc.get(url);
    if (cached) { set(cached); return; }
    void invoke<string>("notes_image_path", { asset: url }).then((path) => {
      const next = convertFileSrc(path);
      noteAssetSrc.set(url, next);
      set(next);
    }).catch(() => undefined);
    return;
  }
  const local = relativeImagePath(url, imageCwd);
  if (local) void readBinaryFile(local).then((bytes) => { const next = imageDataUrl(bytes); if (next) set(next); }).catch(() => undefined);
}

export function NoteWysiwyg({
  value,
  onChange,
  imageCwd,
  autoFocus = false,
  placeholder = "Write something…",
  handle,
}: {
  value: string;
  onChange: (value: string) => void;
  imageCwd?: string;
  autoFocus?: boolean;
  placeholder?: string;
  handle?: Ref<NoteWysiwygHandle>;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<Editor | null>(null);
  // `external` is the markdown last handed in; `normalized` is how the editor
  // writes that same document back (`*` lists become `-`, and so on). Until
  // the text really changes the note keeps its own spelling, so opening or
  // reloading a note never rewrites its file. `emitted` is what the parent
  // last heard, so its echo back through `value` is not taken as news.
  const external = useRef(value);
  const normalized = useRef<string | null>(null);
  const emitted = useRef(value);
  const syncing = useRef(false);
  const latest = useRef({ onChange, imageCwd, placeholder });
  latest.current = { onChange, imageCwd, placeholder };

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    let disposed = false;

    const imageView = $view(imageSchema.node, () => (initial) => {
      const img = document.createElement("img");
      const render = (node: typeof initial) => {
        img.alt = node.attrs.alt ?? "";
        if (node.attrs.title) img.title = node.attrs.title; else img.removeAttribute("title");
        if (img.dataset.src !== node.attrs.src) showImage(img, node.attrs.src ?? "", latest.current.imageCwd);
      };
      render(initial);
      return {
        dom: img,
        update: (node) => { if (node.type !== initial.type) return false; render(node); return true; },
        selectNode: () => img.classList.add("is-selected"),
        deselectNode: () => img.classList.remove("is-selected"),
      };
    });

    const placeholderPlugin = $prose(() => new Plugin({
      props: {
        decorations: (state) => {
          const { doc } = state;
          const first = doc.firstChild;
          if (doc.childCount !== 1 || !first || first.type.name !== "paragraph" || first.content.size > 0) return null;
          return DecorationSet.create(doc, [Decoration.node(0, first.nodeSize, { class: "is-empty", "data-placeholder": latest.current.placeholder })]);
        },
      },
    }));

    // ⌘-click (Ctrl-click) follows a link; a plain click puts the caret in it.
    // A click on a task's box, drawn left of its text, ticks it.
    const linkPlugin = $prose(() => new Plugin({
      props: {
        handleDOMEvents: {
          mousedown: (view, event) => {
            const item = (event.target as HTMLElement | null)?.closest?.('li[data-item-type="task"]');
            if (!item || event.clientX >= item.getBoundingClientRect().left) return false;
            const pos = view.posAtDOM(item, 0) - 1;
            const node = view.state.doc.nodeAt(pos);
            if (!node || node.attrs.checked == null) return false;
            event.preventDefault();
            view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, checked: !node.attrs.checked }));
            return true;
          },
        },
        handleClick: (view, pos, event) => {
          if (!(event.metaKey || event.ctrlKey)) return false;
          const mark = view.state.doc.resolve(pos).marks().find((entry) => entry.type.name === "link");
          const href = mark?.attrs.href as string | undefined;
          if (!href || !/^(https?:|mailto:)/i.test(href)) return false;
          void openUrl(href).catch(() => undefined);
          return true;
        },
      },
    }));

    // Reports every change as it happens (Milkdown's listener waits 200ms,
    // which a note closed straight after typing would lose).
    const changes = $prose((ctx) => new Plugin({
      view: () => ({
        update: (view, previous) => {
          if (view.state.doc.eq(previous.doc)) return;
          const markdown = ctx.get(serializerCtx)(view.state.doc);
          if (syncing.current) { normalized.current = markdown; return; }
          const next = markdown === normalized.current ? external.current : markdown;
          if (next === emitted.current) return;
          emitted.current = next;
          latest.current.onChange(next);
        },
      }),
    }));

    void Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(defaultValueCtx, external.current);
        ctx.update(editorViewOptionsCtx, (options) => ({ ...options, attributes: { class: "note-wysiwyg-content", spellcheck: "false", "aria-label": "Note body" } }));
      })
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(clipboard)
      .use(imageView)
      .use(placeholderPlugin)
      .use(linkPlugin)
      .use(changes)
      .create()
      .then((editor) => {
        if (disposed) { void editor.destroy(); return; }
        editorRef.current = editor;
        normalized.current = editor.action(getMarkdown());
        if (autoFocus) editor.action((ctx) => ctx.get(editorViewCtx).focus());
      });

    return () => {
      disposed = true;
      const editor = editorRef.current;
      editorRef.current = null;
      void editor?.destroy();
    };
    // The editor is made once; later values arrive through the effect below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (value === emitted.current) return;
    external.current = value;
    emitted.current = value;
    const editor = editorRef.current;
    if (!editor) return;
    syncing.current = true;
    try { editor.action(replaceAll(value)); } finally { syncing.current = false; }
    normalized.current = editor.action(getMarkdown());
  }, [value]);

  useImperativeHandle(handle, () => ({
    insertMarkdown: (markdown) => editorRef.current?.action(insert(markdown)),
    focus: () => editorRef.current?.action((ctx) => ctx.get(editorViewCtx).focus()),
  }), []);

  return <div ref={rootRef} className="note-wysiwyg reader-body reader-measure" onMouseDown={(event) => {
    // A click below the last line puts the caret at the end, as in a page.
    if (event.target !== event.currentTarget) return;
    event.preventDefault();
    editorRef.current?.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.focus();
      view.dispatch(view.state.tr.setSelection(Selection.atEnd(view.state.doc)));
    });
  }} />;
}
