import { requestOpenAppResource } from "../../../shared/lib/appResourceLinks";
import type { DiscussionRef } from "./types";

export const OPEN_LEARNING_DISCUSSION_EVENT = "loci:open-learning-discussion";
export function openLearningSource(id: string) {
  requestOpenAppResource({ kind: "source", id });
}
export function sourceResourceUrl(id: string) { return `loci://source/${encodeURIComponent(id)}`; }
export function openLearningDiscussion(discussion: DiscussionRef) {
  window.dispatchEvent(new CustomEvent(OPEN_LEARNING_DISCUSSION_EVENT, { detail: discussion }));
}
