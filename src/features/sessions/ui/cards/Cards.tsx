import { createContext, useContext, useMemo, useRef, useState } from "react";
import { requestOpenAppResource } from "../../../../shared/lib/appResourceLinks";
import { Check, ChevronRight, File, Palette } from "../../../../shared/ui/icons";
import { CourseHostContext } from "../../../learning/model/courseContext";
import { agentForSession } from "../../../agents/model/agent";
import {
  openDocument,
  parseCanvasLink,
  parseDocument,
  parseMindmap,
  parseTodo,
  sendCardReply,
  type MindmapNode,
} from "../../model/cards";

// One width for every card, so several in a reply line up.
const shell = "my-1.5 w-full max-w-[34rem] rounded-2xl border border-stroke bg-background-base/50 font-sans";

const NO_REPLIES: ReadonlySet<string> = new Set();
/** The user's messages in the conversation a card sits in: its only memory of what was done with it. */
export const CardRepliesContext = createContext<ReadonlySet<string>>(NO_REPLIES);

/** A card's line of text, with `code` spans drawn as code. */
function inline(text: string) {
  if (!text.includes("`")) return text;
  return text.split(/(`[^`]+`)/).map((part, index) =>
    part.length > 2 && part.startsWith("`") && part.endsWith("`")
      ? <code key={index} className="rounded bg-content/10 px-1 py-px font-mono text-[0.92em]">{part.slice(1, -1)}</code>
      : part);
}

/** A document the agent wrote: its name in the chat, its text beside it on a click. */
export function DocumentCard({ source, incomplete }: { source: string; incomplete: boolean }) {
  const host = useContext(CourseHostContext);
  const document = useMemo(() => parseDocument(source), [source]);
  const words = document ? document.body.trim().split(/\s+/).filter(Boolean).length : 0;
  if (!document && !incomplete) return null;
  if (host?.agentId) return <button type="button" data-card="document" className="agent-resource-chip" disabled={incomplete || !document}
    aria-label={`Open document ${document?.title ?? "Document"}`} title={incomplete ? "Writing document…" : document?.subject ?? "Open document"}
    onClick={() => document && openDocument(document, host.agentId)}><File /><span>{incomplete ? "Writing document…" : document?.title}</span></button>;

  return (
    <button type="button" data-card="document" disabled={incomplete || !document} onClick={(event) => {
      if (!document) return;
      const sessionId = event.currentTarget.closest<HTMLElement>("[data-session-drop]")?.dataset.sessionDrop;
      openDocument(document, sessionId ? agentForSession(sessionId)?.id : undefined);
    }}
      className={`${shell} flex items-center gap-3 px-3.5 py-3 text-left enabled:hover:bg-content/6 disabled:cursor-default`}>
      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-content/8 text-content/60">
        <File className="size-4" strokeWidth={1.5} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-[13px] font-medium text-content">{document?.title ?? "Document"}</span>
        <span className="truncate text-xs text-content/45">
          {incomplete ? "Writing…" : [document?.subject, "Document", words ? `${words.toLocaleString()} words` : ""].filter(Boolean).join(" · ")}
        </span>
      </span>
      {incomplete ? null : <ChevronRight className="size-3.5 shrink-0 text-content/35" strokeWidth={1.5} />}
    </button>
  );
}

/** A canvas the agent made or changed: its name in the chat, the canvas itself on a click. */
export function CanvasCard({ source }: { source: string }) {
  const host = useContext(CourseHostContext);
  const link = useMemo(() => parseCanvasLink(source), [source]);
  if (!link) return null;
  if (host?.agentId) return <button type="button" data-card="canvas" className="agent-resource-chip" aria-label={`Open canvas ${link.title ?? "Canvas"}`} onClick={() => requestOpenAppResource({ kind: "canvas", id: link.id })}><Palette /><span>{link.title ?? "Canvas"}</span></button>;
  return (
    <button type="button" data-card="canvas" onClick={() => requestOpenAppResource({ kind: "canvas", id: link.id })}
      className={`${shell} flex items-center gap-3 px-3.5 py-3 text-left hover:bg-content/6`}>
      <span className="grid size-9 shrink-0 place-items-center rounded-xl bg-content/8 text-content/60">
        <Palette className="size-4" strokeWidth={1.5} />
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-[13px] font-medium text-content">{link.title ?? "Canvas"}</span>
        <span className="truncate text-xs text-content/45">Canvas · Open</span>
      </span>
      <ChevronRight className="size-3.5 shrink-0 text-content/35" strokeWidth={1.5} />
    </button>
  );
}

/** A checklist. Ticking an item tells the agent it is done; the agent keeps the progress. */
export function TodoCard({ source }: { source: string }) {
  const list = useMemo(() => parseTodo(source), [source]);
  // Ticked here but not yet redrawn by the agent.
  const [ticked, setTicked] = useState<ReadonlySet<number>>(new Set());
  // What the user already told the agent is done, so a tick survives a restart without the card keeping it.
  const replies = useContext(CardRepliesContext);
  const root = useRef<HTMLDivElement>(null);
  if (!list) return null;
  const done = list.items.filter((item, index) => item.done || ticked.has(index) || replies.has(`Done: ${item.text}`)).length;
  return (
    <div ref={root} data-card="todo" className={`${shell} flex flex-col gap-1 p-3`}>
      <div className="flex items-baseline gap-2 px-1 pb-1">
        <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-content">{list.title ?? "To do"}</span>
        <span className="shrink-0 text-xs tabular-nums text-content/45">{done}/{list.items.length}</span>
      </div>
      {list.items.map((item, index) => {
        const checked = item.done || ticked.has(index) || replies.has(`Done: ${item.text}`);
        return (
          <button key={`${index}:${item.text}`} type="button" role="checkbox" aria-checked={checked} disabled={checked}
            onClick={() => {
              setTicked((current) => new Set(current).add(index));
              if (root.current) sendCardReply(root.current, `Done: ${item.text}`);
            }}
            className="flex w-full items-start gap-2.5 rounded-lg px-1 py-1 text-left enabled:hover:bg-content/6 disabled:cursor-default">
            <span className={`mt-0.5 grid size-4 shrink-0 place-items-center rounded-[5px] border ${checked ? "border-transparent bg-content text-background-base" : "border-content/30"}`}>
              {checked ? <Check className="size-3" strokeWidth={2.5} /> : null}
            </span>
            <span className={`min-w-0 flex-1 text-[13px] leading-snug ${checked ? "text-content/45 line-through" : "text-content"}`}>{inline(item.text)}</span>
          </button>
        );
      })}
    </div>
  );
}


/** One idea and, to its right, the ideas under it, joined by a rail. */
function MindmapBranch({ node, depth }: { node: MindmapNode; depth: number }) {
  const [open, setOpen] = useState(depth < 3);
  const leaf = node.children.length === 0;
  return (
    <li className="flex items-center gap-2">
      <button type="button" disabled={leaf} aria-expanded={leaf ? undefined : open} onClick={() => setOpen((value) => !value)}
        title={leaf ? undefined : open ? "Fold" : `Unfold ${node.children.length}`}
        className={`flex max-w-[16rem] shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-1 text-left text-[13px] leading-snug enabled:hover:brightness-125 disabled:cursor-default ${depth === 0 ? "bg-content font-medium text-background-base" : leaf ? "text-content/75" : "bg-content/10 text-content"}`}>
        <span className="min-w-0">{inline(node.text)}</span>
        {!leaf && !open ? <span className="shrink-0 rounded-full bg-content/15 px-1.5 text-[11px] tabular-nums text-content/60">{node.children.length}</span> : null}
      </button>
      {!leaf && open ? (
        <ul className="flex flex-col gap-1 border-l border-content/20 pl-2">
          {node.children.map((child, index) => <MindmapBranch key={`${index}:${child.text}`} node={child} depth={depth + 1} />)}
        </ul>
      ) : null}
    </li>
  );
}

export function MindmapCard({ source }: { source: string }) {
  const root = useMemo(() => parseMindmap(source), [source]);
  if (!root) return null;
  const branches = root.text ? [root] : root.children;
  return (
    <div data-card="mindmap" className={`${shell} overflow-x-auto p-3`}>
      <ul className="flex w-max flex-col gap-2">
        {branches.map((node, index) => <MindmapBranch key={`${index}:${node.text}`} node={node} depth={root.text ? 0 : 1} />)}
      </ul>
    </div>
  );
}
