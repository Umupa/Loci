export const ADD_TO_CHAT_EVENT = "loci:add-to-chat";

/** A quoted selection, a plain block, or the start of a sentence for the user to finish. */
export type AddToChatMode = "quote" | "plain" | "prompt";

export type AddToChatRequest = LearningMessageContext & {
  text: string;
  mode: AddToChatMode;
  targetSessionId?: string;
};

export type QuoteRequest = LearningMessageContext & {
  id: number;
  text: string;
  mode?: AddToChatMode;
};

export function requestAddToChat(text: string, mode: AddToChatMode = "quote", context?: LearningMessageContext & { targetSessionId?: string }) {
  if (typeof window === "undefined") return;
  const normalized = text.replace(/\r\n?/g, "\n");
  // A prompt keeps its trailing space, so typing carries on after it.
  const value = mode === "prompt" ? normalized.trimStart() : normalized.trim();
  if (!value && !context?.sources?.length) return;
  window.dispatchEvent(
    new CustomEvent<AddToChatRequest>(ADD_TO_CHAT_EVENT, {
      detail: { text: value, mode, ...context },
    }),
  );
}

/** Initial composer text for an add-to-chat request that opens a new session. */
export function composerSeedForAddToChat(
  text: string,
  mode: AddToChatMode = "quote",
): string {
  return mode === "plain"
    ? appendComposerInsert("", text)
    : mode === "prompt"
      ? appendComposerPrompt("", text)
      : appendSelectionQuote("", text);
}

export type QuoteConsumption = {
  draft: string;
  consumedId: number | null;
  changed: boolean;
};

export function isMarkdownBlockquotePosition(
  text: string,
  position: number,
): boolean {
  const index = Math.max(0, Math.min(position, text.length));
  const lineStart = text.lastIndexOf("\n", Math.max(0, index - 1)) + 1;
  return /^ {0,3}>/.test(text.slice(lineStart, index));
}

export function appendSelectionQuote(draft: string, text: string): string {
  const selected = text.replace(/\r\n?/g, "\n").trim();
  if (!selected) return draft;

  const quote = selected
    .split("\n")
    .map((line) => (line ? `> ${line}` : ">"))
    .join("\n");
  return joinComposerInsert(draft, quote);
}

export function appendComposerInsert(draft: string, text: string): string {
  const selected = text.replace(/\r\n?/g, "\n").trim();
  if (!selected) return draft;
  return joinComposerInsert(draft, selected);
}

/** The start of a sentence, on its own paragraph, with the cursor meant to follow it. */
export function appendComposerPrompt(draft: string, text: string): string {
  const prompt = text.replace(/\r\n?/g, "\n").trimStart();
  if (!prompt.trim()) return draft;
  const separator = draft.length === 0 || draft.endsWith("\n\n") ? "" : draft.endsWith("\n") ? "\n" : "\n\n";
  return `${draft}${separator}${prompt}`;
}

export function consumeQuoteRequest(
  draft: string,
  consumedId: number | null,
  request: QuoteRequest | undefined,
): QuoteConsumption {
  if (!request || request.id === consumedId) {
    return { draft, consumedId, changed: false };
  }

  const next =
    request.mode === "plain"
      ? appendComposerInsert(draft, request.text)
      : request.mode === "prompt"
        ? appendComposerPrompt(draft, request.text)
        : appendSelectionQuote(draft, request.text);
  return {
    draft: next,
    consumedId: request.id,
    changed: next !== draft,
  };
}

export function acknowledgeQuoteRequest(
  current: QuoteRequest | undefined,
  handledId: number,
): QuoteRequest | undefined {
  return current?.id === handledId ? undefined : current;
}

function joinComposerInsert(draft: string, block: string): string {
  const separator =
    draft.length === 0
      ? ""
      : draft.endsWith("\n\n")
        ? ""
        : draft.endsWith("\n")
          ? "\n"
          : "\n\n";
  return `${draft}${separator}${block}\n\n`;
}
import type { LearningMessageContext } from "../../learning/model/types";
