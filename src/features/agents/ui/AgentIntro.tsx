import { agentLook, agentProjectsPhrase, type Agent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";

/** The first message is enough to start; profile settings stay in Details. */
export function AgentIntro({ agent }: { agent: Agent }) {
  const look = agentLook(agent);
  const projects = agentProjectsPhrase(look.projects);
  const tutor = look.role === "tutor";
  return (
    <div className="flex items-start gap-3" data-agent-intro>
      <AgentAvatar name={look.avatar} color={look.color} className="mt-0.5 size-7 shrink-0" />
      <div className="min-w-0">
        <h1 className="text-lg text-content">
          {tutor ? "What would you like to learn?" : "What would you like help with?"}
        </h1>
        <p className="mt-1 text-[13px] leading-relaxed text-content/55">
          {tutor
            ? "A topic is enough. We'll start with a short exercise."
            : "A sentence is enough. I'll get started and set myself up as we go."}
        </p>
        {projects ? <p className="mt-2 text-xs text-content/40">Works on {projects}.</p> : null}
      </div>
    </div>
  );
}
