import type { Block, Session } from "../../sessions/model/session";
import { toolCallLabel } from "../../sessions/model/transcriptActivity";

export type PendingApprovalNotice = {
  sessionId: string;
  requestId: number;
  label: string;
  kind: "approval" | "question";
  block?: Block;
};

/** Latest undecided approval or clarifying question in a session, if any. */
export function pendingApprovalForSession(
  session: Session,
): PendingApprovalNotice | null {
  if (session.pendingQuestion) {
    return {
      sessionId: session.id,
      requestId: session.pendingQuestion.requestId,
      label:
        session.pendingQuestion.title ||
        session.pendingQuestion.questions[0]?.prompt ||
        "Question",
      kind: "question",
    };
  }
  for (let i = session.blocks.length - 1; i >= 0; i--) {
    const block = session.blocks[i];
    if (!block.approval || block.approval.decided) continue;
    return {
      sessionId: session.id,
      requestId: block.approval.requestId,
      label: toolCallLabel(block, session.cwd),
      kind: "approval",
      block,
    };
  }
  return null;
}

/** Approvals and questions in sessions that are not on screen. */
export function hiddenApprovalNotices(
  sessions: Session[],
  shownSessionIds: ReadonlySet<string>,
): Array<PendingApprovalNotice & { session: Session }> {
  const notices: Array<PendingApprovalNotice & { session: Session }> = [];
  for (const session of sessions) {
    const pending = pendingApprovalForSession(session);
    if (!pending || shownSessionIds.has(session.id)) continue;
    notices.push({ ...pending, session });
  }
  return notices;
}
