/** Where in a file a link points, when it points inside one. */
export type FilePlace = { page: number } | { lines: [number, number] };
export type AppResource =
  | { kind: "canvas" | "note" | "session"; id: string }
  /** `id` is the project-relative path, base64url-encoded so every resource id has one alphabet. */
  | { kind: "file"; id: string; place?: FilePlace };
export const APP_RESOURCE_OPEN_EVENT = "loci-open-resource";

// App-created notes can include compound session/request IDs. Match the
// persisted ID contract, which validates characters rather than length.
const RESOURCE_ID = /^[A-Za-z0-9_-]+$/;

export function appResourceUrl(kind: "canvas" | "note" | "session", id: string): string {
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
  const anchor = !place ? "" : "page" in place ? `#p${place.page}` : `#L${place.lines[0]}-${place.lines[1]}`;
  return `loci://file/${id}${anchor}`;
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
  const file = /^loci:\/\/file\/([A-Za-z0-9_-]+)(?:#(?:p([1-9]\d{0,5})|L([1-9]\d{0,6})-([1-9]\d{0,6})))?$/.exec(href);
  if (!file) return undefined;
  const resource: AppResource = { kind: "file", id: file[1],
    ...(file[2] ? { place: { page: Number(file[2]) } } : file[3] ? { place: { lines: [Number(file[3]), Number(file[4])] as [number, number] } } : {}) };
  return fileResourcePath(resource) ? resource : undefined;
}

/** The address of a resource, as `parseAppResourceUrl` reads it back. */
export function resourceUrl(resource: AppResource): string {
  if (resource.kind !== "file") return `loci://${resource.kind}/${resource.id}`;
  const place = resource.place;
  return `loci://file/${resource.id}${!place ? "" : "page" in place ? `#p${place.page}` : `#L${place.lines[0]}-${place.lines[1]}`}`;
}

export function requestOpenAppResource(resource: AppResource): void {
  window.dispatchEvent(new CustomEvent<AppResource>(APP_RESOURCE_OPEN_EVENT, { detail: resource }));
}
