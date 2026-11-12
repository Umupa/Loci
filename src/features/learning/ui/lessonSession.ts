import { createContext, useContext } from "react";
import type { Block } from "../../sessions/model/session";

/**
 * The conversation of the mentor whose reader this is, for a lesson's margin
 * to show answers as they are written. Absent outside a mentor's workspace.
 */
export type LessonSession = { agentId: string; sessionId?: string; blocks: readonly Block[]; busy: boolean };
export const LessonSessionContext = createContext<LessonSession | null>(null);
export const useLessonSession = () => useContext(LessonSessionContext);
