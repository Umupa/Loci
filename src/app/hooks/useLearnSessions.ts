import { useEffect, useRef } from "react";
import { getCanvas } from "../../features/canvas/canvas";
import { learnSessionFor } from "../../features/learn/learnSeed";
import { LEARN_START_EVENT, type LearnStart } from "../../features/learn/ui/LearnMapPanel";
import { listSessionsByProject } from "../../features/sessions/data/sessionStore";
import { isHarnessAvailable } from "../../integrations/harness/core/availability";
import type { useAppWorkspace } from "./useAppWorkspace";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = { workspace: ReturnType<typeof useAppWorkspace>; runtime: SessionRuntime; submission: SessionSubmission };

/** Opens a session beside a learning map when the learner picks a node to explore or revisit. */
export function useLearnSessions(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  useEffect(() => {
    const start = (event: Event) => {
      const detail = (event as CustomEvent<LearnStart>).detail;
      const { workspace, runtime, submission } = latest.current;
      void (async () => {
        const canvas = await getCanvas(detail.canvasId);
        if (!canvas?.cwd) throw new Error("This learning map does not belong to a project.");
        const cwd = canvas.cwd;
        // The project's last learning session decides the provider and model, also after a restart.
        const session = learnSessionFor(cwd, runtime.sessionsRef.current, await listSessionsByProject(cwd).catch(() => []), isHarnessAvailable);
        workspace.addSession(session, { besideSessionId: canvas.id, edge: "right" });
        const accepted = await submission.submit(session.id, `/learn ${detail.label}`, [], { learnFocus: { nodeId: detail.nodeId, intent: detail.intent } });
        if (!accepted) throw new Error("The learning session could not be started.");
      })().catch((error: unknown) => workspace.setError(error instanceof Error ? error.message : String(error)));
    };
    window.addEventListener(LEARN_START_EVENT, start);
    return () => window.removeEventListener(LEARN_START_EVENT, start);
  }, []);
}
