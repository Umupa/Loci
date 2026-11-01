import { useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { handleAgentApp } from "../../features/agent-app/model/agentApp";
import { listAgents } from "../../features/agents/model/agent";
import type { MentorPage } from "../../features/mentor/model/mentorPage";
import { refreshHarnessCatalogs } from "../../integrations/harness/core/registry";
import type { CommandContext } from "../commands/context";
import { CommandError } from "../commands/registry";
import { agentAppHost, type AgentAppDeps } from "./agentAppHost";
import type { useAgents } from "./useAgents";
import type { MentorView } from "./useMentorView";

/** A CLI call should not wait on a slow provider probe; the catalog lands later. */
const CATALOG_WAIT_MS = 5_000;

type Options = AgentAppDeps & {
  agents: () => ReturnType<typeof useAgents> | null;
  activeAgentId: () => string | null;
  /** Opens a mentor's workspace, as the rail does; false when that did not happen. */
  showMentor: (agentId: string) => Promise<boolean>;
  /** Reads a page in a mentor's reader and brings the mentor on screen. */
  showInMentor: (page: MentorPage, agentId: string) => Promise<void>;
  /** Waits for the reader's unsaved edits; false when they could not be saved. */
  leaveReader: (agentId: string) => Promise<boolean>;
  mentorView: () => MentorView;
};

/**
 * The command layer's view of the window, made of the same hooks the UI
 * calls. It is one stable object that reads the latest hooks on each call.
 */
export function useCommandContext(options: Options): CommandContext {
  const latest = useRef(options);
  latest.current = options;
  const context = useRef<CommandContext | null>(null);
  if (context.current) return context.current;
  const agents = () => {
    const current = latest.current.agents();
    if (!current) throw new CommandError("Loci is still starting; try again", "busy");
    return current;
  };
  let identifier: Promise<string> | undefined;
  context.current = {
    identifier: () => identifier ??= invoke<{ identifier: string }>("cli_access_status").then((status) => status.identifier),
    agents: () => listAgents(),
    activeAgentId: () => latest.current.activeAgentId(),
    createAgent: (template, look) => agents().create(template, { show: false, ...(look ? { look } : {}) }),
    removeAgent: (id, confirmed) => agents().remove(id, { confirmed, rethrow: true }),
    resetAgent: (id, confirmed) => agents().reset(id, { confirmed, rethrow: true }),
    switchAgent: (id) => latest.current.showMentor(id),
    agentChat: async (id) => {
      const session = await agents().chat(id);
      if (!session) throw new CommandError("The mentor's conversation could not be opened");
      return session;
    },
    refreshModels: (harnesses, options) =>
      refreshHarnessCatalogs(harnesses, options?.patient ? {} : { timeoutMs: CATALOG_WAIT_MS }),
    liveSession: (id) => latest.current.runtime.sessionsRef.current.find((session) => session.id === id),
    get submission() { return latest.current.submission; },
    flushPersistence: () => latest.current.runtime.flushPersistence(),
    reader: {
      show: async (agentId, page, focus) => {
        // The reader on screen keeps its unsaved edits safe the way a click does.
        if (focus || latest.current.activeAgentId() === agentId) {
          await latest.current.showInMentor(page, agentId);
          return;
        }
        latest.current.mentorView().show(agentId, page);
      },
      close: async (agentId) => {
        if (!await latest.current.leaveReader(agentId)) return false;
        latest.current.mentorView().close(agentId);
        return true;
      },
      current: (agentId) => {
        const view = latest.current.mentorView().viewFor(agentId);
        return { ...(view.page ? { page: view.page } : {}), ...(view.lesson ? { lesson: view.lesson } : {}) };
      },
    },
    library: {
      open: (agentId, change) => latest.current.mentorView().openLibrary(agentId, { ...change, show: true }),
      current: (agentId) => {
        const view = latest.current.mentorView().viewFor(agentId);
        return { visible: view.library, ...(view.segment ? { segment: view.segment } : {}), ...(view.course ? { course: view.course } : {}), ...(view.filter ? { filter: view.filter } : {}) };
      },
    },
    agentApp: (source, requestId, action, input) => {
      const { workspace, runtime, submission, delegation } = latest.current;
      return handleAgentApp(source, requestId, action, input, agentAppHost(source, { workspace, runtime, submission, delegation }));
    },
  };
  return context.current;
}
