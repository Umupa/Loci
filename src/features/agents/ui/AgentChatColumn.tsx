import { useCallback, useRef, type ReactNode } from "react";
import { useDragResize } from "../../../shared/hooks/useDragResize";
import type { Agent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";

const CHAT_MIN = 320;
/** The main area beside it keeps at least this much. */
const MAIN_MIN = 360;

type Props = {
  width: number;
  onResize: (width: number) => void;
  /** With nothing beside it, or holding more than one pane, it takes the space. */
  alone: boolean;
  hidden: boolean;
  children: ReactNode;
};

/**
 * An agent's conversation, always on the right of what is being read. Showing
 * or hiding it never moves the content beside it.
 */
export function AgentChatColumn({ width, onResize, alone, hidden, children }: Props) {
  const column = useRef<HTMLDivElement | null>(null);
  const resize = useDragResize({
    min: CHAT_MIN,
    max: () => Math.max(CHAT_MIN, (column.current?.parentElement?.clientWidth ?? window.innerWidth) - MAIN_MIN),
    direction: "left", defaultWidth: 420, initial: width, onCommit: onResize,
  });
  const setRef = useCallback((element: HTMLDivElement | null) => {
    column.current = element;
    resize.setPaneRef(element);
  }, [resize.setPaneRef]);
  return <div ref={setRef} className="agent-workspace-panes" data-alone={alone || undefined} hidden={hidden}>
    {!alone ? <div role="separator" aria-label="Resize conversation" aria-orientation="vertical" tabIndex={0} className="agent-chat-resize"
      onPointerDown={resize.onPointerDown} onDoubleClick={resize.onDoubleClick}
      onKeyDown={(event) => {
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
        event.preventDefault();
        resize.setWidth(resize.width + (event.key === "ArrowLeft" ? 20 : -20));
      }} /> : null}
    {children}
  </div>;
}

/** Shows or hides the conversation column, from the header of whatever is being read. */
export function AgentChatToggle({ agent, open, onToggle }: { agent: Pick<Agent, "avatar" | "color" | "name">; open: boolean; onToggle: () => void }) {
  const label = open ? "Hide conversation" : `Chat with ${agent.name || "agent"}`;
  return <button type="button" data-tauri-drag-region="false" data-no-drag aria-pressed={open} aria-label={label} title={label} onClick={onToggle}
    className={`agent-chat-toggle ${open ? "bg-content/8 text-content" : "text-content/60"}`}>
    <AgentAvatar name={agent.avatar} color={agent.color} className="size-3.5 shrink-0" />
    {open ? null : <span>Chat</span>}
  </button>;
}
