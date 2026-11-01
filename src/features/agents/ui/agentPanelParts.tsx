import { useEffect, useRef, useState } from "react";
import { projectKey, projectName } from "../../../shared/lib/paths";
import { Folder, FolderOpen, Plus, X } from "../../../shared/ui/icons";
import { Popover } from "../../../shared/ui/Popover";
import type { RecentProject } from "../../projects/model/recents";
import { AGENT_COLORS } from "../model/agent";
import { AGENT_AVATARS, agentAvatar, defaultAgentName, type AgentAvatarStyle } from "../model/agentAvatars";
import { AgentAvatar } from "./AgentAvatar";

/** The faces an agent can wear, in its color; the chosen one is ringed. */
export function FacePicker({ current, color, onPick }: { current: string; color: string; onPick: (avatar: string) => void }) {
  const selectedStyle = agentAvatar(current).style;
  const [style, setStyle] = useState<AgentAvatarStyle>(selectedStyle);
  useEffect(() => setStyle(selectedStyle), [current, selectedStyle]);
  return (
    <div className="flex w-full flex-col items-center gap-2">
      <div role="group" aria-label="Avatar style" className="flex items-center gap-0.5 rounded-lg bg-content/5 p-0.5">
        {(["bottts", "bottts-neutral"] as const).map((value) => (
          <button key={value} type="button" aria-pressed={style === value} onClick={() => setStyle(value)}
            className={`h-6.5 rounded-md px-2.5 text-[11px] transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-content/60 ${style === value ? "bg-content/12 text-content" : "text-content/50 hover:text-content"}`}>
            {value === "bottts" ? "Bottts" : "Bottts Neutral"}
          </button>
        ))}
      </div>
      <div role="radiogroup" aria-label="Face" className="grid w-full max-w-[244px] grid-cols-[repeat(auto-fit,2.75rem)] justify-center gap-1.5">
        {AGENT_AVATARS.filter((avatar) => avatar.style === style).map((avatar) => (
          <button key={avatar.name} type="button" role="radio" aria-checked={avatar.name === current}
            title={defaultAgentName(avatar.name)} aria-label={defaultAgentName(avatar.name)} onClick={() => onPick(avatar.name)}
            className={`agent-face-option grid size-11 place-items-center rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-content/60 ${avatar.name === current ? "bg-content/12 ring-1 ring-content/20" : "hover:bg-content/8"}`}>
            <AgentAvatar name={avatar.name} color={color} className="size-9" />
          </button>
        ))}
      </div>
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

/** A folder by its name. */
function projectLook(path: string) {
  return { name: projectName(path) };
}

function ProjectIcon(_: { path: string }) {
  return <Folder className="size-3.5 shrink-0 text-content/50" strokeWidth={1.75} />;
}

/**
 * The other folders an agent works in, each removable, and a menu to add one
 * of the folders the app already knows or any folder.
 */
export function ProjectsField({ projects, recents, onAdd, onRemove, onPickFolders }: {
  projects: readonly string[];
  recents: readonly RecentProject[];
  onAdd: (path: string) => void;
  onRemove: (path: string) => void;
  onPickFolders: () => Promise<string[]>;
}) {
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  const taken = new Set(projects.map((path) => projectKey(path)));
  const candidates = recents.filter((recent) => !taken.has(projectKey(recent.path)));
  const pick = () => {
    setOpen(false);
    void onPickFolders().then((paths) => { for (const path of paths) onAdd(path); });
  };
  return (
    <div className="flex min-w-0 flex-col gap-0.5">
      {projects.map((path) => (
        <div key={projectKey(path)} title={path} className="group flex h-7 min-w-0 items-center gap-2 rounded-md px-1.5 hover:bg-content/6">
          <ProjectIcon path={path} />
          <span className="min-w-0 flex-1 truncate text-[13px]">{projectLook(path).name}</span>
          <button type="button" title="Remove folder" aria-label={`Remove ${projectLook(path).name}`} onClick={() => onRemove(path)}
            className="grid size-5 shrink-0 place-items-center rounded text-content/40 opacity-0 hover:text-content focus-visible:opacity-100 group-hover:opacity-100">
            <X className="size-3" strokeWidth={1.75} />
          </button>
        </div>
      ))}
      <button ref={anchor} type="button" aria-haspopup="menu" aria-expanded={open} onClick={() => (candidates.length ? setOpen((value) => !value) : pick())}
        className="flex h-7 w-fit items-center gap-2 rounded-md px-1.5 text-[13px] text-content/50 hover:bg-content/6 hover:text-content">
        <Plus className="size-3.5" strokeWidth={1.75} />
        Add folder
      </button>
      {open ? (
        <Popover anchor={anchor} side="bottom" align="start" width={240} onDismiss={() => setOpen(false)} role="menu" aria-label="Add folder" className="p-1.5">
          <div className="max-h-56 overflow-y-auto">
            {candidates.map((recent) => (
              <button key={recent.path} type="button" role="menuitem" title={recent.path} onClick={() => { setOpen(false); onAdd(recent.path); }}
                className="flex w-full min-w-0 items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[13px] text-content/85 hover:bg-content/8">
                <ProjectIcon path={recent.path} />
                <span className="min-w-0 flex-1 truncate">{projectLook(recent.path).name}</span>
              </button>
            ))}
          </div>
          <div role="separator" className="my-1 h-px bg-content/10" />
          <button type="button" role="menuitem" onClick={pick}
            className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[13px] text-content/85 hover:bg-content/8">
            <FolderOpen className="size-3.5 shrink-0" strokeWidth={1.75} />
            Choose folder…
          </button>
        </Popover>
      ) : null}
    </div>
  );
}
