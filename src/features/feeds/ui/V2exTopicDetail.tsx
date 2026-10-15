import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useRef, useState } from "react";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { ExternalLink, Hashtag, LoaderCircle, MessageMultiple, MessageSquare, RefreshCw, Star, StickyNote } from "../../../shared/ui/icons";
import { formatRelativeTime } from "../../../shared/lib/relativeTime";
import { v2exReplies, v2exTopic, type V2exReply, type V2exTopic } from "../model/v2ex";
import { v2exTopicMarkdown } from "../model/feedContext";
import { ACTION_FILLED, ACTION_GHOST, ACTION_OUTLINE, Avatar, Chip, IconButton, Person } from "../../../shared/ui/inboxParts";
import { V2exMark } from "./feedUi";

type Props = {
  /** What the list knows; the detail refetches the full topic and replies. */
  topic: V2exTopic;
  /** Reply count at the previous visit, to mark what's new. */
  seenCount: number | null;
  starred: boolean;
  onSeen: (topic: V2exTopic, replyCount: number) => void;
  onToggleStar: (topic: V2exTopic) => void;
  onSendToAgent: (topic: V2exTopic, replies: V2exReply[]) => void;
  onSaveNote: (title: string, body: string) => Promise<void>;
};

export const relativeSeconds = (seconds: number) => (seconds > 0 ? formatRelativeTime(new Date(seconds * 1000).toISOString()) : "");

export function V2exTopicDetail({ topic: summary, seenCount, starred, onSeen, onToggleStar, onSendToAgent, onSaveNote }: Props) {
  const [topic, setTopic] = useState(summary);
  const [replies, setReplies] = useState<V2exReply[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [reload, setReload] = useState(0);
  // The new-reply divider stays where it was when the topic opened, even
  // after the visit marks everything seen.
  const [firstNew] = useState(() => seenCount);
  const onSeenRef = useRef(onSeen);
  onSeenRef.current = onSeen;

  useEffect(() => {
    let live = true;
    setError(null);
    void Promise.all([v2exTopic(summary.id).catch(() => summary), v2exReplies(summary.id)]).then(([full, list]) => {
      if (!live) return;
      setTopic(full);
      setReplies(list);
      onSeenRef.current(full, Math.max(full.replies, list.length));
    }, (cause) => {
      if (live) setError(cause instanceof Error ? cause.message : String(cause));
    });
    return () => { live = false; };
  }, [summary, reload]);

  const newFrom = firstNew != null && replies && firstNew < replies.length ? firstNew : null;

  const saveNote = async () => {
    setSaving(true);
    try {
      await onSaveNote(topic.title, v2exTopicMarkdown(topic, replies ?? []));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="flex h-full min-h-0 min-w-0 flex-1 flex-col">
      <div className="relative z-10 shrink-0 border-b border-stroke">
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-2.5 px-8 pb-5 pt-5">
          <header className="flex flex-col gap-2.5">
            <div className="flex min-w-0 items-center gap-2 text-[12px] text-content/50">
              <V2exMark />
              <span className="shrink-0">Topic</span>
              <span className="shrink-0 tabular-nums">#{topic.id}</span>
              {topic.node ? (
                <span className="flex shrink-0 items-center gap-1 text-emerald-400/90">
                  <Hashtag className="size-3.5" />{topic.node.title}
                </span>
              ) : null}
              <span className="flex shrink-0 items-center gap-1">
                <MessageMultiple className="size-3.5" />{topic.replies}
              </span>
              <span className="ml-auto shrink-0">
                <IconButton label="Reload" onClick={() => setReload((value) => value + 1)}>
                  {replies || error ? <RefreshCw className="size-3.5" /> : <LoaderCircle className="size-3.5 animate-spin" />}
                </IconButton>
              </span>
            </div>
            <h1 className="line-clamp-2 text-[20px] font-semibold leading-tight text-content">{topic.title}</h1>
            <div className="flex min-w-0 items-center gap-2 overflow-hidden whitespace-nowrap text-[12px] text-content/50">
              {topic.member ? <Person name={topic.member.username} avatar={topic.member.avatar} /> : <span>Unknown</span>}
              <span aria-hidden>·</span>
              <time>Created {relativeSeconds(topic.created)}</time>
              {topic.lastReplyBy ? (
                <>
                  <span aria-hidden>·</span>
                  <span className="truncate">Last reply {relativeSeconds(topic.lastTouched)} by {topic.lastReplyBy}</span>
                </>
              ) : null}
            </div>
            <div className="flex flex-wrap items-center gap-2 pt-0.5">
              <button type="button" disabled={!replies} onClick={() => replies && onSendToAgent(topic, replies)} className={ACTION_FILLED}>
                Send to agent
              </button>
              <button type="button" disabled={!replies || saving} onClick={() => void saveNote()} className={ACTION_OUTLINE}>
                <StickyNote className="size-3.5" /> Save as note
              </button>
              <button type="button" onClick={() => onToggleStar(topic)} className={ACTION_OUTLINE} aria-pressed={starred}>
                <Star className={`size-3.5 ${starred ? "fill-current text-amber-400" : ""}`} /> {starred ? "Starred" : "Star"}
              </button>
              <button type="button" onClick={() => void openUrl(topic.url)} className={ACTION_GHOST}>
                <ExternalLink className="size-3.5" /> Open on V2EX
              </button>
            </div>
          </header>
        </div>
      </div>
      <div className="min-h-0 min-w-0 flex-1 overflow-y-auto overscroll-none">
        <div className="mx-auto flex w-full max-w-5xl flex-col gap-5 px-8 py-5">
          {topic.content.trim()
            ? <AgentMarkdown text={topic.content} hardBreaks sourceUrl={topic.url} className="text-[14px]" />
            : <p className="text-[13px] text-content/40">No body.</p>}
          <section aria-label="Replies" className="flex flex-col gap-3 border-t border-stroke pt-5">
            <h2 className="flex items-center gap-1.5 text-[12px] font-medium text-content/60">
              <MessageSquare className="size-3.5" /> {replies ? `${replies.length} replies` : "Replies"}
            </h2>
            {error ? <p role="alert" className="text-[12px] text-red-400/90">{error}</p>
              : !replies ? <div className="flex justify-center py-6 text-content/40"><LoaderCircle className="size-4 animate-spin" /></div>
              : replies.length === 0 ? <p className="text-[12px] text-content/40">No replies yet.</p>
              : <ol className="flex flex-col">
                {replies.map((reply, index) => (
                  <li key={reply.id}>
                    {index === newFrom ? <NewRepliesDivider count={replies.length - index} /> : null}
                    <ReplyRow reply={reply} floor={index + 1} op={!!reply.member && reply.member.username === topic.member?.username} />
                  </li>
                ))}
              </ol>}
            <div className="flex justify-end">
              <button type="button" onClick={() => void openUrl(`${topic.url}#reply${topic.replies}`)} className={ACTION_GHOST}>
                <MessageSquare className="size-3.5" /> Reply on V2EX
              </button>
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}

function ReplyRow({ reply, floor, op }: { reply: V2exReply; floor: number; op: boolean }) {
  return (
    <div className="flex gap-3 border-b border-stroke py-3 last:border-b-0">
      <Avatar src={reply.member?.avatar} name={reply.member?.username} size={24} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2 text-[12px] text-content/50">
          <span className="font-medium text-content/80">{reply.member?.username ?? "someone"}</span>
          {op ? <Chip dot="bg-accent" compact>OP</Chip> : null}
          <span>{relativeSeconds(reply.created)}</span>
          <span className="ml-auto tabular-nums text-content/35">#{floor}</span>
        </div>
        <AgentMarkdown text={reply.content} hardBreaks className="mt-1 text-[13px]" />
      </div>
    </div>
  );
}

function NewRepliesDivider({ count }: { count: number }) {
  return (
    <div role="separator" className="my-1 flex items-center gap-2 text-[10px] font-medium uppercase tracking-wide text-accent">
      <span className="h-px flex-1 bg-accent/40" />
      {count} new
      <span className="h-px flex-1 bg-accent/40" />
    </div>
  );
}
