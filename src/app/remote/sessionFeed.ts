import { persistableAttachment } from "../../features/sessions/model/attachments";
import type { Attachment, Block, QueuedMessage, Session } from "../../features/sessions/model/session";
import type { HostSettingValues } from "../../platform/hostSettings";

/** Every top-level session field but its identity and transcript. */
export type SessionMeta = Omit<Session, "id" | "blocks">;

export type SessionChange =
  /** Left the host's memory: detached, archived or deleted. */
  | { id: string; removed: true }
  | {
      id: string;
      /** Fields whose value changed. */
      meta?: Partial<SessionMeta>;
      /** Fields that were removed; JSON cannot carry `undefined`. */
      unset?: (keyof SessionMeta)[];
      /** Block ids in order, sent only when blocks were added, removed or moved. */
      order?: string[];
      /** New or replaced blocks, whole. */
      blocks?: Block[];
      /** Text a block gained while nothing else about it changed: streaming. */
      append?: { id: string; text: string }[];
    };

/**
 * What the host window tells connected devices about its sessions, and about
 * the settings that decide what it does (`platform/hostSettings`). `epoch` is
 * this page load of the host window; `seq` counts what it has sent since, and
 * a snapshot carries the `seq` it already includes. Settings share the count,
 * so a device that catches up gets them in order with the sessions. Session
 * order is not part of the feed: a mirror keeps its own and adds new sessions
 * at the end.
 */
export type SessionFeed =
  | { kind: "snapshot"; epoch: string; seq: number; sessions: Session[]; settings?: HostSettingValues }
  | { kind: "patch"; epoch: string; seq: number; changes: SessionChange[] }
  | { kind: "settings"; epoch: string; seq: number; values: HostSettingValues };

type Changed = Exclude<SessionChange, { removed: true }>;

// Object URLs and inline bytes mean nothing on another device, and the bytes
// can be megabytes; a mirror loads an attachment by its path instead.
const outgoingAttachments = (attachments: Attachment[]) => attachments.map(persistableAttachment);

function outgoingBlock(block: Block): Block {
  return block.attachments?.length ? { ...block, attachments: outgoingAttachments(block.attachments) } : block;
}

function outgoingQueue(messages: QueuedMessage[]): QueuedMessage[] {
  return messages.map((message) => message.attachments.length
    ? { ...message, attachments: outgoingAttachments(message.attachments) } : message);
}

function outgoingMeta<K extends keyof SessionMeta>(key: K, value: SessionMeta[K]): SessionMeta[K] {
  return key === "queuedMessages" && value ? outgoingQueue(value as QueuedMessage[]) as SessionMeta[K] : value;
}

/** A session as it may leave the host. */
export function outgoingSession(session: Session): Session {
  const blocks = session.blocks.map(outgoingBlock);
  const queued = session.queuedMessages && outgoingQueue(session.queuedMessages);
  return { ...session, blocks, ...(queued ? { queuedMessages: queued } : {}) };
}

/** True when `next` differs from `previous` only by text added at its end. */
function appendedText(previous: Block, next: Block): string | undefined {
  if (next.text.length <= previous.text.length || !next.text.startsWith(previous.text)) return undefined;
  const keys = new Set([...Object.keys(previous), ...Object.keys(next)]);
  for (const key of keys) {
    if (key !== "text" && previous[key as keyof Block] !== next[key as keyof Block]) return undefined;
  }
  return next.text.slice(previous.text.length);
}

function diffSession(previous: Session | undefined, next: Session): Changed | undefined {
  const change: Changed = { id: next.id };
  const meta: Partial<Record<keyof SessionMeta, unknown>> = {};
  const unset: (keyof SessionMeta)[] = [];
  const keys = new Set([...Object.keys(previous ?? {}), ...Object.keys(next)]) as Set<keyof Session>;
  for (const key of keys) {
    if (key === "id" || key === "blocks" || previous?.[key] === next[key]) continue;
    if (next[key] === undefined) unset.push(key);
    else meta[key] = outgoingMeta(key, next[key]);
  }
  if (Object.keys(meta).length) change.meta = meta as Partial<SessionMeta>;
  if (unset.length) change.unset = unset;

  if (previous?.blocks !== next.blocks) {
    const before = new Map(previous?.blocks.map((block) => [block.id, block]));
    const blocks: Block[] = [];
    const append: { id: string; text: string }[] = [];
    for (const block of next.blocks) {
      const old = before.get(block.id);
      if (old === block) continue;
      const text = old && appendedText(old, block);
      if (text !== undefined) append.push({ id: block.id, text });
      else blocks.push(outgoingBlock(block));
    }
    const reordered = !previous || previous.blocks.length !== next.blocks.length
      || next.blocks.some((block, index) => previous.blocks[index].id !== block.id);
    if (reordered) change.order = next.blocks.map((block) => block.id);
    if (blocks.length) change.blocks = blocks;
    if (append.length) change.append = append;
  }
  return Object.keys(change).length > 1 ? change : undefined;
}

/**
 * What changed from `previous` to `next`. Blocks and sessions are replaced,
 * never mutated, so unchanged ones are found by reference.
 */
export function diffSessions(previous: readonly Session[], next: readonly Session[]): SessionChange[] {
  const before = new Map(previous.map((session) => [session.id, session]));
  const changes: SessionChange[] = [];
  for (const session of next) {
    const old = before.get(session.id);
    before.delete(session.id);
    if (old === session) continue;
    const change = diffSession(old, session);
    if (change) changes.push(change);
  }
  for (const id of before.keys()) changes.push({ id, removed: true });
  return changes;
}

function applyChange(session: Session | undefined, change: Changed): Session {
  const next = { ...session, ...change.meta, id: change.id } as Session;
  for (const key of change.unset ?? []) delete (next as Partial<Session>)[key];
  if (!change.order && !change.blocks && !change.append) return next;
  const blocks = new Map(session?.blocks.map((block) => [block.id, block]));
  for (const block of change.blocks ?? []) blocks.set(block.id, block);
  for (const { id, text } of change.append ?? []) {
    const block = blocks.get(id);
    if (block) blocks.set(id, { ...block, text: block.text + text });
  }
  const order = change.order ?? session?.blocks.map((block) => block.id) ?? [];
  next.blocks = order.flatMap((id) => blocks.get(id) ?? []);
  return next;
}

/** A mirror's sessions after a patch. */
export function applySessionChanges(sessions: readonly Session[], changes: readonly SessionChange[]): Session[] {
  const byId = new Map(changes.map((change) => [change.id, change]));
  const next: Session[] = [];
  for (const session of sessions) {
    const change = byId.get(session.id);
    byId.delete(session.id);
    if (!change) next.push(session);
    else if (!("removed" in change)) next.push(applyChange(session, change));
  }
  for (const change of byId.values()) if (!("removed" in change)) next.push(applyChange(undefined, change));
  return next;
}

// A hidden run (an agent's habit) is never shown, so it is never sent.
const shared = (sessions: readonly Session[]) => sessions.filter((session) => !session.ephemeral);

/**
 * The host window's side of the feed: collects changes for `delayMs` and
 * sends one patch for them, measured against what it last sent, so a burst of
 * streaming frames costs one diff. `settings` reads the host's shared
 * settings for snapshots.
 */
export function createSessionFeed(initial: readonly Session[], publish: (feed: SessionFeed) => void,
  { delayMs = 50, settings }: { delayMs?: number; settings?: () => HostSettingValues } = {}) {
  const epoch = crypto.randomUUID();
  let seq = 0;
  let sent = shared(initial);
  let latest = sent;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let settingsSent: HostSettingValues = settings?.() ?? {};

  const flush = () => {
    clearTimeout(timer);
    timer = undefined;
    const changes = diffSessions(sent, latest);
    sent = latest;
    if (changes.length) publish({ kind: "patch", epoch, seq: ++seq, changes });
  };

  return {
    changed(sessions: readonly Session[]) {
      latest = shared(sessions);
      timer ??= setTimeout(flush, delayMs);
    },
    flush,
    /** Settings whose value differs from what devices were last told; sessions changed first go out first. */
    settingsChanged(values: HostSettingValues) {
      const changed = Object.fromEntries(Object.entries(values).filter(([key, value]) => settingsSent[key] !== value));
      if (!Object.keys(changed).length) return;
      flush();
      settingsSent = { ...settingsSent, ...changed };
      publish({ kind: "settings", epoch, seq: ++seq, values: changed });
    },
    /** Everything sent so far, as one message; a patch with a larger `seq` follows it. */
    snapshot(): SessionFeed {
      flush();
      if (!settings) return { kind: "snapshot", epoch, seq, sessions: sent.map(outgoingSession) };
      // Anything changed since the last message is in here, so it need not be sent again.
      settingsSent = settings();
      return { kind: "snapshot", epoch, seq, sessions: sent.map(outgoingSession), settings: settingsSent };
    },
    dispose() { clearTimeout(timer); },
  };
}

export type SessionFeedPublisher = ReturnType<typeof createSessionFeed>;
