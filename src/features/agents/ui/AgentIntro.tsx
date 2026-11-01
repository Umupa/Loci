import { agentLook, type Agent } from "../model/agent";
import { AgentAvatar } from "./AgentAvatar";

/** The first message is enough to start; profile settings stay in the settings dialog. */
export function AgentIntro({ agent }: { agent: Agent }) {
  const look = agentLook(agent);
  return (
    <div className="agent-greeting" data-agent-intro>
      <AgentAvatar name={look.avatar} color={look.color} className="relative z-10 size-14 shrink-0" />
      <div className="agent-greeting-copy">
        <div className="agent-greeting-name">{look.name}</div>
        <h1 className="mt-4 text-[14px] font-medium text-content">
          What do you want to learn?
        </h1>
        <p className="mt-1 max-w-sm text-[13px] leading-relaxed text-content/45">
          Name a topic and what you already know. I'll find first-hand sources and set up a course with you.
        </p>
      </div>
    </div>
  );
}
