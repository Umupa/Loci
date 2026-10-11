import { invoke } from "@tauri-apps/api/core";

export type FeedProvider = "v2ex" | "x";

export type FeedItemState = {
  itemId: string;
  /** Reply count when the reader last opened the item. */
  seenCount?: number | null;
  seenAt?: number | null;
  starred: boolean;
  starredAt?: number | null;
  snapshot?: unknown;
};

export type FeedStateMap = ReadonlyMap<string, FeedItemState>;

export const FEED_STATE_CHANGED_EVENT = "loci:feed-state-changed";

export async function loadFeedState(provider: FeedProvider): Promise<Map<string, FeedItemState>> {
  const rows = await invoke<FeedItemState[]>("feeds_state_list", { provider });
  return new Map(rows.map((row) => [row.itemId, row]));
}

export async function markFeedItemSeen(provider: FeedProvider, itemId: string, seenCount: number) {
  await invoke("feeds_mark_seen", { provider, itemId, seenCount });
  notify(provider);
}

export async function markFeedItemsSeen(provider: FeedProvider, items: { itemId: string; seenCount: number }[]) {
  if (!items.length) return;
  await invoke("feeds_mark_seen_many", { provider, items });
  notify(provider);
}

export async function setFeedItemStarred(provider: FeedProvider, itemId: string, starred: boolean, snapshot?: unknown) {
  await invoke("feeds_set_starred", { provider, itemId, starred, snapshot: starred ? snapshot : undefined });
  notify(provider);
}

function notify(provider: FeedProvider) {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent<FeedProvider>(FEED_STATE_CHANGED_EVENT, { detail: provider }));
}

/**
 * What the list badge shows. Never-opened items are "new"; opened ones count
 * replies posted since. Optimistic marks win over the stored row.
 */
export type Unread = { kind: "new" } | { kind: "replies"; count: number } | null;

export function unreadOf(state: FeedItemState | undefined, replies: number): Unread {
  if (!state || state.seenCount == null) return { kind: "new" };
  const fresh = replies - state.seenCount;
  return fresh > 0 ? { kind: "replies", count: fresh } : null;
}

/** Apply a seen mark locally so the badge clears before the store answers. */
export function withSeen(map: FeedStateMap, itemId: string, seenCount: number): Map<string, FeedItemState> {
  const next = new Map(map);
  const current = next.get(itemId);
  next.set(itemId, {
    starred: false,
    ...current,
    itemId,
    seenCount: Math.max(current?.seenCount ?? 0, seenCount),
    seenAt: Date.now(),
  });
  return next;
}

export function withStarred(map: FeedStateMap, itemId: string, starred: boolean, snapshot?: unknown): Map<string, FeedItemState> {
  const next = new Map(map);
  const current = next.get(itemId);
  next.set(itemId, {
    ...current,
    itemId,
    starred,
    starredAt: starred ? Date.now() : null,
    snapshot: starred ? snapshot ?? current?.snapshot : undefined,
  });
  return next;
}
