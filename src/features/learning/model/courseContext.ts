import { createContext } from "react";

export type CourseHost = { agentId?: string; sourceSessionId: string };
export const CourseHostContext = createContext<CourseHost | null>(null);
