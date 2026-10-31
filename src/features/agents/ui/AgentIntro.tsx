import { agentLook, type Agent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";

/** The first message is enough to start; profile settings stay in the settings dialog. */
export function AgentIntro({ agent }: { agent: Agent }) {
  const look = agentLook(agent);
  const tutor = look.role === "tutor";
  return (
    <div className="agent-greeting" data-agent-intro>
      <AgentAvatar name={look.avatar} color={look.color} className="relative z-10 size-14 shrink-0" />
      <div className="agent-greeting-copy">
        <div className="agent-greeting-name">{look.name}</div>
        <h1 className="mt-4 text-[14px] font-medium text-content">
          {tutor ? "What would you like to learn?" : "What would you like help with?"}
        </h1>
        <p className="mt-1 max-w-sm text-[13px] leading-relaxed text-content/45">
          {tutor
            ? "A topic is enough. We'll start with a short exercise."
            : "A sentence is enough. I'll get started and set myself up as we go."}
        </p>
      </div>
    </div>
  );
}
