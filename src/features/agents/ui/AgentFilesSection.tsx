import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { prettyCwd, projectName } from "../../../shared/lib/paths";
import { FileTree, type OpenFileFn } from "../../files/ui/FileTree";
import { agentLook, agentsSnapshot, findAgent, subscribeAgents } from "../model/agent";
import { ensureAgentWorkdir } from "../model/agentWorkdir";

type Props = {
  agentId: string;
  /** Opens a file in the reader, replacing what is there. */
  onOpenFile: OpenFileFn;
  onFileMoved?: (from: string, to: string) => void;
  onFileDeleted?: (path: string) => void;
  /** Filters the trees by name or path; they then have no search field of their own. */
  filter?: string;
  /** Clears that filter, as choosing a folder from its matches does. */
  onClearQuery?: () => void;
};

type Workdir = { path?: string; error?: string };

/**
 * A mentor's files: its workdir as a file tree, then any other folders it
 * was given, each folded until opened. It fills the width it is given and
 * brings no layout of its own, so it can sit in any column.
 */
export function AgentFilesSection({ agentId, onOpenFile, onFileMoved, onFileDeleted, filter, onClearQuery }: Props) {
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
  const empty = `No files yet — ask ${agentLook(agent).name} to write one.`;
  return (
    <section className="flex min-h-0 min-w-0 flex-col" aria-label="Files">
      {workdir.path ? (
        <FileTree key={workdir.path} cwd={workdir.path} rootLabel={projectName(workdir.path)} query={filter} onClearQuery={onClearQuery}
          paneActions={false} empty={empty}
          header={<p className="truncate text-[11px] text-content/45" title={workdir.path}>{prettyCwd(workdir.path)}</p>}
          onOpenFile={onOpenFile} onFileMoved={onFileMoved} onFileDeleted={onFileDeleted} />
      ) : workdir.error ? (
        <p className="px-3 py-2 text-[12px] text-content/50" role="alert">
          Could not open the working folder: {workdir.error}
        </p>
      ) : (
        <p className="px-3 py-2 text-[12px] text-content/40">Opening the working folder…</p>
      )}
    </section>
  );
}
