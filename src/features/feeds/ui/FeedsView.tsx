import { openUrl } from "@tauri-apps/plugin-opener";
import { useCallback, useEffect, useMemo, useState, type FormEvent, type ReactNode } from "react";
import { OverlayNav } from "../../../app/shell/TitleBar";
import { WindowControls } from "../../../app/shell/WindowControls";
import { IS_MAC } from "../../../platform/tauri/platform";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import { ContextMenu, type ContextMenuItem } from "../../../shared/ui/ContextMenu";
import {
  Bell, Bookmark, CheckCheck, Compass, Hashtag, Home, ListBullet, ListFilter, LoaderCircle, MessageMultiple, Plus, RefreshCw, Rss, Search, Star,
} from "../../../shared/ui/icons";
import { ADD_NOTE_TO_CHAT_EVENT, NOTES_CHANGED_EVENT, upsertNote, type NoteComposerCard } from "../../notes";
import { v2exTopicCard, xCaptureCard, type XCapture } from "../model/feedContext";
import {
  addSavedNode, loadFeedSource, loadFeedTab, loadSavedNodes, removeSavedNode, sameSource, saveFeedSource, saveFeedTab, saveSavedNodes,
  sourceKey, v2exListOf, type FeedSource, type FeedTab, type SavedNode,
} from "../model/feedSources";
import { markFeedItemSeen, markFeedItemsSeen, setFeedItemStarred, unreadOf, withSeen, withStarred, type FeedStateMap } from "../model/feedState";
import {
  clearV2exToken, parseNodeName, setV2exToken, v2exNode, v2exStatus, v2exTopic,
  type V2exNotification, type V2exReply, type V2exStatus, type V2exTopic,
} from "../model/v2ex";
import { navigateXFeed, X_SHORTCUTS, xPathForQuery } from "../model/xFeed";
import { ACTION_FILLED, ACTION_GHOST, Avatar, Chip, EmptyDetail, FeedProviderMark, IconButton, Person, PROVIDER_LABELS } from "./feedUi";
import { clearFeedLists, useFeedState, useV2exNotifications, useV2exTopics } from "./useFeedData";
import { relativeSeconds, V2exTopicDetail } from "./V2exTopicDetail";
import { XFeedPane } from "./XFeedPane";

type Props = {
  besideRail?: boolean;
  compactRail?: boolean;
  onClose: () => void;
  onToggleSidebar?: () => void;
  onNoteSaved?: (id: string) => void;
};

const LIST_MIN = 240;
const LIST_MAX = 420;
const LIST_DEFAULT = 300;
let rememberedListWidth = LIST_DEFAULT;

const X_ICONS: Record<string, ReactNode> = {
  home: <Home className="size-3.5" />,
  explore: <Compass className="size-3.5" />,
  notifications: <Bell className="size-3.5" />,
  bookmarks: <Bookmark className="size-3.5" />,
  lists: <ListBullet className="size-3.5" />,
};

function isTopic(value: unknown): value is V2exTopic {
  return !!value && typeof value === "object" && typeof (value as V2exTopic).id === "number" && typeof (value as V2exTopic).title === "string";
}

function typingTarget(target: EventTarget | null): boolean {
  return target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
}

function matches(query: string, ...fields: (string | null | undefined)[]): boolean {
  const needle = query.trim().toLowerCase();
  return !needle || fields.some((field) => field?.toLowerCase().includes(needle));
}

function sourceTitle(source: FeedSource, nodes: readonly SavedNode[]): string {
  switch (source.kind) {
    case "v2ex-hot": return "Hot";
    case "v2ex-latest": return "Latest";
    case "v2ex-notifications": return "Notifications";
    case "v2ex-starred": return "Starred";
    case "v2ex-node": return nodes.find((node) => node.name === source.name)?.title ?? source.name;
    case "x": return "X";
  }
}

export function FeedsView({ besideRail = false, compactRail = false, onClose, onToggleSidebar, onNoteSaved }: Props) {
  const [tab, setTabState] = useState<FeedTab>(loadFeedTab);
  const [source, setSourceState] = useState<FeedSource>(loadFeedSource);
  const [nodes, setNodes] = useState<SavedNode[]>(loadSavedNodes);
  const [status, setStatus] = useState<V2exStatus>({ connected: false });
  const [accountOpen, setAccountOpen] = useState(false);
  const [addingNode, setAddingNode] = useState(false);
  const [selected, setSelected] = useState<V2exTopic | null>(null);
  const [query, setQuery] = useState("");
  const [xPage, setXPage] = useState("home");
  const [menuAnchor, setMenuAnchor] = useState<HTMLElement | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [state, setState] = useFeedState("v2ex");
  const resize = useDragResize({
    min: LIST_MIN,
    max: () => Math.min(LIST_MAX, Math.round(window.innerWidth * 0.5)),
    defaultWidth: LIST_DEFAULT,
    initial: rememberedListWidth,
    onCommit: (width) => { rememberedListWidth = width; },
  });

  useEffect(() => {
    let live = true;
    void v2exStatus(true).then((next) => { if (live) setStatus(next); }, () => {
      // A stored token V2EX now rejects: say so, but keep it until the user acts.
      void v2exStatus(false).then((next) => { if (live) setStatus(next); }, () => undefined);
    });
    return () => { live = false; };
  }, []);

  const setTab = (next: FeedTab) => {
    setTabState(next);
    saveFeedTab(next);
    setQuery("");
    setMenuAnchor(null);
  };

  const setSource = useCallback((next: FeedSource) => {
    setSourceState(next);
    saveFeedSource(next);
    setSelected(null);
    setAccountOpen(false);
    setQuery("");
  }, []);

  const v2exTab = tab === "v2ex";
  const listSource = v2exTab ? v2exListOf(source) : null;
  const topics = useV2exTopics(listSource, listSource ? sourceKey(source) : null, status.connected);
  const notifications = useV2exNotifications(v2exTab && source.kind === "v2ex-notifications" && status.connected);
  const starred = useMemo(() => [...state.values()]
    .filter((row) => row.starred && isTopic(row.snapshot))
    .sort((a, b) => (b.starredAt ?? 0) - (a.starredAt ?? 0))
    .map((row) => row.snapshot as V2exTopic), [state]);
  const listed = useMemo(() => (source.kind === "v2ex-starred" ? starred : listSource ? topics.items : [])
    .filter((topic) => matches(query, topic.title, topic.node?.title, topic.node?.name, topic.member?.username)),
  [source.kind, starred, listSource, topics.items, query]);
  const shownNotifications = notifications.items.filter((item) => matches(query, item.text, item.payload, item.member));
  const unreadTopics = listed.filter((topic) => unreadOf(state.get(String(topic.id)), topic.replies));

  const onSeen = useCallback((topic: V2exTopic, count: number) => {
    setState((current) => withSeen(current, String(topic.id), count));
    void markFeedItemSeen("v2ex", String(topic.id), count).catch(() => undefined);
  }, [setState]);

  const markAllRead = () => {
    const items = unreadTopics.map((topic) => ({ itemId: String(topic.id), seenCount: topic.replies }));
    setState((current) => items.reduce((next, item) => withSeen(next, item.itemId, item.seenCount), current));
    void markFeedItemsSeen("v2ex", items).catch((cause) => setNotice(String(cause)));
  };

  const toggleStar = useCallback((topic: V2exTopic) => {
    const next = !state.get(String(topic.id))?.starred;
    setState((current) => withStarred(current, String(topic.id), next, topic));
    void setFeedItemStarred("v2ex", String(topic.id), next, topic).catch((cause) => setNotice(String(cause)));
  }, [state, setState]);

  const sendToAgent = useCallback((card: NoteComposerCard) => {
    window.dispatchEvent(new CustomEvent<NoteComposerCard>(ADD_NOTE_TO_CHAT_EVENT, { detail: card }));
    onClose();
  }, [onClose]);

  const saveNote = useCallback(async (title: string, body: string, tag: string) => {
    try {
      const note = await upsertNote({ id: crypto.randomUUID(), title: title.slice(0, 200), body, tags: [tag] });
      window.dispatchEvent(new Event(NOTES_CHANGED_EVENT));
      onNoteSaved?.(note.id);
    } catch (cause) {
      setNotice(String(cause));
    }
  }, [onNoteSaved]);

  const openNotification = useCallback((item: V2exNotification) => {
    if (!item.topicId) return;
    setNotice(null);
    setAccountOpen(false);
    void v2exTopic(item.topicId).then(setSelected, (cause) => setNotice(String(cause)));
  }, []);

  const goX = (id: string, path: string) => {
    setXPage(id);
    void navigateXFeed(path).catch((cause) => setNotice(String(cause)));
  };

  // j / k walk the topic list, like most feed readers.
  useEffect(() => {
    if (!v2exTab || source.kind === "v2ex-notifications") return;
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey || typingTarget(event.target)) return;
      if ((event.key !== "j" && event.key !== "k") || !listed.length) return;
      event.preventDefault();
      const index = selected ? listed.findIndex((topic) => topic.id === selected.id) : -1;
      const next = event.key === "j" ? Math.min(listed.length - 1, index + 1) : Math.max(0, index - 1);
      setSelected(listed[next]);
      setAccountOpen(false);
      document.querySelector(`[data-feed-topic="${listed[next].id}"]`)?.scrollIntoView({ block: "nearest" });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [v2exTab, source.kind, listed, selected]);

  const loading = source.kind === "v2ex-notifications" ? notifications.loading : topics.loading;
  const refresh = source.kind === "v2ex-notifications" ? notifications.refresh : topics.refresh;
  const listError = source.kind === "v2ex-notifications" ? notifications.error : listSource ? topics.error : null;

  const menuItems: ContextMenuItem[] = [
    { kind: "item", id: "v2ex-hot", label: "Hot", checked: source.kind === "v2ex-hot" },
    { kind: "item", id: "v2ex-latest", label: "Latest", checked: source.kind === "v2ex-latest" },
    ...(status.connected ? [{ kind: "item" as const, id: "v2ex-notifications", label: "Notifications", checked: source.kind === "v2ex-notifications" }] : []),
    { kind: "item", id: "v2ex-starred", label: "Starred", description: starred.length ? `${starred.length} topics` : undefined, checked: source.kind === "v2ex-starred" },
    ...(nodes.length ? [{ kind: "sep" as const }] : []),
    ...nodes.map((node) => ({
      kind: "item" as const, id: `v2ex-node:${node.name}`, label: node.title, description: node.name,
      checked: sameSource(source, { kind: "v2ex-node", name: node.name }),
    })),
    { kind: "sep" },
    { kind: "item", id: "add-node", label: "Add node…" },
    ...(source.kind === "v2ex-node" ? [{ kind: "item" as const, id: "remove-node", label: `Remove ${sourceTitle(source, nodes)}`, danger: true }] : []),
    { kind: "item", id: "account", label: status.member ? `Account · @${status.member.username}` : "Connect account…" },
  ];

  const pickMenu = (id: string) => {
    setMenuAnchor(null);
    if (id === "add-node") { setAddingNode(true); return; }
    if (id === "account") { setAccountOpen(true); setSelected(null); return; }
    if (id === "remove-node" && source.kind === "v2ex-node") {
      const next = removeSavedNode(nodes, source.name);
      setNodes(next);
      saveSavedNodes(next);
      setSource({ kind: "v2ex-hot" });
      return;
    }
    if (id.startsWith("v2ex-node:")) { setSource({ kind: "v2ex-node", name: id.slice("v2ex-node:".length) }); return; }
    setSource({ kind: id } as FeedSource);
  };

  const submitX = (event: FormEvent) => {
    event.preventDefault();
    const path = xPathForQuery(query);
    if (path) goX("search", path);
  };

  const list = (
    <div ref={resize.setPaneRef} className="relative flex h-full min-h-0 shrink-0 flex-col border-r border-stroke">
      <div className="flex h-9 shrink-0 items-center gap-px border-b border-stroke px-2">
        <div role="tablist" aria-label="Feed providers" className="flex min-w-0 basis-0 items-center gap-px" style={{ flexGrow: 2 }}>
          {(["v2ex", "x"] as const).map((provider) => (
            <button key={provider} type="button" role="tab" aria-selected={tab === provider} onClick={() => setTab(provider)}
              className={`flex h-6 min-w-0 flex-1 items-center justify-center rounded-md px-2 text-[12px] leading-none ${
                tab === provider ? "bg-selection text-content" : "text-content/50 hover:bg-content/5 hover:text-content"}`}>
              <span className="flex items-center gap-1.5">
                <FeedProviderMark provider={provider} className="block size-3.5 shrink-0" />
                <span className="leading-none">{PROVIDER_LABELS[provider]}</span>
              </span>
            </button>
          ))}
        </div>
        {v2exTab ? (
          <button type="button" onClick={() => setAddingNode((open) => !open)}
            className={`flex h-6 min-w-0 flex-1 items-center justify-center gap-1.5 rounded-md px-2 text-[12px] leading-none ${
              addingNode ? "bg-selection text-content" : "text-content/40 hover:bg-content/5 hover:text-content"}`}>
            <Plus className="size-3.5 shrink-0" />
            <span className="min-w-0 truncate">Add node</span>
          </button>
        ) : <span className="flex-1" />}
      </div>
      {v2exTab && addingNode ? (
        <AddNodeForm onCancel={() => setAddingNode(false)} onAdd={(node) => {
          const next = addSavedNode(nodes, node);
          setNodes(next);
          saveSavedNodes(next);
          setAddingNode(false);
          setSource({ kind: "v2ex-node", name: node.name });
        }} />
      ) : null}
      <form onSubmit={v2exTab ? (event) => event.preventDefault() : submitX} className="flex h-9 shrink-0 items-center gap-1 border-b border-stroke px-2">
        <div className="relative flex h-7 min-w-0 flex-1 items-center">
          <Search className="pointer-events-none absolute left-2 size-3 shrink-0 opacity-50" />
          <input value={query} onChange={(event) => setQuery(event.target.value)} spellCheck={false} autoComplete="off"
            placeholder={v2exTab ? `Filter ${sourceTitle(source, nodes)}` : "Search X, @handle or a link"}
            aria-label={v2exTab ? "Filter feed" : "Search X"}
            className="h-7 w-full rounded-md bg-transparent pl-7 pr-2 text-[12px] text-content outline-none placeholder:text-content/40" />
        </div>
        {v2exTab ? (
          <>
            <IconButton label="Choose list" active={!!menuAnchor || source.kind !== "v2ex-hot"} onClick={(event) => setMenuAnchor(event.currentTarget)}>
              <ListFilter className="size-3" />
            </IconButton>
            <IconButton label="Mark all as read" disabled={!unreadTopics.length} onClick={markAllRead}>
              <CheckCheck className="size-3.5" />
            </IconButton>
            <IconButton label="Refresh" disabled={source.kind === "v2ex-starred"} onClick={refresh}>
              {loading ? <LoaderCircle className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}
            </IconButton>
          </>
        ) : null}
      </form>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-none">
        {notice ? (
          <button type="button" onClick={() => setNotice(null)} className="w-full px-3 py-2 text-left text-[12px] text-red-400/90 hover:text-red-300">{notice}</button>
        ) : null}
        {!v2exTab ? (
          <ul className="flex flex-col gap-0.5 p-1.5">
            {X_SHORTCUTS.map((shortcut) => (
              <li key={shortcut.id}>
                <Card active={xPage === shortcut.id} onClick={() => goX(shortcut.id, shortcut.path)}>
                  <span className="flex min-w-0 items-center gap-1.5 text-[11px] text-content/50">
                    <FeedProviderMark provider="x" className="size-3 shrink-0" />
                    <span className="truncate">x.com{shortcut.path}</span>
                  </span>
                  <span className="mt-1 flex items-center gap-1.5 text-[13px] font-semibold leading-snug text-content">
                    <span className="text-content/60">{X_ICONS[shortcut.id]}</span>{shortcut.label}
                  </span>
                  <span className="mt-1 truncate text-[11px] text-content/45">{shortcut.description}</span>
                </Card>
              </li>
            ))}
          </ul>
        ) : (
          <>
            {listError ? <p role="alert" className="px-3 py-2 text-[12px] text-red-400/90">{listError}</p> : null}
            {source.kind === "v2ex-notifications" ? (
              <NotificationList items={shownNotifications} loading={notifications.loading} more={!notifications.done} onMore={notifications.loadMore}
                onOpen={openNotification} />
            ) : (
              <TopicList topics={listed} state={state} selectedId={accountOpen ? undefined : selected?.id} loading={!!listSource && topics.loading}
                empty={query.trim() ? "No matching topics" : source.kind === "v2ex-starred" ? "Star a topic to keep it here." : "Nothing here yet."}
                more={!!listSource && !topics.done && !query.trim()} onMore={topics.loadMore}
                onSelect={(topic) => { setSelected(topic); setAccountOpen(false); }} />
            )}
          </>
        )}
      </div>
      {v2exTab ? (
        <button type="button" onClick={() => { setAccountOpen(true); setSelected(null); }}
          className={`flex h-9 shrink-0 items-center gap-2 border-t border-stroke px-3 text-left text-[12px] ${accountOpen ? "text-content" : "text-content/50 hover:text-content"}`}>
          {status.member ? <Avatar src={status.member.avatar} name={status.member.username} size={16} /> : <FeedProviderMark provider="v2ex" />}
          <span className="min-w-0 truncate">{status.member ? `@${status.member.username}` : status.connected ? "V2EX account" : "Connect V2EX account"}</span>
        </button>
      ) : null}
      <div role="separator" aria-orientation="vertical" aria-label="Resize feed list"
        className={`absolute inset-y-0 -right-px z-10 w-1.5 cursor-col-resize touch-none ${resize.dragging ? "bg-content/15" : "hover:bg-content/10"}`}
        onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick} />
    </div>
  );

  const detail = !v2exTab ? (
    <XFeedPane onSendToAgent={(capture: XCapture) => sendToAgent(xCaptureCard(capture))}
      onSaveNote={(title, body) => saveNote(title, body, "x")} />
  ) : accountOpen ? (
    <AccountPanel status={status} onChange={(next) => { setStatus(next); clearFeedLists(); }} />
  ) : selected ? (
    <V2exTopicDetail key={selected.id} topic={selected} seenCount={state.get(String(selected.id))?.seenCount ?? null}
      starred={!!state.get(String(selected.id))?.starred} onSeen={onSeen} onToggleStar={toggleStar}
      onSendToAgent={(topic: V2exTopic, replies: V2exReply[]) => sendToAgent(v2exTopicCard(topic, replies))}
      onSaveNote={(title, body) => saveNote(title, body, "v2ex")} />
  ) : (
    <EmptyDetail icon={<Rss className="size-6" />}>Select a topic · j / k to move through the list</EmptyDetail>
  );

  return (
    <div role="region" aria-label="Feeds" data-app-feeds className="flex min-h-0 min-w-0 flex-1 flex-col text-content">
      <div className="flex h-10 shrink-0 select-none items-center border-b border-stroke" data-tauri-drag-region="deep">
        {IS_MAC && compactRail ? <div className="w-4 shrink-0" /> : null}
        {IS_MAC && !besideRail ? <div className="w-[78px] shrink-0" /> : null}
        {besideRail ? null : <OverlayNav onBack={onClose} onToggleSidebar={onToggleSidebar} />}
        <div className="flex min-w-0 flex-1 items-center gap-2 px-3 text-[13px]">
          <Rss className="size-3.5 shrink-0 text-content/45" />
          <span className="min-w-0 truncate text-content">Feeds</span>
        </div>
        {IS_MAC ? null : <WindowControls />}
      </div>
      <div className="flex min-h-0 min-w-0 flex-1">
        {list}
        <div className="relative flex min-h-0 min-w-0 flex-1">{detail}</div>
      </div>
      {menuAnchor ? <ContextMenu anchor={menuAnchor} items={menuItems} onPick={pickMenu} onClose={() => setMenuAnchor(null)} /> : null}
    </div>
  );
}

function Card({ active, onClick, children, ...rest }: { active: boolean; onClick: () => void; children: ReactNode; "data-feed-topic"?: number }) {
  return (
    <button type="button" aria-current={active ? "true" : undefined} onClick={onClick} {...rest}
      className={`flex w-full flex-col rounded-md border px-2.5 py-2 text-left ${
        active ? "border-transparent bg-selection text-content" : "border-transparent text-content/80 hover:bg-content/5 hover:text-content"}`}>
      {children}
    </button>
  );
}

function ListSpinner() {
  return <div className="flex justify-center py-10 text-content/40"><LoaderCircle className="size-4 animate-spin" /></div>;
}

function MoreButton({ loading, onMore }: { loading: boolean; onMore: () => void }) {
  return (
    <li>
      <button type="button" onClick={onMore} disabled={loading}
        className="flex h-8 w-full items-center justify-center gap-1.5 rounded-md text-[12px] text-content/45 hover:bg-content/5 hover:text-content">
        {loading ? <LoaderCircle className="size-3.5 animate-spin" /> : null} Load more
      </button>
    </li>
  );
}

function TopicList({ topics, state, selectedId, loading, empty, more, onMore, onSelect }: {
  topics: readonly V2exTopic[];
  state: FeedStateMap;
  selectedId?: number;
  loading: boolean;
  empty: string;
  more: boolean;
  onMore: () => void;
  onSelect: (topic: V2exTopic) => void;
}) {
  if (!topics.length) return loading ? <ListSpinner /> : <p className="px-3 py-2 text-[12px] text-content/50">{empty}</p>;
  return (
    <ul className="flex flex-col gap-0.5 p-1.5">
      {topics.map((topic) => {
        const row = state.get(String(topic.id));
        const unread = unreadOf(row, topic.replies);
        return (
          <li key={topic.id}>
            <Card active={topic.id === selectedId} onClick={() => onSelect(topic)} data-feed-topic={topic.id}>
              <span className="flex items-center gap-2">
                <span className="flex min-w-0 flex-1 items-center gap-1.5">
                  <FeedProviderMark provider="v2ex" />
                  <Hashtag className="size-3 shrink-0 text-emerald-400/90" />
                  <span className="min-w-0 truncate text-[11px] text-content/50">{topic.node?.title ?? "Topic"} · #{topic.id}</span>
                </span>
                <span className="flex shrink-0 items-center gap-1.5">
                  {unread?.kind === "replies" ? (
                    <span className="inline-flex items-center gap-0.5 text-[11px] tabular-nums text-accent"><MessageMultiple className="size-3" />+{unread.count}</span>
                  ) : null}
                  <span className="text-[11px] tabular-nums text-content/45">{relativeSeconds(topic.lastTouched)}</span>
                  {unread?.kind === "new" ? <span aria-label="Unread" className="size-1.5 rounded-full bg-accent" /> : null}
                </span>
              </span>
              <span className={`mt-1 line-clamp-1 text-[13px] font-semibold leading-snug ${unread ? "text-content" : "text-content/60"}`}>{topic.title}</span>
              <span className="mt-1 flex min-w-0 items-center gap-2">
                <span className="flex min-w-0 flex-1 items-center gap-1.5 text-[11px] text-content/45">
                  {topic.member ? <Person name={topic.member.username} avatar={topic.member.avatar} size={14} /> : <span className="truncate">{topic.lastReplyBy ?? ""}</span>}
                </span>
                <span className="flex min-w-0 shrink-0 items-center gap-1">
                  {row?.starred ? <Star className="size-3 fill-current text-amber-400" /> : null}
                  <Chip compact dot={topic.replies > 50 ? "bg-orange-400" : topic.replies > 0 ? "bg-emerald-400" : "bg-content/30"}>
                    {topic.replies} replies
                  </Chip>
                </span>
              </span>
            </Card>
          </li>
        );
      })}
      {more ? <MoreButton loading={loading} onMore={onMore} /> : null}
    </ul>
  );
}

function NotificationList({ items, loading, more, onMore, onOpen }: {
  items: readonly V2exNotification[];
  loading: boolean;
  more: boolean;
  onMore: () => void;
  onOpen: (item: V2exNotification) => void;
}) {
  if (!items.length) return loading ? <ListSpinner /> : <p className="px-3 py-2 text-[12px] text-content/50">No notifications.</p>;
  return (
    <ul className="flex flex-col gap-0.5 p-1.5">
      {items.map((item) => (
        <li key={item.id}>
          <Card active={false} onClick={() => onOpen(item)}>
            <span className="flex items-center gap-2">
              <span className="flex min-w-0 flex-1 items-center gap-1.5">
                <FeedProviderMark provider="v2ex" />
                <Bell className="size-3 shrink-0 text-sky-400/90" />
                <span className="min-w-0 truncate text-[11px] text-content/50">Notification{item.member ? ` · ${item.member}` : ""}</span>
              </span>
              <span className="shrink-0 text-[11px] tabular-nums text-content/45">{relativeSeconds(item.created)}</span>
            </span>
            <span className="mt-1 line-clamp-2 text-[13px] font-semibold leading-snug text-content">{item.text}</span>
            {item.payload.trim() ? <span className="mt-1 line-clamp-2 text-[11px] text-content/45">{item.payload}</span> : null}
          </Card>
        </li>
      ))}
      {more ? <MoreButton loading={loading} onMore={onMore} /> : null}
    </ul>
  );
}

function AddNodeForm({ onAdd, onCancel }: { onAdd: (node: SavedNode) => void; onCancel: () => void }) {
  const [value, setValue] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const name = parseNodeName(value);
    if (!name) { setError("Use a node name like python, or its /go/ link."); return; }
    setBusy(true);
    setError(null);
    void v2exNode(name).then((node) => onAdd({ name: node.name, title: node.title }), (cause) => setError(String(cause)))
      .finally(() => setBusy(false));
  };

  return (
    <form onSubmit={submit} className="shrink-0 border-b border-stroke px-2 py-1.5">
      <div className="relative flex h-7 items-center">
        <Hashtag className="pointer-events-none absolute left-2 size-3 opacity-50" />
        <input autoFocus value={value} onChange={(event) => setValue(event.target.value)} disabled={busy}
          onKeyDown={(event) => { if (event.key === "Escape") onCancel(); }}
          placeholder="Node name or /go/ link, then Enter" aria-label="V2EX node" spellCheck={false} autoComplete="off"
          className="h-7 w-full rounded-md bg-content/5 pl-7 pr-7 text-[12px] outline-none placeholder:text-content/35" />
        {busy ? <LoaderCircle className="absolute right-2 size-3 animate-spin text-content/40" /> : null}
      </div>
      {error ? <p className="mt-1 px-1 text-[11px] text-red-400/90">{error}</p> : null}
    </form>
  );
}

function AccountPanel({ status, onChange }: { status: V2exStatus; onChange: (status: V2exStatus) => void }) {
  const [token, setToken] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const save = (event: FormEvent) => {
    event.preventDefault();
    if (!token.trim()) return;
    setBusy(true);
    setError(null);
    void setV2exToken(token).then((next) => { setToken(""); onChange(next); }, (cause) => setError(String(cause))).finally(() => setBusy(false));
  };

  const disconnect = () => {
    setBusy(true);
    void clearV2exToken().then(() => onChange({ connected: false }), (cause) => setError(String(cause))).finally(() => setBusy(false));
  };

  return (
    <div className="flex h-full min-h-0 min-w-0 flex-1 flex-col">
      <div className="shrink-0 border-b border-stroke">
        <header className="mx-auto flex w-full max-w-5xl flex-col gap-2.5 px-8 pb-5 pt-5">
          <div className="flex items-center gap-2 text-[12px] text-content/50">
            <FeedProviderMark provider="v2ex" />
            <span>Account</span>
            <span className={status.member ? "text-emerald-400/90" : ""}>{status.member ? "Connected" : status.connected ? "Token not confirmed" : "Not connected"}</span>
          </div>
          <h1 className="text-[20px] font-semibold leading-tight">V2EX account</h1>
          <p className="text-[12px] text-content/50">
            Hot, Latest and nodes work without an account. A personal access token adds your notifications and paged node lists.
            It stays on this computer, readable only by your user account.
          </p>
          {status.connected ? (
            <div className="flex items-center gap-2 pt-0.5 text-[12px] text-content/70">
              {status.member ? <Person name={`@${status.member.username}`} avatar={status.member.avatar} size={20} /> : <span>Token saved</span>}
              <button type="button" disabled={busy} onClick={disconnect} className={ACTION_GHOST}>Disconnect</button>
            </div>
          ) : null}
        </header>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        <form onSubmit={save} className="mx-auto flex w-full max-w-5xl flex-col gap-2 px-8 py-5">
          <label htmlFor="v2ex-token" className="text-[12px] text-content/60">Personal access token</label>
          <div className="max-w-md rounded-md border border-content/10 bg-content/5 focus-within:border-content/20">
            <input id="v2ex-token" type="password" value={token} onChange={(event) => setToken(event.target.value)} disabled={busy}
              placeholder="Paste a token" autoComplete="off" spellCheck={false}
              className="h-8 w-full bg-transparent px-3 text-[13px] text-content outline-none placeholder:text-content/35" />
          </div>
          {error ? <p role="alert" className="text-[12px] text-red-400/90">{error}</p> : null}
          <div className="mt-1 flex items-center gap-2">
            <button type="submit" disabled={busy || !token.trim()} className={ACTION_FILLED}>
              {busy ? "Checking…" : status.connected ? "Replace token" : "Connect"}
            </button>
            <button type="button" onClick={() => void openUrl("https://www.v2ex.com/settings/tokens")} className={ACTION_GHOST}>
              Create a token on V2EX
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
