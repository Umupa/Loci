import { useEffect, useRef } from "react";
import { agentForSession } from "../../features/agents/model/agent";
import { upsertLearningWidget } from "../../features/learning/model/learningStore";
import { widgetsInText } from "../../features/learning/model/widgets";
import type { Session } from "../../features/sessions/model/session";

/** Register completed output, not card mounts: opening old history must never
 * overwrite a newer revision. The store compares the originating turn/order. */
export function useLearningWidgets(sessions: readonly Session[], onError: (error: unknown) => void) {
  const seen = useRef(new Map<string, string>());
  const latestError = useRef(onError);
  latestError.current = onError;
  useEffect(() => {
    for (const session of sessions) {
      if (session.ephemeral) continue;
      const agent = agentForSession(session.id);
      const owner = agent ? { kind: "agent" as const, id: agent.id } : { kind: "session" as const, id: session.id };
      let turnAt = 0;
      for (const [index, block] of session.blocks.entries()) {
        if (block.role === "user") turnAt = block.startedAt ?? turnAt;
        if (block.role !== "assistant" || block.tool || block.streaming) continue;
        const key = `${session.id}:${block.id}`;
        if (seen.current.get(key) === block.text) continue;
        seen.current.set(key, block.text);
        for (const spec of widgetsInText(block.text)) {
          void upsertLearningWidget(owner, spec, session.id, block.id, turnAt * 1000 + index)
            .catch((error) => latestError.current(error));
        }
      }
    }
  }, [sessions]);
}
