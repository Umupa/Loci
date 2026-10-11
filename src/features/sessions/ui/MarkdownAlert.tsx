import type { Element, Root } from "hast";
import type { ComponentProps } from "react";
import type { Plugin } from "unified";
import { DiamondAlert, Info, Lightbulb, MessageSquareWarning, TriangleAlert } from "../../../shared/ui/icons";

const ALERTS = {
  note: { title: "Note", icon: Info },
  tip: { title: "Tip", icon: Lightbulb },
  important: { title: "Important", icon: MessageSquareWarning },
  warning: { title: "Warning", icon: TriangleAlert },
  caution: { title: "Caution", icon: DiamondAlert },
};

/** Runs after sanitizing and before word-fade spans split the marker text. */
export const rehypeGithubAlerts: Plugin<[], Root> = () => (tree, file) => {
  const source = String(file.value);
  function visit(node: Root | Element) {
    if (node.type === "element" && node.tagName === "blockquote") {
      const first = node.children.find((child) => child.type !== "text" || child.value.trim());
      if (first?.type === "element" && first.tagName === "p") {
        const text = first.children[0];
        const marker = text?.type === "text"
          ? text.value.match(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\r?\n|$)/i)
          : null;
        const offset = text?.position?.start.offset;
        // Escapes and character references express a literal label, not an alert.
        const literalMarker = marker && offset !== undefined
          && source.slice(offset, offset + marker[1].length + 3).toUpperCase() === `[!${marker[1].toUpperCase()}]`;
        const next = first.children[1];
        const hardBreak = next?.type === "element" && next.tagName === "br";
        // A marker must fill the first line, even when inline markup follows it.
        if (marker && literalMarker && text?.type === "text" && (marker[0].endsWith("\n") || first.children.length === 1 || hardBreak)) {
          node.properties.dataMarkdownAlert = marker[1].toLowerCase();
          text.value = text.value.slice(marker[0].length);
          if (!text.value) first.children.shift();
          if (hardBreak && !marker[0].endsWith("\n")) {
            first.children.shift();
            const body = first.children[0];
            if (body?.type === "text") body.value = body.value.replace(/^\r?\n/, "");
          }
          if (!first.children.some((child) => child.type !== "text" || child.value.trim())) {
            node.children.splice(node.children.indexOf(first), 1);
          }
        }
      }
    }
    for (const child of node.children) if (child.type === "element") visit(child);
  }
  visit(tree);
};

export function MarkdownBlockquote({ node, children, className, ...props }: ComponentProps<"blockquote"> & { node?: Element }) {
  const type = node?.properties.dataMarkdownAlert as keyof typeof ALERTS | undefined;
  const alert = type ? ALERTS[type] : undefined;
  return (
    <blockquote
      {...props}
      data-streamdown="blockquote"
      data-markdown-alert={type}
      className={`my-4 border-muted-foreground/30 border-l-4 pl-4 text-muted-foreground${alert ? "" : " italic"}${className ? ` ${className}` : ""}`}
    >
      {alert ? (
        <div className="markdown-alert-title">
          <alert.icon size={18} aria-hidden="true" focusable="false" />
          <span>{alert.title}</span>
        </div>
      ) : null}
      {children}
    </blockquote>
  );
}
