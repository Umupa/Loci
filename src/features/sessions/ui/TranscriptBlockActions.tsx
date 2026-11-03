import { useMemo, useState } from "react";
import { blockAt, blockLabel, type ReadingBlock } from "../../learning/model/blockAnchor";
import { BlockHandle, BlockToolbar } from "../../learning/ui/BlockToolbar";
import { SELECTABLE_AGENT_RESPONSE_ATTR } from "../model/transcriptSelection";

type Props = {
  scroller: HTMLElement | null;
  enabled?: boolean;
  /** Ask: the block, as written, goes into the reply being written. */
  onAddToChat?: (text: string, blockId?: string) => void;
  /** Highlight: the block is kept in the mentor's highlights. */
  onKeep?: (text: string) => void | Promise<unknown>;
  /** Save as note: the block becomes a note of its own. */
  onSaveNote?: (text: string) => void | Promise<void>;
};

/**
 * A whole block of a reply (a table, a diagram, a code block, a picture) has
 * the reader's handle and bar: Highlight · Save as note · Ask, each taking the
 * block's Markdown as it was written.
 */
export function TranscriptBlockActions({ scroller, enabled = true, onAddToChat, onKeep, onSaveNote }: Props) {
  const root = useMemo(() => ({ current: scroller }), [scroller]);
  const [open, setOpen] = useState<{ block: ReadingBlock; blockId?: string; at: DOMRect } | null>(null);
  const shown = open?.block;
  return <>
    <BlockHandle root={root} enabled={enabled && !!scroller} marked={() => false}
      onOpen={(element, at) => {
        const block = scroller ? blockAt(scroller, element) : null;
        if (!block) return;
        const blockId = element.closest(`[${SELECTABLE_AGENT_RESPONSE_ATTR}]`)?.getAttribute(SELECTABLE_AGENT_RESPONSE_ATTR) ?? undefined;
        setOpen({ block, blockId, at });
      }} />
    {shown && open ? <BlockToolbar key={shown.source} anchor={open.at} label={`${blockLabel(shown.kind)} actions`}
      onDismiss={() => setOpen(null)}
      onMark={onKeep ? async () => { await onKeep(shown.source); } : undefined}
      onSaveNote={onSaveNote ? () => onSaveNote(shown.source) : undefined}
      onAsk={onAddToChat ? () => onAddToChat(shown.source, open.blockId) : undefined} /> : null}
  </>;
}
