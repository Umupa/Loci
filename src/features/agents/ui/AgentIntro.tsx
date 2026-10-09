import { agentLook, agentProjectsPhrase, type Agent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";

/** Meets the user in an agent's empty conversation: who it is and what it can reach. */
export function AgentIntro({ agent }: { agent: Agent }) {
  const look = agentLook(agent);
  const projects = agentProjectsPhrase(look.projects);
  return (
    <div className="flex items-center gap-3">
      <AgentAvatar name={look.avatar} color={look.color} className="size-7 shrink-0" />
      <div className="min-w-0">
        <h1 className="truncate text-lg text-content">{look.name}</h1>
        <p className="truncate text-[13px] text-content/50">
          {projects
            ? `Works on ${projects}. It remembers what it learns and can start sessions for you.`
            : "It has no projects yet. Add some in Details, or just talk."}
        </p>
      </div>
    </div>
  );
}
