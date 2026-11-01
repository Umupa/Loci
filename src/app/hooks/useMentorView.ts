import { useCallback, useRef, useState } from "react";
import { isLibrarySegment, type LibrarySegment } from "../../features/mentor/model/libraryCourse";
import { parseStoredPage, samePage, storedPage, type MentorLesson, type MentorPage } from "../../features/mentor/model/mentorPage";
import { requestFilePlace } from "../../features/files/model/filePlace";
import { mirrorViewState } from "../../features/agents/model/mentorStore";

export type MentorViewState = {
  /** What the reader shows; nothing leaves it empty. */
  page?: MentorPage;
  /** The lesson on screen when the page is a course. */
  lesson?: MentorLesson;
  /** Bumped by every explicit opening, so asking for the same lesson again selects it. */
  request: number;
  /** The page came back from a previous visit and has not been checked yet. */
  restored?: boolean;
  /** The outline and library column on the left. */
  library: boolean;
  libraryWidth: number;
  /** Which kind of thing the library shows; unset picks one from what the mentor has. */
  segment?: LibrarySegment;
  /** The course the library's Courses segment shows. */
  course?: string;
  /** The library's filter text, for this window only. */
  filter?: { segment: LibrarySegment; text: string };
  /** The conversation column on the right. */
  chat: boolean;
  chatWidth: number;
};

/** Earlier versions kept the same per-agent preferences here; their extra fields are ignored. */
export const MENTOR_VIEW_KEY = "loci:agent-overviews.v1";
export const DEFAULT_MENTOR_VIEW: MentorViewState = { request: 0, library: true, libraryWidth: 260, chat: true, chatWidth: 420 };
const width = (value: unknown, min: number, fallback: number) => typeof value === "number" && Number.isFinite(value) ? Math.max(min, value) : fallback;

function read(): Record<string, MentorViewState> {
  try {
    const value = JSON.parse(localStorage.getItem(MENTOR_VIEW_KEY) ?? "{}");
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).flatMap(([id, raw]) => {
      if (!raw || typeof raw !== "object" || !/^[A-Za-z0-9_-]+$/.test(id)) return [];
      const item = raw as Record<string, unknown>;
      const page = parseStoredPage(item.page);
      return [[id, {
        ...(page ? { page, restored: true } : {}),
        request: 0,
        library: typeof item.library === "boolean" ? item.library : DEFAULT_MENTOR_VIEW.library,
        libraryWidth: width(item.libraryWidth, 200, DEFAULT_MENTOR_VIEW.libraryWidth),
        ...(isLibrarySegment(item.segment) ? { segment: item.segment } : {}),
        ...(typeof item.course === "string" && /^[A-Za-z0-9_-]+$/.test(item.course) ? { course: item.course } : {}),
        chat: typeof item.chat === "boolean" ? item.chat : DEFAULT_MENTOR_VIEW.chat,
        // `width` was the conversation's width before the reader moved to the middle.
        chatWidth: width(item.width, 320, DEFAULT_MENTOR_VIEW.chatWidth),
      }]];
    }));
  } catch { return {}; }
}

function write(states: Record<string, MentorViewState>) {
  const stored = Object.fromEntries(Object.entries(states).map(([id, state]) => [id, {
    library: state.library, libraryWidth: state.libraryWidth, chat: state.chat, width: state.chatWidth,
    ...(state.segment ? { segment: state.segment } : {}),
    ...(state.course ? { course: state.course } : {}),
    ...(state.page ? { page: storedPage(state.page, state.lesson) } : {}),
  }]));
  // Also kept in SQLite (mentor_state), where it outlives this WebView's storage.
  mirrorViewState(stored);
  try {
    localStorage.setItem(MENTOR_VIEW_KEY, JSON.stringify(stored));
  } catch { /* This window keeps its view even when storage is unavailable. */ }
}

/** A page the reader showed, to come back to: with its lesson, and the line navigation left. */
export type HistoryEntry = { page: MentorPage; lesson?: MentorLesson; line?: number };
type History = { back: HistoryEntry[]; forward: HistoryEntry[] };
/** How far back the reader remembers, per mentor. */
export const HISTORY_MAX = 50;

/** Options of an opening: the line it left in the page before (for Back). */
export type ShowOptions = { fromLine?: number };

/** The page an entry reopens: a course at the lesson it was on. */
function entryPage(entry: HistoryEntry): MentorPage {
  if (entry.page.kind === "course" && entry.lesson) return { kind: "course", course: { ...entry.page.course, itemId: entry.lesson.id } };
  return entry.page;
}

/**
 * Each mentor keeps its own reader and columns. Coming back to a mentor opens
 * the page, and in a course the lesson, it was showing.
 */
export function useMentorView() {
  const [states, setStates] = useState(read);
  const latest = useRef(states);
  // Back and forward, per mentor, for this window's life only (like a browser tab's).
  const histories = useRef(new Map<string, History>());
  const [, setHistoryVersion] = useState(0);
  const historyOf = (id: string): History => {
    let history = histories.current.get(id);
    if (!history) { history = { back: [], forward: [] }; histories.current.set(id, history); }
    return history;
  };
  const remember = (id: string, state: MentorViewState, line?: number) => {
    if (!state.page) return;
    const history = historyOf(id);
    history.back = [...history.back, { page: state.page, ...(state.lesson ? { lesson: state.lesson } : {}), ...(line ? { line } : {}) }].slice(-HISTORY_MAX);
    history.forward = [];
    setHistoryVersion((version) => version + 1);
  };
  const update = useCallback((id: string, edit: (state: MentorViewState) => MentorViewState) => {
    const before = latest.current[id] ?? DEFAULT_MENTOR_VIEW;
    const after = edit(before);
    if (after === before) return;
    const next = { ...latest.current, [id]: after };
    latest.current = next;
    setStates(next);
    write(next);
  }, []);
  const show = useCallback((id: string, page: MentorPage, options: ShowOptions = {}) => update(id, (state) => {
    // Every replacement can be gone back from; so can a jump within the same file.
    if (state.page && (!samePage(state.page, page) || options.fromLine !== undefined)) remember(id, state, options.fromLine);
    return ({
    ...state, page, request: state.request + 1, restored: false,
    // The library's Courses segment follows the course being read.
    ...(page.kind === "course" ? { course: page.course.courseId } : {}),
    // A different course starts without the previous one's lesson.
    lesson: page.kind === "course" && state.page?.kind === "course" && state.page.course.courseId === page.course.courseId ? state.lesson : undefined,
  }); }), [update]); // eslint-disable-line react-hooks/exhaustive-deps
  const close = useCallback((id: string) => update(id, (state) => {
    if (!state.page) return state;
    remember(id, state);
    return { ...state, page: undefined, lesson: undefined, restored: false };
  }), [update]); // eslint-disable-line react-hooks/exhaustive-deps
  /** Back (-1) or forward (1) through the pages this mentor's reader showed; false when there is none. */
  const go = useCallback((id: string, direction: -1 | 1): boolean => {
    const history = historyOf(id);
    const from = direction < 0 ? history.back : history.forward;
    const entry = from[from.length - 1];
    if (!entry) return false;
    const state = latest.current[id] ?? DEFAULT_MENTOR_VIEW;
    const current: HistoryEntry | undefined = state.page ? { page: state.page, ...(state.lesson ? { lesson: state.lesson } : {}) } : undefined;
    if (direction < 0) { history.back = from.slice(0, -1); if (current) history.forward = [...history.forward, current]; }
    else { history.forward = from.slice(0, -1); if (current) history.back = [...history.back, current].slice(-HISTORY_MAX); }
    setHistoryVersion((version) => version + 1);
    const page = entryPage(entry);
    if (entry.line && page.kind === "file") requestFilePlace(page.path, { lines: [entry.line, entry.line] });
    update(id, (before) => ({
      ...before, page, request: before.request + 1, restored: false,
      ...(page.kind === "course" ? { course: page.course.courseId } : {}),
      lesson: page.kind === "course" ? entry.lesson : undefined,
    }));
    return true;
  }, [update]); // eslint-disable-line react-hooks/exhaustive-deps
  const setLesson = useCallback((id: string, lesson: MentorLesson | null) => update(id, (state) => {
    if (state.page?.kind !== "course") return state;
    if ((state.lesson?.id ?? null) === (lesson?.id ?? null) && state.lesson?.title === lesson?.title) return state;
    return { ...state, lesson: lesson ?? undefined };
  }), [update]);
  const confirmRestored = useCallback((id: string, page: MentorPage, exists: boolean) => update(id, (state) => {
    if (!state.restored || state.page !== page) return state;
    return exists ? { ...state, restored: false } : { ...state, page: undefined, lesson: undefined, restored: false };
  }), [update]);
  return {
    stateFor: (id: string) => states[id] ?? DEFAULT_MENTOR_VIEW,
    /** What is being read now, outside of rendering. */
    readingFor: (id: string) => latest.current[id]?.page,
    /** The whole view now, outside of rendering: the page and the lesson in it. */
    viewFor: (id: string) => latest.current[id] ?? DEFAULT_MENTOR_VIEW,
    show, close, setLesson, confirmRestored,
    back: useCallback((id: string) => go(id, -1), [go]),
    forward: useCallback((id: string) => go(id, 1), [go]),
    /** How many pages there are to go back and forward to. */
    historyFor: (id: string) => ({ back: histories.current.get(id)?.back.length ?? 0, forward: histories.current.get(id)?.forward.length ?? 0 }),
    /** Shows one kind of thing in the library, a course in its Courses segment, or a filter. */
    openLibrary: useCallback((id: string, change: { segment?: LibrarySegment; course?: string; filter?: string; show?: boolean }) => update(id, (state) => {
      const segment = change.segment ?? state.segment;
      const next: MentorViewState = { ...state, ...(change.segment ? { segment: change.segment } : {}), ...(change.course ? { course: change.course } : {}), ...(change.show ? { library: true } : {}) };
      if (change.filter !== undefined) {
        if (change.filter && segment) next.filter = { segment, text: change.filter };
        else delete next.filter;
      }
      return next.segment === state.segment && next.course === state.course && next.library === state.library && next.filter === state.filter ? state : next;
    }), [update]),
    toggleLibrary: useCallback((id: string) => update(id, (state) => ({ ...state, library: !state.library })), [update]),
    toggleChat: useCallback((id: string) => update(id, (state) => ({ ...state, chat: !state.chat })), [update]),
    resizeLibrary: useCallback((id: string, value: number) => update(id, (state) => ({ ...state, libraryWidth: value })), [update]),
    resizeChat: useCallback((id: string, value: number) => update(id, (state) => ({ ...state, chatWidth: value })), [update]),
  };
}

export type MentorView = ReturnType<typeof useMentorView>;
