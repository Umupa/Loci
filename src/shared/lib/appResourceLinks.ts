/** Where in a file a link points, when it points inside one; `quote` is the passage to show there. */
export type FilePlace = { page: number; quote?: string; annotationId?: string } | { lines: [number, number]; quote?: string };
/** Where in a source a link points: a heading, a quoted passage, a page or lines. */
export type SourcePlace = { section?: string; quote?: string; page?: number; lines?: [number, number] };
export type AppResource =
  | { kind: "canvas" | "note" | "session"; id: string }
  | { kind: "source"; id: string; place?: SourcePlace }
  /** `id` is the project-relative path, base64url-encoded so every resource id has one alphabet. */
  | { kind: "file"; id: string; place?: FilePlace };
export const APP_RESOURCE_OPEN_EVENT = "loci-open-resource";

// App-created notes can include compound session/request IDs. Match the
// persisted ID contract, which validates characters rather than length.
const RESOURCE_ID = /^[A-Za-z0-9_-]+$/;

export function appResourceUrl(kind: "canvas" | "note" | "session" | "source", id: string): string {
  if (!RESOURCE_ID.test(id)) throw new Error("Invalid resource ID");
  return `loci://${kind}/${id}`;
}

/** A link to a project file, optionally to a PDF page or a range of lines. */
export function fileResourceUrl(relativePath: string, place?: FilePlace): string {
  const bytes = new TextEncoder().encode(relativePath);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const id = btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  if (!id) throw new Error("Invalid file path");
  return `loci://file/${id}${filePlaceFragment(place)}`;
}

const SECTION_MAX = 300;
const QUOTE_MAX = 500;
function filePlaceFragment(place?: FilePlace): string {
  if (!place) return "";
  if ("page" in place) return `#p${place.page}`;
  return `#L${place.lines[0]}-${place.lines[1]}${place.quote ? `&quote=${encodeURIComponent(place.quote)}` : ""}`;
}
function sourcePlaceFragment(place?: SourcePlace): string {
  if (!place) return "";
  const parts = [
    ...(place.page ? [`p${place.page}`] : []),
    ...(place.lines ? [`L${place.lines[0]}-${place.lines[1]}`] : []),
    ...(place.section ? [`section=${encodeURIComponent(place.section)}`] : []),
    ...(place.quote ? [`quote=${encodeURIComponent(place.quote)}`] : []),
  ];
  return parts.length ? `#${parts.join("&")}` : "";
}

/**
 * A link's fragment: `p7`, `L12-40` (or `L12`), `section=…` and `quote=…`,
 * joined by `&`, each at most once. Anything else makes the whole link invalid.
 */
function parsePlace(fragment: string): SourcePlace | undefined {
  const place: SourcePlace = {};
  for (const part of fragment.split("&")) {
    const page = /^p([1-9]\d{0,5})$/.exec(part);
    const lines = /^L([1-9]\d{0,6})(?:-([1-9]\d{0,6}))?$/.exec(part);
    const field = /^(section|quote)=(.+)$/.exec(part);
    if (page && place.page === undefined) place.page = Number(page[1]);
    else if (lines && !place.lines) {
      const first = Number(lines[1]); const last = lines[2] ? Number(lines[2]) : first;
      if (last < first) return undefined;
      place.lines = [first, last];
    } else if (field && place[field[1] as "section" | "quote"] === undefined) {
      let text: string;
      try { text = decodeURIComponent(field[2]).replace(/\s+/g, " ").trim(); } catch { return undefined; }
      if (!text || text.length > (field[1] === "section" ? SECTION_MAX : QUOTE_MAX) || /[\u0000-\u001f]/.test(text)) return undefined;
      place[field[1] as "section" | "quote"] = text;
    } else return undefined;
  }
  return place;
}

/** The project-relative path of a file link, or undefined when it could leave the project. */
export function fileResourcePath(resource: AppResource): string | undefined {
  if (resource.kind !== "file") return undefined;
  try {
    const binary = atob(resource.id.replace(/-/g, "+").replace(/_/g, "/"));
    const path = new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
    const parts = path.split("/");
    return !path || path.startsWith("/") || path.includes("\\") || path.includes("\0") || parts.some((part) => !part || part === "." || part === "..") ? undefined : path;
  } catch { return undefined; }
}

/** Parse the exact app-owned address, without URL path normalization. */
export function parseAppResourceUrl(href: string): AppResource | undefined {
  const match = /^loci:\/\/(canvas|note|session)\/([A-Za-z0-9_-]+)$/.exec(href);
  if (match) return { kind: match[1] as "canvas" | "note" | "session", id: match[2] };
  const source = /^loci:\/\/source\/([A-Za-z0-9_-]+)(?:#(.{1,2000}))?$/.exec(href);
  if (source) {
    if (source[2] === undefined) return { kind: "source", id: source[1] };
    const place = parsePlace(source[2]);
    return place ? { kind: "source", id: source[1], place } : undefined;
  }
  const file = /^loci:\/\/file\/([A-Za-z0-9_-]+)(?:#(.{1,2000}))?$/.exec(href);
  if (!file) return undefined;
  let place: FilePlace | undefined;
  if (file[2] !== undefined) {
    const parsed = parsePlace(file[2]);
    // A file link names a page, or lines with an optional passage in them.
    if (!parsed || parsed.section || (parsed.page && (parsed.lines || parsed.quote)) || (!parsed.page && !parsed.lines)
      || (parsed.lines && !/(^|&)L\d+-\d+(&|$)/.test(file[2]))) return undefined;
    place = parsed.page ? { page: parsed.page } : { lines: parsed.lines!, ...(parsed.quote ? { quote: parsed.quote } : {}) };
  }
  const resource: AppResource = { kind: "file", id: file[1], ...(place ? { place } : {}) };
  return fileResourcePath(resource) ? resource : undefined;
}

/** The address of a resource, as `parseAppResourceUrl` reads it back. */
export function resourceUrl(resource: AppResource): string {
  if (resource.kind === "file") return `loci://file/${resource.id}${filePlaceFragment(resource.place)}`;
  if (resource.kind === "source") return `loci://source/${resource.id}${sourcePlaceFragment(resource.place)}`;
  return `loci://${resource.kind}/${resource.id}`;
}

export function requestOpenAppResource(resource: AppResource): void {
  window.dispatchEvent(new CustomEvent<AppResource>(APP_RESOURCE_OPEN_EVENT, { detail: resource }));
}
