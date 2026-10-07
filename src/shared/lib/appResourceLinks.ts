export type AppResource = { kind: "canvas" | "note"; id: string };
export const APP_RESOURCE_OPEN_EVENT = "loci-open-resource";

// App-created notes can include compound session/request IDs. Match the
// persisted ID contract, which validates characters rather than length.
const RESOURCE_ID = /^[A-Za-z0-9_-]+$/;

export function appResourceUrl(kind: AppResource["kind"], id: string): string {
  if (!RESOURCE_ID.test(id)) throw new Error("Invalid resource ID");
  return `loci://${kind}/${id}`;
}

/** Parse the exact app-owned address, without URL path normalization. */
export function parseAppResourceUrl(href: string): AppResource | undefined {
  const match = /^loci:\/\/(canvas|note)\/([A-Za-z0-9_-]+)$/.exec(href);
  return match ? { kind: match[1] as AppResource["kind"], id: match[2] } : undefined;
}

export function requestOpenAppResource(resource: AppResource): void {
  window.dispatchEvent(new CustomEvent<AppResource>(APP_RESOURCE_OPEN_EVENT, { detail: resource }));
}
