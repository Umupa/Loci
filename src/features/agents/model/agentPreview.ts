import type { Session } from "../../sessions/model/session";

/** The last thing said in an agent's chat, as the rail shows it under its name. */
export type AgentPreview = {
  text: string;
  /** When it was said, when the chat knows. */
  at?: number;
};

const PREVIEW_KEY = "loci:agent-previews";
const PREVIEWS_CHANGED = "loci:agent-previews-changed";
const PREVIEW_CHARS = 120;

function oneLine(text: string): string {
  const flat = text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/^\s*(?:#{1,6}|>|[-*])\s+/gm, "")
    .replace(/[`*_]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return flat.length <= PREVIEW_CHARS
    ? flat
    : `${flat.slice(0, PREVIEW_CHARS - 1).trimEnd()}…`;
}

/**
 * The latest words in the chat: the agent's last reply or habit post, or the
 * user's message while no reply has come. App notifications and tool steps
 * say nothing a person would read here.
 */
export function agentPreview(
  session: Pick<Session, "blocks">,
): AgentPreview | undefined {
  const { blocks } = session;
  for (let i = blocks.length - 1; i >= 0; i--) {
    const block = blocks[i];
    const spoken =
      (block.role === "assistant" && !block.tool && !block.streaming) ||
      (block.role === "user" && !block.draft && !block.agentSessionCompletion);
    if (!spoken) continue;
    const text = oneLine(block.text);
    if (!text) continue;
    let at = block.agentHabit?.at ?? block.startedAt;
    // A reply carries no time of its own; its turn's message does.
    for (let j = i; at == null && j >= 0; j--) {
      if (blocks[j].role === "user") at = blocks[j].startedAt;
    }
    return { text, ...(at != null ? { at } : {}) };
  }
  return undefined;
}

function readPreviews(): Record<string, AgentPreview> {
  try {
    const parsed = JSON.parse(localStorage.getItem(PREVIEW_KEY) ?? "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, AgentPreview>)
      : {};
  } catch {
    return {};
  }
}

/** What each agent last said, by agent id; kept so the rail can show it before a chat is opened. */
export function loadAgentPreviews(): Record<string, AgentPreview> {
  return readPreviews();
}

/** Remembers an agent's latest words; `undefined` forgets them. Returns whether anything changed. */
export function saveAgentPreview(
  agentId: string,
  preview: AgentPreview | undefined,
): boolean {
  const previews = readPreviews();
  const current = previews[agentId];
  if (current?.text === preview?.text && current?.at === preview?.at)
    return false;
  if (preview) previews[agentId] = preview;
  else delete previews[agentId];
  try {
    localStorage.setItem(PREVIEW_KEY, JSON.stringify(previews));
  } catch {
    return false;
  }
  window.dispatchEvent(new CustomEvent(PREVIEWS_CHANGED));
  return true;
}

export function subscribeAgentPreviews(onChange: () => void): () => void {
  window.addEventListener(PREVIEWS_CHANGED, onChange);
  return () => window.removeEventListener(PREVIEWS_CHANGED, onChange);
}

export function agentPreviewsSnapshot(): string {
  try {
    return localStorage.getItem(PREVIEW_KEY) ?? "";
  } catch {
    return "";
  }
}

/** When it was said, as a contact list shows it: the time today, then the day. */
export function previewTimeLabel(at: number, now = Date.now()): string {
  const days = Math.round(
    (new Date(now).setHours(0, 0, 0, 0) - new Date(at).setHours(0, 0, 0, 0)) /
      86_400_000,
  );
  if (days <= 0)
    return new Date(at).toLocaleTimeString("en", {
      hour: "numeric",
      minute: "2-digit",
    });
  if (days === 1) return "Yesterday";
  return new Date(at).toLocaleDateString("en", {
    month: "short",
    day: "numeric",
  });
}
