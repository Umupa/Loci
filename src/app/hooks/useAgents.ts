import { deleteCanvas, loadCanvases } from "../../features/canvas/canvas";
import { agentTemplate, templateSoul } from "../../features/agents/model/agentTemplates";
import { deleteAgentDocument, saveAgentDocuments } from "../../features/agents/model/agentDocuments";
import { documentsInText } from "../../features/sessions/model/cards";
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore, type SetStateAction } from "react";
import { ask } from "@tauri-apps/plugin-dialog";
import { homeDir } from "../../platform/tauri/fs";
import { forgetHarnessSession } from "../../integrations/harness/core/registry";
import { deleteSession } from "../../features/sessions/data/sessionStore";
import { sessionChildHarnesses } from "../../features/sessions/model/handoff";
import { newDefaultSession, type Block, type Session } from "../../features/sessions/model/session";
import {
  agentCanvasScope, agentLook, agentState, agentsSnapshot, createAgent, findAgent, listAgents, removeAgent, subscribeAgents,
  type AgentState,
} from "../../features/agents/model/agent";
import { forgetAgentContext, loadAgentFiles, saveAgentFile } from "../../features/agents/model/agentFiles";
import { agentPreview, saveAgentPreview } from "../../features/agents/model/agentPreview";
import { forgetAgentRotation } from "../../features/agents/model/agentRotation";
import { ensureAgentSession, resetAgentSession } from "../../features/agents/model/agentWorkspace";
import { archiveOlderTurns, canArchive, loadTranscriptPage, planArchive, type TranscriptPage } from "../../features/agents/model/agentTranscript";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";

type Options = {
  runtime: SessionRuntime;
  submission: SessionSubmission;
  /** A saved conversation by id, from memory or the store. */
  loadSession: (id: string) => Promise<Session | null>;
  onError: (error: unknown) => void;
  /** The agent's conversation is ready to be shown. */
  onShow: (agentId: string, session: Session) => void;
  /** All conversations the user is currently reading, including unfocused panes. */
  visibleSessionIds?: ReadonlySet<string>;
  /** Keep the agent's pane in place when its conversation is reset. */
  onReplaceSession: (previousId: string, fresh: Session) => void;
  /** Remove every pane for a deleted conversation. */
  onRemoveSession: (sessionId: string) => void;
};

/** Owns the agents' conversations: opening one into view, resetting it and deleting it. */
export function useAgents(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const { sessions } = options.runtime;
  const snapshot = useSyncExternalStore(subscribeAgents, agentsSnapshot);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const agents = useMemo(() => listAgents(), [snapshot]);
  const [viewId, setViewId] = useState<string | null>(null);
  const [details, setDetails] = useState<ReadonlyMap<string, boolean>>(() => new Map());
  const isDetailsOpen = useCallback((agentId: string) => details.get(agentId) ?? false, [details]);
  const setDetailsOpenFor = useCallback((agentId: string, open: SetStateAction<boolean>) => {
    setDetails((current) => {
      const value = typeof open === "function" ? open(current.get(agentId) ?? false) : open;
      if ((current.get(agentId) ?? false) === value) return current;
      return new Map(current).set(agentId, value);
    });
  }, []);
  const viewIdRef = useRef(viewId);
  viewIdRef.current = viewId;
  // A slower open must not replace the agent chosen after it.
  const request = useRef(0);

  const viewAgent = viewId ? agents.find((agent) => agent.id === viewId) : undefined;
  const viewSession = viewAgent?.sessionId ? sessions.find((session) => session.id === viewAgent.sessionId) : undefined;

  /** What each agent is doing; one whose conversation is not loaded is at rest. */
  const states = useMemo(() => {
    const map = new Map<string, AgentState>();
    for (const agent of agents) {
      const session = agent.sessionId ? sessions.find((entry) => entry.id === agent.sessionId) : undefined;
      if (session) map.set(agent.id, agentState(session));
    }
    return map;
  }, [agents, sessions]);

  // A document goes into the agent's library as soon as its message is complete, not when
  // the turn ends: a turn can run on for minutes after the document was written.
  const filed = useRef(new Map<string, Set<string>>());
  useEffect(() => {
    for (const agent of agents) {
      const session = agent.sessionId ? sessions.find((entry) => entry.id === agent.sessionId) : undefined;
      if (!session) continue;
      const known = filed.current.get(session.id);
      const seen = known ?? new Set<string>();
      if (!known) filed.current.set(session.id, seen);
      for (const block of session.blocks) {
        if (block.role !== "assistant" || block.tool || block.streaming) continue;
        const key = `${block.id}:${block.text.length}`;
        if (seen.has(key)) continue;
        seen.add(key);
        // What was already there when the conversation loaded is in the library, or was removed from it.
        if (!known) continue;
        const documents = documentsInText(block.text);
        if (documents.length) void saveAgentDocuments(agent.id, documents).catch(() => undefined);
      }
    }
  }, [agents, sessions]);

  /** Archived pages stay with their conversation when pane focus changes. */
  type Earlier = { blocks: Block[]; next?: TranscriptPage; before?: number };
  const [earlier, setEarlier] = useState<ReadonlyMap<string, Earlier>>(() => new Map());
  const earlierRef = useRef(earlier);
  earlierRef.current = earlier;
  const pageRequests = useRef(new Map<string, Promise<Earlier | undefined>>());
  const readEarlier = useCallback((sessionId: string, append: boolean): Promise<Earlier | undefined> => {
    const pending = pageRequests.current.get(sessionId);
    if (pending) return pending;
    const shown = earlierRef.current.get(sessionId);
    if (shown && (!append || (!shown.next && shown.before === undefined))) return Promise.resolve(shown);
    // Both targeted navigation and the manual history button share this read.
    const request = Promise.resolve().then(async () => {
      const page = shown?.next ?? await loadTranscriptPage(sessionId, shown?.before);
      if (pageRequests.current.get(sessionId) !== request) return undefined;
      const next: Earlier = !shown ? { blocks: [], next: page }
        : { blocks: page ? [...page.blocks, ...shown.blocks] : shown.blocks,
          ...(page?.hasOlder ? { before: page.seq } : {}) };
      const updated = new Map(earlierRef.current).set(sessionId, next);
      earlierRef.current = updated;
      setEarlier(updated);
      return next;
    }).finally(() => {
      if (pageRequests.current.get(sessionId) === request) pageRequests.current.delete(sessionId);
    });
    pageRequests.current.set(sessionId, request);
    return request;
  }, []);
  const viewSessionId = viewSession?.id;
  useEffect(() => {
    const visible = options.visibleSessionIds ?? new Set(viewSessionId ? [viewSessionId] : []);
    for (const agent of agents) {
      const id = agent.sessionId;
      if (!id || !visible.has(id) || earlierRef.current.has(id) || pageRequests.current.has(id)) continue;
      void readEarlier(id, false).catch((error) => latest.current.onError(error));
    }
  }, [agents, options.visibleSessionIds, viewSessionId, readEarlier]);
  const earlierBlocksFor = useCallback((sessionId: string) => {
    const blocks = earlier.get(sessionId)?.blocks;
    if (!blocks?.length) return blocks;
    // The page write can finish after the pane opens, while its live turns are kept.
    const liveIds = new Set(sessions.find((session) => session.id === sessionId)?.blocks.map((block) => block.id));
    return blocks.filter((block) => !liveIds.has(block.id));
  }, [earlier, sessions]);
  const hasEarlier = useCallback((sessionId: string) => {
    const shown = earlier.get(sessionId);
    return !!shown?.next || shown?.before !== undefined;
  }, [earlier]);
  const loadEarlier = useCallback(async (sessionId: string) => {
    const shown = earlierRef.current.get(sessionId);
    if (!shown || (!shown.next && shown.before === undefined) || pageRequests.current.has(sessionId)) return;
    try {
      await readEarlier(sessionId, true);
    } catch (error) {
      latest.current.onError(error);
    }
  }, [readEarlier]);
  const ensureBlockLoaded = useCallback(async (sessionId: string, blockId: string): Promise<boolean> => {
    if (latest.current.runtime.sessionsRef.current.find((session) => session.id === sessionId)?.blocks.some((block) => block.id === blockId)) return true;
    if (!listAgents().some((agent) => agent.sessionId === sessionId)) return false;
    let shown = await readEarlier(sessionId, false);
    while (shown) {
      if (shown.blocks.some((block) => block.id === blockId)) return true;
      if (!shown.next && shown.before === undefined) return false;
      shown = await readEarlier(sessionId, true);
    }
    return false;
  }, [readEarlier]);
  const forgetEarlier = useCallback((sessionId: string) => {
    pageRequests.current.delete(sessionId);
    if (!earlierRef.current.has(sessionId)) return;
    const next = new Map(earlierRef.current);
    next.delete(sessionId);
    earlierRef.current = next;
    setEarlier(next);
  }, []);

  // An idle chat that has grown long hands its oldest turns to the page store. One in
  // view waits until the user leaves, so nothing they are reading disappears.
  const archiving = useRef(new Set<string>());
  useEffect(() => {
    for (const agent of agents) {
      const visible = options.visibleSessionIds ?? new Set(viewSessionId ? [viewSessionId] : []);
      const chat = agent.sessionId && !visible.has(agent.sessionId)
        ? sessions.find((session) => session.id === agent.sessionId) : undefined;
      if (!chat || archiving.current.has(chat.id) || !canArchive(chat) || !planArchive(chat.blocks)) continue;
      archiving.current.add(chat.id);
      void archiveOlderTurns(chat).then(async (kept) => {
        if (!kept) return;
        const { runtime, visibleSessionIds } = latest.current;
        // Opening the pane during the page write must not remove what is now being read.
        const focusedSessionId = viewIdRef.current ? findAgent(viewIdRef.current)?.sessionId : undefined;
        if (visibleSessionIds ? visibleSessionIds.has(chat.id) : focusedSessionId === chat.id) return;
        // Only the exact chat that was archived gives up its turns.
        runtime.updateSessions((current) => current.map((session) => session === chat ? { ...session, blocks: kept } : session));
        forgetEarlier(chat.id);
        await runtime.persistSession(chat.id);
      }).catch((error) => latest.current.onError(error)).finally(() => archiving.current.delete(chat.id));
    }
  }, [agents, sessions, options.visibleSessionIds, viewSessionId, forgetEarlier]);

  // The rail shows what each agent last said, also for chats that are not loaded.
  useEffect(() => {
    for (const agent of agents) {
      const chat = agent.sessionId ? sessions.find((session) => session.id === agent.sessionId) : undefined;
      if (chat && !chat.busy) saveAgentPreview(agent.id, agentPreview(chat));
    }
  }, [agents, sessions]);

  const addSession = useCallback((session: Session) => {
    const { runtime } = latest.current;
    runtime.bindRestoredSession(session);
    runtime.updateSessions((current) => current.some((entry) => entry.id === session.id) ? current : [...current, session]);
  }, []);

  const open = useCallback(async (agentId: string) => {
    const turn = ++request.current;
    try {
      const session = await ensureAgentSession(agentId, {
        home: homeDir,
        load: (id) => latest.current.loadSession(id),
        create: (cwd) => newDefaultSession(cwd),
        add: addSession,
      });
      if (!session || turn !== request.current) return;
      setViewId(agentId);
      latest.current.onShow(agentId, session);
    } catch (error) {
      latest.current.onError(error);
    }
  }, [addSession]);

  /**
   * Opens a new agent ready for the user's purpose or first task. Creating it
   * does not run a model; a template supplies its standing instructions.
   */
  const create = useCallback(async (templateId?: string) => {
    const template = agentTemplate(templateId);
    const agent = createAgent([], template ? { name: template.name, role: template.role, avatar: template.avatar, color: template.color } : {});
    const turn = ++request.current;
    try {
      const session = await ensureAgentSession(agent.id, {
        home: homeDir,
        load: (id) => latest.current.loadSession(id),
        create: (cwd) => newDefaultSession(cwd),
        add: addSession,
      });
      if (!session || turn !== request.current) return;
      setViewId(agent.id);
      latest.current.onShow(agent.id, session);
      // A template is an agent whose soul is already written: nothing else is sent to it.
      if (template) await saveAgentFile(agent.id, "soul", templateSoul(template), (await loadAgentFiles(agent.id)).soulHash);
    } catch (error) {
      latest.current.onError(error);
    }
  }, [addSession]);

  /** Sync rail selection to the focused pane without reopening its conversation. */
  const select = useCallback((agentId?: string) => {
    const next = agentId ?? null;
    if (next !== viewIdRef.current) request.current += 1;
    viewIdRef.current = next;
    setViewId(next);
  }, []);

  const close = useCallback(() => {
    request.current += 1;
    setViewId(null);
  }, []);

  /** Stops the conversation's work and deletes its record; the agent itself stays. */
  const discardSession = useCallback(async (session: Session, notify = true) => {
    const { runtime, submission } = latest.current;
    await submission.stopSessionWork(session.id);
    await runtime.flushPersistence();
    await deleteSession(session.id);
    for (const harness of sessionChildHarnesses(session)) void forgetHarnessSession(harness, session.id).catch(() => undefined);
    runtime.updateSessions((current) => current.filter((entry) => entry.id !== session.id));
    forgetEarlier(session.id);
    if (notify) latest.current.onRemoveSession(session.id);
  }, [forgetEarlier]);

  const reset = useCallback(async (agentId: string) => {
    const agent = findAgent(agentId);
    const current = agent?.sessionId
      ? latest.current.runtime.sessionsRef.current.find((session) => session.id === agent.sessionId) : undefined;
    if (!agent || !current) return;
    if (!await ask(`Reset ${agentLook(agent).name}'s conversation? Its messages are removed; its soul and memory stay.`,
      { title: "Reset conversation", kind: "warning", okLabel: "Reset", cancelLabel: "Cancel" })) return;
    try {
      await resetAgentSession(current, {
        stop: (id) => latest.current.submission.stopSessionWork(id),
        remove: (session) => discardSession(session, false),
        replace: (previousId, fresh) => {
          addSession(fresh);
          latest.current.onReplaceSession(previousId, fresh);
        },
      });
    } catch (error) {
      latest.current.onError(error);
    }
  }, [addSession, discardSession]);

  /** Deletes the agent's conversation, then the agent. Its files stay on disk. */
  const remove = useCallback(async (agentId: string) => {
    const agent = findAgent(agentId);
    if (!agent) return;
    if (!await ask(`Delete ${agentLook(agent).name}? Its conversation is permanently removed. Its documents go with it; its soul and memory files stay on disk.`,
      { title: "Delete agent", kind: "warning", okLabel: "Delete", cancelLabel: "Cancel" })) return;
    try {
      if (viewIdRef.current === agentId) {
        close();
      }
      if (agent.sessionId) {
        const session = latest.current.runtime.sessionsRef.current.find((entry) => entry.id === agent.sessionId)
          ?? await latest.current.loadSession(agent.sessionId);
        if (session) await discardSession(session);
        else latest.current.onRemoveSession(agent.sessionId);
        forgetAgentContext(agent.sessionId);
        forgetAgentRotation(agent.sessionId);
      }
      removeAgent(agentId);
      setDetails((current) => {
        const next = new Map(current);
        next.delete(agentId);
        return next;
      });
      void deleteAgentDocument(agentId).catch(() => undefined);
      void import("../../features/learning/model/learningStore").then(({ deleteOwnerWidgets }) => deleteOwnerWidgets({ kind: "agent", id: agentId })).catch(latest.current.onError);
      // Its library goes with it, canvases included.
      void loadCanvases(true).then((all) => Promise.all(all.filter((canvas) => canvas.cwd === agentCanvasScope(agentId)).map((canvas) => deleteCanvas(canvas.id)))).catch(() => undefined);
      saveAgentPreview(agentId, undefined);
    } catch (error) {
      latest.current.onError(error);
    }
  }, [close, discardSession]);

  return {
    agents, states, viewAgent, viewSession, earlierBlocksFor, hasEarlier, loadEarlier, ensureBlockLoaded, isDetailsOpen, setDetailsOpenFor,
    open, create, select, close, reset, remove,
  };
}
