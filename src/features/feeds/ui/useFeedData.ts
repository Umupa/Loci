import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { FEED_STATE_CHANGED_EVENT, loadFeedState, type FeedItemState, type FeedProvider } from "../model/feedState";
import { v2exNotifications, v2exTopics, type V2exListSource, type V2exNotification, type V2exTopic } from "../model/v2ex";

/** A list younger than this is shown as-is when its source is reopened. */
const FRESH_MS = 2 * 60_000;
/** While Feeds is open, lists refresh this often. */
export const POLL_MS = 5 * 60_000;

type Page<T> = { items: T[]; page: number; done: boolean; at: number };
const lists = new Map<string, Page<unknown>>();
let listGeneration = 0;
const listListeners = new Set<() => void>();
const subscribeLists = (listener: () => void) => {
  listListeners.add(listener);
  return () => { listListeners.delete(listener); };
};
const getListGeneration = () => listGeneration;

type ListState<T> = {
  items: T[];
  loading: boolean;
  error: string | null;
  done: boolean;
  refresh: () => void;
  loadMore: () => void;
};

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * One paged list with a module-level cache, so switching sources is instant
 * and only stale lists hit the network. `key` null means no list.
 */
function usePagedList<T extends { id: number }>(key: string | null, fetchPage: (page: number) => Promise<T[]>, pageSize: number): ListState<T> {
  const generation = useSyncExternalStore(subscribeLists, getListGeneration, getListGeneration);
  const cached = key ? (lists.get(key) as Page<T> | undefined) : undefined;
  const [items, setItems] = useState<T[]>(cached?.items ?? []);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(cached?.done ?? true);
  const request = useRef(0);
  const fetchRef = useRef(fetchPage);
  fetchRef.current = fetchPage;

  const load = useCallback((page: number) => {
    if (!key) return;
    const id = ++request.current;
    setLoading(true);
    setError(null);
    void fetchRef.current(page).then((batch) => {
      if (id !== request.current || generation !== listGeneration) return;
      const previous = page > 1 ? (lists.get(key) as Page<T> | undefined)?.items ?? [] : [];
      const seen = new Set(previous.map((item) => item.id));
      const merged = [...previous, ...batch.filter((item) => !seen.has(item.id))];
      const entry: Page<T> = { items: merged, page, done: batch.length < pageSize, at: Date.now() };
      lists.set(key, entry as Page<unknown>);
      setItems(merged);
      setDone(entry.done);
    }, (cause) => {
      if (id === request.current && generation === listGeneration) setError(errorText(cause));
    }).finally(() => {
      if (id === request.current && generation === listGeneration) setLoading(false);
    });
  }, [key, pageSize, generation]);

  useEffect(() => {
    request.current += 1;
    setLoading(false);
    if (!key) {
      setItems([]);
      setDone(true);
      setError(null);
      return;
    }
    const entry = lists.get(key) as Page<T> | undefined;
    setItems(entry?.items ?? []);
    setDone(entry?.done ?? true);
    setError(null);
    if (!entry || Date.now() - entry.at > FRESH_MS) load(1);
    const timer = window.setInterval(() => load(1), POLL_MS);
    return () => {
      request.current += 1;
      window.clearInterval(timer);
    };
  }, [key, load]);

  const refresh = useCallback(() => load(1), [load]);
  const loadMore = useCallback(() => {
    if (!key || loading || done) return;
    load(((lists.get(key)?.page) ?? 1) + 1);
  }, [key, loading, done, load]);

  return { items, loading, error, done, refresh, loadMore };
}

/** v2 node pages hold 20 topics; v1 lists are a single batch. */
export function useV2exTopics(source: V2exListSource | null, key: string | null, connected: boolean): ListState<V2exTopic> {
  const pageSize = source?.kind === "node" && connected ? 20 : Number.POSITIVE_INFINITY;
  return usePagedList(source ? `${key}:${connected ? "v2" : "v1"}` : null, (page) => v2exTopics(source!, page), pageSize);
}

export function useV2exNotifications(enabled: boolean): ListState<V2exNotification> {
  return usePagedList(enabled ? "v2ex-notifications" : null, (page) => v2exNotifications(page), 10);
}

/** Drop cached lists, e.g. after the account changes. */
export function clearFeedLists() {
  lists.clear();
  listGeneration += 1;
  listListeners.forEach((listener) => listener());
}

export function useFeedState(provider: FeedProvider) {
  const [state, setState] = useState<Map<string, FeedItemState>>(() => new Map());
  useEffect(() => {
    let live = true;
    const reload = () => {
      void loadFeedState(provider).then((next) => { if (live) setState(next); }, () => undefined);
    };
    const onChange = (event: Event) => {
      if ((event as CustomEvent<FeedProvider>).detail === provider) reload();
    };
    reload();
    window.addEventListener(FEED_STATE_CHANGED_EVENT, onChange);
    return () => {
      live = false;
      window.removeEventListener(FEED_STATE_CHANGED_EVENT, onChange);
    };
  }, [provider]);
  return [state, setState] as const;
}
