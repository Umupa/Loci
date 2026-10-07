/** How a file pane shows a file, decided from its name before anything is read. */
export type FileKind = "markdown" | "pdf" | "image" | "text";

const MARKDOWN = new Set(["md", "markdown", "mdx", "mdown"]);
const IMAGE = new Set(["png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "avif"]);

/**
 * Anything that is not a known document or image is tried as text; a file that
 * turns out to be binary falls back to the "open elsewhere" card when read.
 */
export function fileKind(name: string): FileKind {
  const dot = name.lastIndexOf(".");
  const extension = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
  if (extension === "pdf") return "pdf";
  if (MARKDOWN.has(extension)) return "markdown";
  if (IMAGE.has(extension)) return "image";
  return "text";
}
