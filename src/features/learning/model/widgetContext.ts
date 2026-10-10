import { findAgent } from "../../agents/model/agent";
import { requestAddToChat } from "../../sessions/model/quoteDraft";
import { getLearningSource } from "./learningStore";
import { currentWidget } from "./widgetRuntime";
import { widgetRef } from "./widgets";
import type { StoredWidget, WidgetContext } from "./types";

export async function askAboutWidget(widget: StoredWidget, text: string, selection?: string) {
  // A control may setState and ask in the same click, before React redraws.
  widget = currentWidget(widgetRef(widget)) ?? widget;
  const targetSessionId = widget.owner.kind === "agent" ? findAgent(widget.owner.id)?.sessionId : widget.owner.id;
  if (!targetSessionId) throw new Error("Open the conversation this explanation belongs to first.");
  const sources = (await Promise.all(widget.sourceIds.map(getLearningSource))).filter((source) => source !== null);
  const widgetContext: WidgetContext = { owner: widget.owner, id: widget.id, title: widget.title, revision: widget.revision, state: widget.state, ...(selection ? { selection } : {}) };
  requestAddToChat(text, "plain", { targetSessionId, widgetContext, sources });
}
