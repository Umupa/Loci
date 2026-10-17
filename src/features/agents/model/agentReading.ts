/**
 * What the user has open beside an agent's conversation. The overview sets
 * it; each turn the agent is told, so "this lesson" needs no explaining.
 */
export type AgentReading =
  | { kind: "course"; courseId: string; title: string; lessonId?: string; lessonTitle?: string }
  | { kind: "document"; id: string; title: string }
  | { kind: "note"; id: string };

const reading = new Map<string, AgentReading>();

export function setAgentReading(agentId: string, next: AgentReading | undefined): void {
  if (next) reading.set(agentId, next);
  else reading.delete(agentId);
}

export function agentReading(agentId: string): AgentReading | undefined {
  return reading.get(agentId);
}

/** The context block for a turn, or nothing when the agent's main area is empty. */
export function readingContext(agentId: string): string | undefined {
  const current = reading.get(agentId);
  return current ? `<reading_now>\n${JSON.stringify(current)}\n</reading_now>` : undefined;
}
