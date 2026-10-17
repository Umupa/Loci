import { useCallback, useRef, useState } from "react";
import type { OpenCourseDetail } from "../../features/learning/model/course";
import type { AgentDocument } from "../../features/sessions/model/cards";

export type AgentOverviewTab = "courses" | "documents" | "notes" | "habits" | "canvases";
export type AgentOverviewPage =
  | { kind: "course"; course: OpenCourseDetail }
  | { kind: "document"; document: AgentDocument }
  | { kind: "note"; id: string }
  | { kind: "habit"; id: string }
  | { kind: "new-habit" };
export type AgentOverviewState = {
  /** The main area: the overview and whatever it has open. */
  open: boolean;
  tab: AgentOverviewTab;
  /** Width of the conversation column beside it. */
  width: number;
  /** The conversation column; it never moves, it is only shown or hidden. */
  chat: boolean;
  page?: AgentOverviewPage;
};
const KEY = "loci:agent-overviews.v1";
const TABS: AgentOverviewTab[] = ["courses", "documents", "notes", "habits", "canvases"];
const DEFAULT: AgentOverviewState = { open: true, tab: "courses", width: 420, chat: true };

function read(): Record<string, AgentOverviewState> {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) ?? "{}");
    if (!value || typeof value !== "object" || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).flatMap(([id, raw]) => {
      if (!raw || typeof raw !== "object" || !/^[A-Za-z0-9_-]+$/.test(id)) return [];
      const item = raw as Partial<AgentOverviewState>;
      return [[id, {
        open: typeof item.open === "boolean" ? item.open : DEFAULT.open,
        tab: TABS.includes(item.tab!) ? item.tab! : DEFAULT.tab,
        width: typeof item.width === "number" && Number.isFinite(item.width) ? Math.max(320, item.width) : DEFAULT.width,
        chat: typeof item.chat === "boolean" ? item.chat : DEFAULT.chat,
      }]];
    }));
  } catch { return {}; }
}

/** Each agent keeps its own overview; only the small UI preferences are persisted. */
export function useAgentOverview() {
  const [states, setStates] = useState(read);
  const latest = useRef(states);
  const update = useCallback((id: string, edit: (state: AgentOverviewState) => AgentOverviewState) => {
    const next = { ...latest.current, [id]: edit(latest.current[id] ?? DEFAULT) };
    latest.current = next;
    setStates(next);
    try {
      localStorage.setItem(KEY, JSON.stringify(Object.fromEntries(Object.entries(next).map(([key, { open, tab, width, chat }]) => [key, { open, tab, width, chat }]))));
    } catch { /* The current window still retains its view. */ }
  }, []);
  const show = useCallback((id: string, page: AgentOverviewPage) => {
    const tab: AgentOverviewTab = page.kind === "course" ? "courses" : page.kind === "document" ? "documents" : page.kind === "note" ? "notes" : "habits";
    update(id, (state) => ({ ...state, tab, page, open: true }));
  }, [update]);
  return {
    stateFor: (id: string) => states[id] ?? DEFAULT,
    show,
    // One of the two is always showing: hiding one brings the other back.
    toggle: (id: string) => update(id, (state) => ({ ...state, open: !state.open, chat: state.open ? true : state.chat })),
    close: (id: string) => update(id, (state) => ({ ...state, open: false, chat: true })),
    toggleChat: (id: string) => update(id, (state) => ({ ...state, chat: !state.chat, open: state.chat ? true : state.open })),
    selectTab: (id: string, tab: AgentOverviewTab) => update(id, (state) => ({ ...state, tab, page: undefined })),
    back: (id: string) => update(id, (state) => ({ ...state, page: undefined })),
    resize: (id: string, width: number) => update(id, (state) => ({ ...state, width })),
  };
}
