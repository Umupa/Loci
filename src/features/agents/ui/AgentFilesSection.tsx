import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { ChevronDown, ChevronRight } from "../../../shared/ui/icons";
import { prettyCwd, projectName } from "../../../shared/lib/paths";
import { FileTree, type OpenFileFn } from "../../files/ui/FileTree";
import { agentsSnapshot, findAgent, subscribeAgents } from "../model/agent";
import { ensureAgentWorkdir } from "../model/agentWorkdir";

type Props = {
  agentId: string;
  /** Opens a file in the reader, replacing what is there. */
  onOpenFile: OpenFileFn;
  onFileMoved?: (from: string, to: string) => void;
  onFileDeleted?: (path: string) => void;
  /** Filters the working folder's tree by name or path; the tree then has no search field of its own. */
  filter?: string;
};

type Workdir = { path?: string; error?: string };

/**
 * A mentor's files: its workdir as a file tree, then any other folders it
 * was given, each folded until opened. It fills the width it is given and
 * brings no layout of its own, so it can sit in any column.
 */
export function AgentFilesSection({ agentId, onOpenFile, onFileMoved, onFileDeleted, filter }: Props) {
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  const agent = useMemo(() => findAgent(agentId), [agentId, snapshot]);
  const [workdir, setWorkdir] = useState<Workdir>({});
  const saved = agent?.workdir;

  useEffect(() => {
    let live = true;
    setWorkdir({});
    ensureAgentWorkdir(agentId).then(
      (path) => live && setWorkdir({ path }),
      (error: unknown) => live && setWorkdir({ error: String(error instanceof Error ? error.message : error) }),
    );
    return () => { live = false; };
  }, [agentId, saved]);

  if (!agent) return null;
  return (
    <section className="flex min-h-0 min-w-0 flex-col" aria-label="Files">
      {workdir.path ? (
        <FileTree key={workdir.path} cwd={workdir.path} rootLabel={projectName(workdir.path)} query={filter}
          header={<p className="truncate text-[11px] text-content/45" title={workdir.path}>{prettyCwd(workdir.path)}</p>}
          onOpenFile={onOpenFile} onFileMoved={onFileMoved} onFileDeleted={onFileDeleted} />
      ) : workdir.error ? (
        <p className="px-3 py-2 text-[12px] text-content/50" role="alert">
          Could not open the working folder: {workdir.error}
        </p>
      ) : (
        <p className="px-3 py-2 text-[12px] text-content/40">Opening the working folder…</p>
      )}
      {agent.projects.length ? (
        <div className="mt-2 flex flex-col">
          <p className="px-3 pb-1 text-[11px] font-medium text-content/45">Other folders</p>
          {agent.projects.map((path) => (
            <OtherFolder key={path} path={path} onOpenFile={onOpenFile}
              onFileMoved={onFileMoved} onFileDeleted={onFileDeleted} />
          ))}
        </div>
      ) : null}
    </section>
  );
}

function OtherFolder({ path, ...tree }: { path: string } & Omit<Props, "agentId" | "filter">) {
  const [open, setOpen] = useState(false);
  const Chevron = open ? ChevronDown : ChevronRight;
  return (
    <div className="flex min-w-0 flex-col">
      <button type="button" aria-expanded={open} title={path} onClick={() => setOpen(!open)}
        className="flex min-w-0 items-center gap-1 px-3 py-1 text-left text-[12px] text-content/70 hover:text-content">
        <Chevron className="size-3 shrink-0" />
        <span className="truncate">{projectName(path)}</span>
      </button>
      {open ? <FileTree cwd={path} rootLabel={projectName(path)} {...tree} /> : null}
    </div>
  );
}
