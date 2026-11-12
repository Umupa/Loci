import { useEffect, useRef, useState } from "react";
import { X } from "../../../shared/ui/icons";
import { openLearningDiscussion } from "../../learning/model/navigation";
import type { MentorPage } from "../model/mentorPage";
import { returningTo, returnSummary, touchMentor, type ReturnSummary } from "../model/mentorReturn";

/** How often time with a mentor on screen counts as being with it. */
const PRESENT_MS = 60_000;

/**
 * Coming back to a mentor after a while: where things were left, in one card
 * at the top of the reader. The last lesson, the last question and the next
 * lesson come from this device; no model is asked. One click goes on. The
 * card goes once anything is opened.
 */
export function useReturn(agentId: string, left: { courseId: string; lessonId?: string } | undefined, pageKey: string) {
  const [summary, setSummary] = useState<{ agentId: string; value: ReturnSummary; page: string }>();
  const leftRef = useRef(left);
  leftRef.current = left;
  const pageRef = useRef(pageKey);
  pageRef.current = pageKey;
  useEffect(() => {
    let live = true;
    const check = () => {
      if (document.hidden) return;
      if (returningTo(agentId)) {
        const page = pageRef.current;
        void returnSummary(agentId, leftRef.current).then((value) => {
          if (live && (value.last || value.question || value.next)) setSummary({ agentId, value, page });
        });
      }
      touchMentor(agentId);
    };
    check();
    const timer = window.setInterval(() => { if (!document.hidden && document.hasFocus()) touchMentor(agentId); }, PRESENT_MS);
    const visible = () => { if (!document.hidden) check(); };
    window.addEventListener("focus", check);
    document.addEventListener("visibilitychange", visible);
    return () => { live = false; window.clearInterval(timer); window.removeEventListener("focus", check); document.removeEventListener("visibilitychange", visible); };
  }, [agentId]);
  // Opening anything is going on: the card has done its work.
  const shown = summary?.agentId === agentId && summary.page === pageKey ? summary.value : undefined;
  return { summary: shown, dismiss: () => setSummary(undefined) };
}

export function ReturnCard({ agentId, summary, onOpen, onDismiss }: { agentId: string; summary: ReturnSummary; onOpen: (page: MentorPage) => void; onDismiss: () => void }) {
  const { last, question, go } = summary;
  const open = () => {
    if (!go) return;
    onDismiss();
    onOpen({ kind: "course", course: { courseId: go.courseId, agentId, title: go.courseTitle, itemId: go.lessonId, openRequest: Date.now() } });
  };
  return <section className="mentor-return" aria-label="Where you left off" data-return-card>
    <div className="mentor-return-body">
      {last ? <p className="mentor-return-last"><span>{last.courseTitle}</span><span aria-hidden> / </span><span>{last.title}</span></p> : null}
      {question ? <button type="button" className="mentor-return-question" title={question.text}
        onClick={() => openLearningDiscussion({ sessionId: question.sessionId, blockId: question.messageId })}>{question.text}</button> : null}
      {go ? <button type="button" className="mentor-return-go" onClick={open}>{go.title}</button> : null}
    </div>
    <button type="button" className="mentor-return-close" aria-label="Dismiss" title="Dismiss" onClick={onDismiss}><X className="size-3.5" /></button>
  </section>;
}
