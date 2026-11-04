import { codeBlockSchema } from "@milkdown/kit/preset/commonmark";
import { Plugin, TextSelection } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import type { Node as ProseNode } from "@milkdown/kit/prose/model";
import { $prose, $view } from "@milkdown/kit/utils";
import { currentColorScheme, SCHEME_CHANGE_EVENT } from "../../settings/model/appearance";
import { createLazyMermaidPlugin } from "../../../shared/lib/markdown/mermaidPlugin";

/*
 * A ```mermaid block in a note reads as its diagram. With the caret inside it
 * the source opens beneath the diagram, which follows as it is typed; a click
 * on the diagram puts the caret in the source.
 */

const mermaid = createLazyMermaidPlugin();
const RENDER_DELAY_MS = 250;
let renderSeq = 0;

const isMermaid = (node: ProseNode) => node.type.name === "code_block" && String(node.attrs.language ?? "").trim().toLowerCase() === "mermaid";

export const mermaidCodeBlockView = $view(codeBlockSchema.node, () => (initial, view, getPos) => {
  const pre = document.createElement("pre");
  const code = document.createElement("code");
  pre.appendChild(code);
  const setLanguage = (node: ProseNode) => {
    const language = String(node.attrs.language ?? "");
    if (language) pre.dataset.language = language; else delete pre.dataset.language;
  };
  setLanguage(initial);
  if (!isMermaid(initial)) {
    return {
      dom: pre,
      contentDOM: code,
      update: (node) => {
        if (node.type !== initial.type || isMermaid(node)) return false;
        setLanguage(node);
        return true;
      },
    };
  }

  const dom = document.createElement("div");
  dom.className = "note-mermaid";
  const diagram = document.createElement("div");
  diagram.className = "note-mermaid-diagram";
  diagram.contentEditable = "false";
  diagram.setAttribute("aria-label", "Mermaid diagram");
  dom.append(diagram, pre);

  let source = initial.textContent;
  let shown: string | null = null;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let destroyed = false;

  const render = () => {
    timer = undefined;
    const text = source.trim();
    const scheme = currentColorScheme();
    const key = `${scheme}\n${text}`;
    if (key === shown) return;
    shown = key;
    if (!text) { diagram.replaceChildren(); dom.classList.add("is-failed"); return; }
    void mermaid
      .getMermaid({ theme: scheme === "light" ? "default" : "dark" })
      .render(`note-mermaid-${++renderSeq}`, text)
      .then(({ svg }) => {
        if (destroyed || shown !== key) return;
        diagram.innerHTML = svg;
        dom.classList.remove("is-failed");
      })
      .catch(() => {
        if (destroyed || shown !== key) return;
        dom.classList.add("is-failed");
      });
  };
  const schedule = (delay: number) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(render, delay);
  };
  const onScheme = () => schedule(0);
  window.addEventListener(SCHEME_CHANGE_EVENT, onScheme);
  render();

  diagram.addEventListener("mousedown", (event) => {
    event.preventDefault();
    event.stopPropagation();
    const pos = getPos();
    if (pos == null) return;
    const node = view.state.doc.nodeAt(pos);
    if (!node) return;
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, pos + 1 + node.content.size)));
    view.focus();
  });

  return {
    dom,
    contentDOM: code,
    update: (node) => {
      if (!isMermaid(node)) return false;
      setLanguage(node);
      if (node.textContent !== source) {
        source = node.textContent;
        schedule(RENDER_DELAY_MS);
      }
      return true;
    },
    // Only the source is text the user edits; the SVG mermaid writes and the
    // classes set here are not edits.
    ignoreMutation: (mutation) => mutation.type !== "selection" && !code.contains(mutation.target),
    stopEvent: (event) => diagram.contains(event.target as Node),
    destroy: () => {
      destroyed = true;
      if (timer) clearTimeout(timer);
      window.removeEventListener(SCHEME_CHANGE_EVENT, onScheme);
    },
  };
});

/** Marks the mermaid block holding the caret, so its source shows. */
export const mermaidEditingPlugin = $prose(() => new Plugin({
  props: {
    decorations: (state) => {
      const { $from, $to } = state.selection;
      for (let depth = $from.depth; depth > 0; depth--) {
        const node = $from.node(depth);
        if (!isMermaid(node)) continue;
        const start = $from.before(depth);
        if ($to.pos > start + node.nodeSize) return null;
        return DecorationSet.create(state.doc, [Decoration.node(start, start + node.nodeSize, { class: "is-editing" })]);
      }
      return null;
    },
  },
}));
