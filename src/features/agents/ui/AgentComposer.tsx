import { useLayoutEffect, useRef, useState } from "react";
import { isImeComposition } from "../../../shared/lib/keyboard";
import { ArrowUp, Plus, Square } from "../../../shared/ui/icons";
import { AttachmentChip } from "../../sessions/ui/AttachmentChip";
import type { Attachment } from "../../sessions/model/session";
import {
  attachmentsFromFiles,
  filesFromClipboard,
  mergeAttachments,
  pickAttachments,
  revokeAttachment,
} from "../../sessions/model/attachments";
import { getComposerDraft, setComposerDraft } from "../../sessions/model/draftCache";
import { resizeComposer } from "../../sessions/model/composerResize";

/** Tallest the field grows before it scrolls, in px. */
const MAX_HEIGHT = 160;

type Props = {
  sessionId: string;
  /** Who the message goes to, for the placeholder. */
  name: string;
  busy: boolean;
  focusToken?: number;
  /** Returns false when the message was not taken, so the draft stays. */
  onSubmit: (text: string, attachments: Attachment[]) => boolean | void;
  onStop: () => void;
};

/**
 * A messaging app's input for an agent: attach, type, send, whether or not it
 * is mid-reply; Escape stops a reply. The model and permissions live in the
 * details panel instead.
 */
export function AgentComposer({ sessionId, name, busy, focusToken, onSubmit, onStop }: Props) {
  const [text, setText] = useState(() => getComposerDraft(sessionId) ?? "");
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const attachmentsRef = useRef(attachments);
  const [reading, setReading] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const field = useRef<HTMLTextAreaElement>(null);
  // Reads still in flight when the composer goes away are thrown out.
  const generation = useRef(0);
  const ready = reading === 0 && (text.trim().length > 0 || attachments.length > 0);

  useLayoutEffect(() => {
    const el = field.current;
    if (!el) return;
    resizeComposer(el, MAX_HEIGHT);
    el.style.overflowY = el.scrollHeight > MAX_HEIGHT ? "auto" : "hidden";
  }, [text]);
  useLayoutEffect(() => { field.current?.focus(); }, [focusToken, sessionId]);
  useLayoutEffect(() => () => {
    generation.current += 1;
    for (const file of attachmentsRef.current) revokeAttachment(file);
  }, []);

  const update = (next: string) => {
    setText(next);
    setComposerDraft(sessionId, next);
  };
  const keep = (next: Attachment[]) => {
    attachmentsRef.current = next;
    setAttachments(next);
  };
  const read = (source: () => Promise<Attachment[]>) => {
    const started = generation.current;
    setReading((count) => count + 1);
    setError(null);
    void Promise.resolve().then(source).then((incoming) => {
      if (started !== generation.current) { incoming.forEach(revokeAttachment); return; }
      if (incoming.length) keep(mergeAttachments(attachmentsRef.current, incoming));
    }, (reason: unknown) => {
      if (started === generation.current) setError(reason instanceof Error ? reason.message : String(reason));
    }).finally(() => {
      if (started === generation.current) setReading((count) => count - 1);
    });
  };
  const send = () => {
    if (!ready) return;
    if (onSubmit(text.trim(), attachmentsRef.current) === false) return;
    update("");
    keep([]);
    setError(null);
  };

  return (
    <form className="agent-composer mx-auto w-full max-w-4xl shrink-0 px-4 pb-3 pt-1 font-sans"
      onSubmit={(event) => { event.preventDefault(); send(); }}>
      {error ? <p role="alert" className="px-4 pb-1.5 text-xs text-red-400">{error}</p> : null}
      <div className="agent-composer-box flex flex-col gap-2 rounded-[1.6rem] border border-stroke bg-content/4 p-1.5 has-focus:border-content/25">
        {attachments.length > 0 ? (
          <div className="flex flex-wrap gap-1.5 px-2 pt-1.5">
            {attachments.map((file) => (
              <AttachmentChip key={file.id} attachment={file} onRemove={() => {
                revokeAttachment(file);
                keep(attachmentsRef.current.filter((item) => item.id !== file.id));
              }} />
            ))}
          </div>
        ) : null}
        <div className="flex items-end gap-2">
          <button type="button" title="Attach files" aria-label="Attach files" onClick={() => read(pickAttachments)}
            className="grid size-9 shrink-0 place-items-center rounded-full bg-content/8 text-content/60 hover:bg-content/14 hover:text-content">
            <Plus className="size-4" strokeWidth={1.75} />
          </button>
          <textarea ref={field} rows={1} value={text} aria-label={`Message ${name}`} placeholder={`Message ${name}`}
            onChange={(event) => update(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Escape" && busy && !isImeComposition(event.nativeEvent)) { event.preventDefault(); onStop(); return; }
              if (event.key !== "Enter" || event.shiftKey || isImeComposition(event.nativeEvent)) return;
              event.preventDefault();
              send();
            }}
            onPaste={(event) => {
              const files = filesFromClipboard(event.clipboardData);
              if (files.length === 0) return;
              event.preventDefault();
              read(() => attachmentsFromFiles(files));
            }}
            className="scrollbar-none block min-w-0 flex-1 resize-none self-center bg-transparent py-1.5 text-[14px] leading-5 text-content outline-none placeholder:text-content/40" />
          {busy && !ready ? (
            <button type="button" title="Stop (Esc)" aria-label="Stop" onClick={onStop}
              className="agent-composer-send grid size-9 shrink-0 place-items-center rounded-full">
              <Square className="size-3" strokeWidth={2.5} />
            </button>
          ) : (
            <button type="submit" aria-label="Send" title={reading ? "Reading attachments…" : "Send"} disabled={!ready}
              className="agent-composer-send grid size-9 shrink-0 place-items-center rounded-full transition-transform duration-150 active:scale-90 disabled:cursor-default">
              <ArrowUp className="size-4" strokeWidth={2} />
            </button>
          )}
        </div>
      </div>
    </form>
  );
}
