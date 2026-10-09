import { joinPath, slash } from "../paths";

type MarkdownNode = {
  type: string;
  url?: string;
  identifier?: string;
  title?: string | null;
  children?: MarkdownNode[];
};

const PREFIX = "/local-image/";

/** The file a picture in a document points at when its address is a path relative to the document's folder. */
export function relativeImagePath(src: string, folder: string | undefined): string | undefined {
  let value = src.trim().replace(/[?#].*$/, "");
  if (!folder || folder === "~" || !value) return undefined;
  try { value = decodeURIComponent(value); } catch { /* A literal percent sign is valid in a file name. */ }
  value = slash(value);
  // An address with a scheme, a root or a home is not beside the document.
  if (/^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith("/") || value.startsWith("~")) return undefined;
  return joinPath(folder, value);
}

/**
 * Point pictures stored beside a document, such as the figures saved with a
 * reading, at their file. This runs before URL sanitizing, which would
 * otherwise resolve `../` away and lose where the path started.
 */
export function remarkLocalImages({ cwd }: { cwd?: string }) {
  const definitions = new Map<string, MarkdownNode>();
  function collect(node: MarkdownNode) {
    if (node.type === "definition" && node.identifier && !definitions.has(node.identifier)) definitions.set(node.identifier, node);
    for (const child of node.children ?? []) collect(child);
  }
  function visit(node: MarkdownNode) {
    // Resolve image references separately: their definition may also be used
    // by an ordinary link, whose file navigation must remain intact.
    if (node.type === "imageReference" && node.identifier) {
      const definition = definitions.get(node.identifier);
      if (definition?.url && relativeImagePath(definition.url, cwd)) {
        node.type = "image";
        node.url = definition.url;
        node.title = definition.title;
      }
    }
    if (node.type === "image" && node.url) {
      const path = relativeImagePath(node.url, cwd);
      if (path) {
        const bytes = new TextEncoder().encode(path);
        let binary = "";
        for (const byte of bytes) binary += String.fromCharCode(byte);
        node.url = PREFIX + btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      }
    }
    for (const child of node.children ?? []) visit(child);
  }
  return (root: MarkdownNode) => {
    definitions.clear();
    collect(root);
    visit(root);
  };
}

/** The file behind an address written by `remarkLocalImages`. */
export function localImagePath(url: string): string | undefined {
  if (!url.startsWith(PREFIX)) return undefined;
  try {
    const binary = atob(url.slice(PREFIX.length).replace(/-/g, "+").replace(/_/g, "/"));
    return new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(binary, (char) => char.charCodeAt(0))) || undefined;
  } catch { return undefined; }
}
