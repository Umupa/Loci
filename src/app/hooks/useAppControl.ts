import { importAgentSource, listAgentDocuments, readAgentDocument } from "../../features/agents/model/agentDocuments";
import { useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWebviewWindow } from "@tauri-apps/api/webviewWindow";
import { canAccessAgentAppProject, handleAgentApp, type AppSessionListing } from "../../features/agent-app/model/agentApp";
import { agentForSession, findAgent, updateAgent } from "../../features/agents/model/agent";
import { habitRunAgent, loadHabits, updateHabits } from "../../features/agents/model/agentHabits";
import { loadAgentFiles, readAgentFile, writeAgentFile } from "../../features/agents/model/agentFiles";
import { readAgentConversation } from "../../features/agents/model/agentTranscript";
import { handleCanvasBridge } from "../../features/canvas/checkpoints";
import { deleteCourse, loadCourse, loadCourseSummaries, saveCourse } from "../../features/learning/model/course";
import { listSessionsByProject } from "../../features/sessions/data/sessionStore";
import { newSession, sessionDraftBlock, type Session } from "../../features/sessions/model/session";
import { sameProjectPath } from "../../features/projects/model/recents";
import { getNote, loadNotes, NOTES_CHANGED_EVENT, upsertNote } from "../../features/notes";
import type { SessionRuntime } from "./useSessionRuntime";
import type { SessionSubmission } from "./useSessionSubmission";
import type { AgentDelegation } from "./useAgentDelegation";

/** What the app CLI needs from the window: its sessions, and where it shows things. */
export type AppControlWorkspace = {
  loadSession: (id: string) => Promise<Session | null>;
  /** Keeps a session in memory; `reveal` also shows it in the current mentor's reader. */
  addSession: (session: Session, options?: { reveal?: boolean }) => unknown;
  archiveSession: (id: string, archived: boolean) => Promise<boolean>;
  removeSession: (id: string) => Promise<boolean>;
  isCanvasOpen: (id: string) => boolean;
  revealCanvas: (id: string, sessionId: string) => void;
};

type Options = { workspace: AppControlWorkspace; runtime: SessionRuntime; submission: SessionSubmission; delegation?: AgentDelegation };
type ControlRequest = { id: string; namespace: string; sessionId: string; requestId: string; action: string; input: Record<string, unknown> };

/** Routes authenticated loopback requests into the same actions used by the UI. */
export function useAppControl(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const receipts = useRef(new Map<string, { signature: string; promise: Promise<unknown> }>());
  useEffect(() => {
    const listening = getCurrentWebviewWindow().listen<ControlRequest>("loci-control-request", ({ payload }) => {
      const handle = async () => {
        const { workspace, runtime, submission, delegation } = latest.current;
        const source = runtime.sessionsRef.current.find((session) => session.id === payload.sessionId);
        // The built-in Excalidraw MCP server reaches canvases here; it needs no app access grant.
        if (payload.namespace === "canvas") {
          if (!source) throw new Error("This session cannot draw on Loci canvases");
          return handleCanvasBridge(source, payload.action, payload.input, { isOpen: workspace.isCanvasOpen, reveal: workspace.revealCanvas });
        }
        if (payload.namespace !== "app") throw new Error("Unknown CLI namespace");
        if (!source) throw new Error("This session cannot use the Loci app CLI");
        const key = `${source.id}:${payload.requestId}`;
        const signature = JSON.stringify([payload.action, payload.input]);
        const previous = receipts.current.get(key);
        if (previous) {
          if (previous.signature !== signature) throw new Error("Request ID was already used with different input");
          return previous.promise;
        }
        // An agent's chat lives outside its projects, so its reach follows its roster.
        // A habit's hidden run works for its agent, with the same reach.
        const habitRunOf = habitRunAgent(source.id);
        const agent = agentForSession(source.id) ?? (habitRunOf ? findAgent(habitRunOf) : undefined);
        const reaches = (cwd: string) => canAccessAgentAppProject(source, cwd, agent?.projects);
        const ensureSession = async (id: string): Promise<Session> => {
          const target = runtime.sessionsRef.current.find((session) => session.id === id) ?? await workspace.loadSession(id);
          if (!target || !reaches(target.cwd)) throw new Error("Session is unavailable in this project");
          runtime.bindRestoredSession(target);
          runtime.updateSessions((current) => current.some((session) => session.id === id) ? current : [...current, target]);
          return target;
        };
        const promise = handleAgentApp(source, payload.requestId, payload.action, payload.input, {
          start: async (launch, id, placement, notify) => {
            const existing = runtime.sessionsRef.current.find((session) => session.id === id) ?? await workspace.loadSession(id);
            const previous = existing?.blocks.find((block) => block.appRequestId === id);
            if (previous) {
              if (previous.text !== launch.prompt || (!launch.draft && previous.draft)) throw new Error("Request ID was already used for another session launch");
              return;
            }
            if (existing?.blocks.some((block) => block.role === "user" && !block.draft)) return;
            if (existing && sessionDraftBlock(existing)) throw new Error("Session ID already has a different draft");
            // There are no panes to place a session beside; an older request's placement still starts it.
            if (placement) {
              const pane = runtime.sessionsRef.current.find((entry) => entry.id === placement.besideSessionId);
              if (!pane || !reaches(pane.cwd)) throw new Error("The selected session is not open in this project");
            }
            const session = existing ?? { ...newSession(launch.harness, launch.cwd, launch.model, launch.runtimeMode, launch.modelSettings), id };
            workspace.addSession(session, { reveal: launch.reveal === true });
            // The agent hears back once this session stops, together with the others it launched this turn.
            const watch = notify && delegation ? delegation.monitor(source.id, id, id, launch.cwd, launch.prompt) : undefined;
            try {
              const accepted = launch.draft
                ? submission.saveDraft(id, launch.prompt, [], id)
                : await submission.submit(id, launch.prompt, [], { appRequestId: id, ...(watch ? { onSettled: watch } : {}) });
              if (!accepted) throw new Error("Session could not accept the requested prompt");
              await runtime.flushPersistence();
              watch?.accept();
            } catch (error) {
              watch?.discard();
              throw error;
            }
          },
          sessions: async (cwd): Promise<AppSessionListing[]> => {
            const stored = await listSessionsByProject(cwd);
            const rows = new Map<string, AppSessionListing>(stored.map((session) => [session.id, { id: session.id, title: session.title, harness: session.harness, model: session.model, busy: false, hasDraft: !!session.draft }]));
            for (const session of runtime.sessionsRef.current) if (sameProjectPath(session.cwd, cwd) && !session.ephemeral && !agentForSession(session.id)) rows.set(session.id, { id: session.id, title: session.title, harness: session.harness, model: session.model, busy: !!session.busy, hasDraft: !!sessionDraftBlock(session) });
            return [...rows.values()];
          },
          session: async (id) => {
            const target = runtime.sessionsRef.current.find((session) => session.id === id) ?? await workspace.loadSession(id);
            return target && reaches(target.cwd) ? target : null;
          },
          send: async (id, prompt, requestId, notify) => {
            const target = await ensureSession(id);
            const previous = target.blocks.find((block) => block.appRequestId === requestId);
            if (previous) {
              if (previous.text !== prompt) throw new Error("Request ID was already used with another prompt");
              if (previous.draft) throw new Error("Request ID belongs to an unsent draft");
              return { alreadySubmitted: true };
            }
            if (target.busy) throw new Error("Session is busy; try again when it finishes");
            if (sessionDraftBlock(target)) throw new Error("Session already has a draft; send or remove it first");
            const watch = notify && delegation ? delegation.monitor(source.id, requestId, id, target.cwd, prompt) : undefined;
            try {
              if (!await submission.submit(id, prompt, [], { appRequestId: requestId, ...(watch ? { onSettled: watch } : {}) })) throw new Error("Session could not accept the follow-up");
              await runtime.flushPersistence();
              watch?.accept();
            } catch (error) {
              watch?.discard();
              throw error;
            }
            return { alreadySubmitted: false };
          },
          stop: async (id) => {
            await ensureSession(id);
            await submission.stopSessionWork(id);
            delegation?.dismiss(source.id, id);
          },
          remove: async (id, mode) => {
            await ensureSession(id);
            if (mode === "archive") await workspace.archiveSession(id, true);
            else if (!await workspace.removeSession(id)) throw new Error("The user did not confirm deleting this session");
            delegation?.dismiss(source.id, id);
          },
          draft: async (id, prompt, requestId) => {
            const target = await ensureSession(id);
            const previous = target.blocks.find((block) => block.appRequestId === requestId);
            if (previous) {
              if (previous.text !== prompt) throw new Error("Request ID was already used with another prompt");
              return { alreadySaved: true, draft: !!previous.draft };
            }
            if (target.busy) throw new Error("Session is busy; try again when it finishes");
            if (sessionDraftBlock(target)) throw new Error("Session already has a draft; send or remove it first");
            if (!submission.saveDraft(id, prompt, [], requestId)) throw new Error("Session could not accept a draft");
            await runtime.flushPersistence();
            return { alreadySaved: false, draft: true };
          },
          agentOf: () => agent && { id: agent.id, projects: agent.projects, ...(agent.sessionId ? { chatId: agent.sessionId } : {}), ...(habitRunOf ? { habitRun: true } : {}) },
          readAgentChat: async (chatId, options) => {
            const chat = runtime.sessionsRef.current.find((session) => session.id === chatId) ?? await workspace.loadSession(chatId);
            if (!chat) throw new Error("The conversation is no longer available");
            return readAgentConversation(chat, options);
          },
          habits: { load: loadHabits, update: updateHabits },
          renameAgent: (agentId, look) => { updateAgent(agentId, (current) => ({ ...current, ...look })); },
          files: { load: loadAgentFiles, read: readAgentFile, write: writeAgentFile },
          documents: { list: listAgentDocuments, read: readAgentDocument, importSource: importAgentSource },
          courses: {
            list: async (agentId) => (await loadCourseSummaries()).filter((course) => course.agentId === agentId),
            read: (agentId, id) => loadCourse(id, agentId),
            write: saveCourse,
            remove: deleteCourse,
          },
          notes: () => loadNotes(true), note: getNote,
          saveNote: async (note) => { const saved = await upsertNote(note); window.dispatchEvent(new Event(NOTES_CHANGED_EVENT)); return saved; },
        });
        receipts.current.set(key, { signature, promise });
        void promise.catch(() => { if (receipts.current.get(key)?.promise === promise) receipts.current.delete(key); });
        if (receipts.current.size > 256) { const first = receipts.current.keys().next().value; if (first) receipts.current.delete(first); }
        return promise;
      };
      void handle().then(
        (result) => invoke("control_reply", { id: payload.id, response: { ok: true, result } }),
        (error: unknown) => invoke("control_reply", { id: payload.id, response: { ok: false, error: error instanceof Error ? error.message : String(error) } }),
      ).catch(console.error);
    });
    return () => { void listening.then((stop) => stop()); };
  }, []);
}
