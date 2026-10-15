import type { V2exListSource, V2exNode } from "./v2ex";

/** One entry in the Feeds source list. */
export type FeedSource =
  | { kind: "v2ex-hot" }
  | { kind: "v2ex-latest" }
  | { kind: "v2ex-node"; name: string }
  | { kind: "v2ex-notifications" }
  | { kind: "v2ex-starred" };

export type SavedNode = Pick<V2exNode, "name" | "title">;

const SOURCE_KEY = "loci.feeds.source";
const NODES_KEY = "loci.feeds.v2exNodes";
const MAX_NODES = 50;

export const DEFAULT_SOURCE: FeedSource = { kind: "v2ex-hot" };

export function sourceKey(source: FeedSource): string {
  return source.kind === "v2ex-node" ? `v2ex-node:${source.name}` : source.kind;
}

export function sameSource(a: FeedSource, b: FeedSource): boolean {
  return sourceKey(a) === sourceKey(b);
}

/** The list request behind a topic source; null for sources that aren't topic lists. */
export function v2exListOf(source: FeedSource): V2exListSource | null {
  if (source.kind === "v2ex-hot") return { kind: "hot" };
  if (source.kind === "v2ex-latest") return { kind: "latest" };
  if (source.kind === "v2ex-node") return { kind: "node", name: source.name };
  return null;
}

export function parseSource(raw: unknown): FeedSource | null {
  if (typeof raw !== "string") return null;
  if (raw.startsWith("v2ex-node:")) {
    const name = raw.slice("v2ex-node:".length);
    return /^[A-Za-z0-9_-]{1,64}$/.test(name) ? { kind: "v2ex-node", name } : null;
  }
  const simple = ["v2ex-hot", "v2ex-latest", "v2ex-notifications", "v2ex-starred"] as const;
  const kind = simple.find((item) => item === raw);
  return kind ? ({ kind } as FeedSource) : null;
}

/** The V2EX list last shown. */
export function loadFeedSource(): FeedSource {
  try {
    const source = parseSource(localStorage.getItem(SOURCE_KEY));
    return source ?? DEFAULT_SOURCE;
  } catch {
    return DEFAULT_SOURCE;
  }
}

export function saveFeedSource(source: FeedSource) {
  try {
    localStorage.setItem(SOURCE_KEY, sourceKey(source));
  } catch {
    // Storage can be unavailable; the choice just won't persist.
  }
}

export function parseSavedNodes(raw: string | null): SavedNode[] {
  if (!raw) return [];
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    const seen = new Set<string>();
    const nodes: SavedNode[] = [];
    for (const item of parsed) {
      if (!item || typeof item !== "object") continue;
      const { name, title } = item as Record<string, unknown>;
      if (typeof name !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(name) || seen.has(name)) continue;
      seen.add(name);
      nodes.push({ name, title: typeof title === "string" && title.trim() ? title : name });
    }
    return nodes.slice(0, MAX_NODES);
  } catch {
    return [];
  }
}

export function loadSavedNodes(): SavedNode[] {
  try {
    return parseSavedNodes(localStorage.getItem(NODES_KEY));
  } catch {
    return [];
  }
}

export function saveSavedNodes(nodes: readonly SavedNode[]) {
  try {
    localStorage.setItem(NODES_KEY, JSON.stringify(nodes.slice(0, MAX_NODES)));
  } catch {
    // Storage can be unavailable; the list just won't persist.
  }
}

export function addSavedNode(nodes: readonly SavedNode[], node: SavedNode): SavedNode[] {
  return [...nodes.filter((item) => item.name !== node.name), { name: node.name, title: node.title }].slice(0, MAX_NODES);
}

export function removeSavedNode(nodes: readonly SavedNode[], name: string): SavedNode[] {
  return nodes.filter((item) => item.name !== name);
}
