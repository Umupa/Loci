import { useEffect, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { AgentMarkdown } from "../../sessions/ui/AgentMarkdown";
import { answerAfter, askOnLesson, keepLessonAnswer, type LessonQuestion, type LessonThread } from "../model/lessonQuestions";
import { resolveAnchor } from "../model/textAnchor";
import type { TextAnchor } from "../model/types";
import { useLessonSession, type LessonSession } from "./lessonSession";
import "./LessonMargin.css";

/** Room a margin needs beside the text: its notes and the gap before them. */
const MARGIN_ROOM = 340;

/** The element a lesson's blocks are the children of. */
function flowRoot(text: HTMLElement): HTMLElement {
  return text.querySelector<HTMLElement>(".agent-markdown") ?? text;
}

/** The top-level block holding a passage, which its note sits beside (or under). */
function blockOf(text: HTMLElement, anchor: TextAnchor): HTMLElement | null {
  const range = resolveAnchor(text, anchor);
  if (!range) return null;
  const root = flowRoot(text);
  let node: Node | null = range.startContainer;
  let element = node instanceof HTMLElement ? node : node?.parentElement ?? null;
  while (element && element.parentElement && element.parentElement !== root) element = element.parentElement;
  return element && element.parentElement === root ? element : null;
}

/** Whether the reader has room beside the text for notes, kept current as it resizes. */
function useWideMargin(article: HTMLElement | null): boolean {
  const [wide, setWide] = useState(true);
  useEffect(() => {
    const scroll = article?.closest<HTMLElement>("[data-reading-scroll]");
    if (!article || !scroll) return;
    const measure = () => setWide((scroll.clientWidth - article.offsetWidth) / 2 >= MARGIN_ROOM);
    measure();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measure);
    observer?.observe(scroll);
    observer?.observe(article);
    return () => observer?.disconnect();
  }, [article]);
  return wide;
}

type Note = { key: string; passage: TextAnchor; thread?: LessonThread };

/**
 * A lesson's margin: each question asked on a passage, with the mentor's
 * answer, beside that passage, and the box for a new one. They are messages
 * in the mentor's conversation, shown again where they were asked; a thread
 * of several folds to its latest. Without room beside the text, a note sits
 * under its paragraph instead.
 */
export function LessonMargin({ article, threads, draft, onDraftDone }: {
  /** The lesson's article: its text is inside, and its notes are placed against it. */
  article: HTMLElement | null;
  threads: readonly LessonThread[];
  /** A passage just chosen to ask about. */
  draft: TextAnchor | null;
  onDraftDone: () => void;
}) {
  const session = useLessonSession();
  const wide = useWideMargin(article);
  const notes = useMemo<Note[]>(() => [
    ...threads.flatMap((thread) => thread.passage ? [{ key: thread.id, passage: thread.passage, thread }] : []),
    ...(draft ? [{ key: "draft", passage: draft }] : []),
  ], [threads, draft]);
  const [hosts, setHosts] = useState<Map<string, HTMLElement>>(new Map());
  const [open, setOpen] = useState<string | null>(null);

  // A host for each note, put into the text beside (or after) its block.
  const noteKeys = notes.map((note) => `${note.key}:${note.passage.start}:${note.passage.exact.length}`).join("|");
  useLayoutEffect(() => {
    const text = article?.querySelector<HTMLElement>("[data-reading-text]");
    if (!text) { setHosts(new Map()); return; }
    const made = new Map<string, HTMLElement>();
    for (const note of notes) {
      const block = blockOf(text, note.passage);
      if (!block) continue;
      const host = document.createElement("div");
      host.className = "lesson-note-host";
      host.dataset.wide = wide ? "true" : "false";
      host.dataset.lessonNote = note.key;
      if (wide) block.before(host); else block.after(host);
      made.set(note.key, host);
    }
    setHosts(made);
    return () => { for (const host of made.values()) host.remove(); };
  }, [article, noteKeys, wide]); // eslint-disable-line react-hooks/exhaustive-deps

  // Notes in the margin are kept from overlapping: each sits below the one above.
  useLayoutEffect(() => {
    if (!wide || !hosts.size) return;
    const place = () => {
      const ordered = [...hosts.values()];
      for (const host of ordered) host.style.transform = "";
      ordered.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);
      let bottom = -Infinity;
      for (const host of ordered) {
        const rect = host.getBoundingClientRect();
        const shift = Math.max(0, bottom + 10 - rect.top);
        if (shift) host.style.transform = `translateY(${shift}px)`;
        bottom = rect.top + shift + rect.height;
      }
    };
    place();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(place);
    for (const host of hosts.values()) observer?.observe(host);
    return () => observer?.disconnect();
  }, [hosts, wide]);

  if (!session?.sessionId) return null;
  return <>{notes.map((note) => {
    const host = hosts.get(note.key);
    if (!host) return null;
    return createPortal(note.thread
      ? <ThreadNote thread={note.thread} session={session} open={open === note.key} onToggle={() => setOpen((current) => current === note.key ? null : note.key)} />
      : <AskBox session={session} passage={note.passage} autoFocus placeholder="Ask about this passage…" onSent={onDraftDone} onCancel={onDraftDone} />, host);
  })}</>;
}

/** A question's answer: as it is being written, else as it was kept. */
export function answerOf(question: LessonQuestion, session: LessonSession): { text: string; streaming: boolean; waiting: boolean } {
  const live = answerAfter(session.blocks, question.messageId);
  // A finished answer that was never kept is kept now.
  if (live?.id && live.text && !live.streaming && !session.busy && !question.answer)
    keepLessonAnswer({ agentId: session.agentId, courseId: question.courseId, lessonId: question.lessonId }, question.messageId, live.id, live.text);
  if (live && (live.text || live.streaming)) return { text: live.text, streaming: live.streaming, waiting: false };
  if (question.answer) return { text: question.answer, streaming: false, waiting: false };
  // Asked and in the conversation, with the turn still running: the answer is on its way.
  return { text: "", streaming: false, waiting: !!live && session.busy };
}

function QuestionAndAnswer({ question, session, clamp }: { question: LessonQuestion; session: LessonSession; clamp: boolean }) {
  const answer = answerOf(question, session);
  return <div className="lesson-note__item" data-question={question.messageId}>
    <p className="lesson-note__question">{question.text}</p>
    {answer.text ? <div className={`lesson-note__answer${clamp ? " lesson-note__answer--clamped" : ""}`}>
      <AgentMarkdown text={answer.text} streaming={answer.streaming} />
    </div> : answer.waiting ? <p className="lesson-note__waiting" role="status">…</p> : null}
  </div>;
}

/** One thread on a passage: its latest question and answer, or all of them with a box to follow up. */
function ThreadNote({ thread, session, open, onToggle }: { thread: LessonThread; session: LessonSession; open: boolean; onToggle: () => void }) {
  const latest = thread.questions[thread.questions.length - 1];
  const earlier = thread.questions.length - 1;
  return <aside className="lesson-note" data-open={open || undefined} aria-label={`Asked: ${thread.questions[0].text}`}>
    {open ? <>
      {thread.questions.map((question) => <QuestionAndAnswer key={question.messageId} question={question} session={session} clamp={false} />)}
      <AskBox session={session} passage={thread.passage} threadId={thread.id} placeholder="Ask more…" />
      <button type="button" className="lesson-note__fold" onClick={onToggle}>Fold</button>
    </> : <button type="button" className="lesson-note__summary" onClick={onToggle} title="Show the thread and ask more">
      <QuestionAndAnswer question={latest} session={session} clamp />
      {earlier ? <span className="lesson-note__count">+{earlier}</span> : null}
    </button>}
  </aside>;
}

/** A box that asks the mentor directly: on a passage, following up a thread, or on the lesson. */
export function AskBox({ session, passage, threadId, placeholder, autoFocus, onSent, onCancel, className }: {
  session: LessonSession; passage?: TextAnchor; threadId?: string; placeholder: string; autoFocus?: boolean;
  onSent?: () => void; onCancel?: () => void; className?: string;
}) {
  const [text, setText] = useState("");
  const field = useRef<HTMLTextAreaElement>(null);
  useEffect(() => { if (autoFocus) field.current?.focus({ preventScroll: true }); }, [autoFocus]);
  const send = () => {
    const question = text.trim();
    if (!question || !session.sessionId) return;
    askOnLesson({ agentId: session.agentId, sessionId: session.sessionId, question, ...(passage ? { passage } : {}), ...(threadId ? { threadId } : {}) });
    setText("");
    onSent?.();
  };
  const keys = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (event.nativeEvent.isComposing) return;
    if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); send(); }
    else if (event.key === "Escape" && onCancel) { event.preventDefault(); event.stopPropagation(); onCancel(); }
  };
  return <textarea ref={field} className={`lesson-ask ${className ?? ""}`} rows={1} value={text} placeholder={placeholder} aria-label={placeholder}
    onChange={(event) => setText(event.target.value)} onKeyDown={keys}
    onBlur={() => { if (!text.trim()) onCancel?.(); }} />;
}
