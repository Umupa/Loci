import { AGENT_COLORS } from "../model/agent";
import { AGENT_AVATARS, agentAvatar, defaultAgentName } from "../model/agentAvatars";
import { AgentAvatar } from "./AgentAvatar";

/** The faces an agent can wear, each on a card in its color; the chosen one is ringed. */
export function FacePicker({ current, color, onPick }: { current: string; color: string; onPick: (avatar: string) => void }) {
  // A face saved under an older name still shows as chosen.
  const chosen = agentAvatar(current).name;
  return (
    <div role="radiogroup" aria-label="Face" className="grid w-full max-w-[280px] grid-cols-[repeat(auto-fit,2.75rem)] justify-center gap-1.5">
      {AGENT_AVATARS.map((avatar) => (
        <button key={avatar.name} type="button" role="radio" aria-checked={avatar.name === chosen}
          title={defaultAgentName(avatar.name)} aria-label={defaultAgentName(avatar.name)} onClick={() => onPick(avatar.name)}
          className={`agent-face-option grid size-11 place-items-center rounded-xl focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-content/60 ${avatar.name === chosen ? "bg-content/12 ring-1 ring-content/25" : "hover:bg-content/8"}`}>
          <AgentAvatar name={avatar.name} color={color} className="size-9" />
        </button>
      ))}
    </div>
  );
}

export function ColorPicker({ current, onPick }: { current: string; onPick: (color: string) => void }) {
  return (
    <div role="radiogroup" aria-label="Color" className="flex flex-wrap justify-center gap-2.5">
      {AGENT_COLORS.map((color) => (
        <button key={color} type="button" role="radio" aria-checked={color === current} aria-label={color} onClick={() => onPick(color)}
          className="agent-color-option size-5 rounded-full focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-content/60"
          style={{ backgroundColor: color }} />
      ))}
    </div>
  );
}
