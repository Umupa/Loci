import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  appendSteerUser, appendUser, stopStreaming,
} from "../../integrations/harness/core/apply";
import {
  cancelHarnessTurn, canCompactHarnessContext, canRewindHarnessLastTurn,
  canSteerHarness, compactHarnessContext, forgetHarnessSession,
  generateHarnessTitle, isLiveHarness, keepHarnessQuestionOpen,
  respondHarnessApproval, respondHarnessQuestion, rewindHarnessLastTurn,
  runHarnessTextPrompt, sendHarnessTurn, steerHarnessTurn, stopHarnessSession,
} from "../../integrations/harness/core/registry";
import type { ApprovalDecision, HarnessEvent } from "../../integrations/harness/core/types";
import {
  canReplaceSessionTitle, formatSessionTitle, HARNESS_LABEL, HARNESS_TITLE,
  removeSessionDraft, sessionDisplayTitle, sessionDraftBlock, sessionWorkCwd,
  type Attachment, type Block, type BtwThread, type ComposerTurnOptions,
  type HarnessId, type RuntimeMode, type Session,
} from "../../features/sessions/model/session";
import {
  nativeModelId, preferredModelSettings, resolveModel,
  saveLastModelSettings, saveRecentModelChoice,
} from "../../features/sessions/model/models";
import { titleFromPrompt } from "../../features/sessions/model/session";
import { displayAttachments, prepareAttachments } from "../../features/sessions/model/attachments";
import { preparePrompt } from "../../features/sessions/model/promptPreparation";
import { consumeOperatorCommand, operatorEnabledInThread } from "../../features/sessions/model/operatorCommand";
import {
  appendPreparingHandoff, buildDeterministicHandoff, chooseHandoffBrief,
  completeHandoff, consumeHandoff, isPreparingHandoff, pendingHandoff,
  planComposerSwitch, sessionChildHarnesses, shouldAskOutgoingAgent,
  userMessagesAfterHandoff, wrapHandoffPrompt,
} from "../../features/sessions/model/handoff";
import { requestOutgoingHandoff } from "../../features/sessions/model/handoffTurn";
import { createEditedResendAttempt, createEditedResendCoordinator } from "../../features/sessions/model/editLastTurn";
import { dropContextWindow } from "../../features/sessions/model/contextUsage";
import { shouldGenerateSessionTitle } from "../../features/sessions/model/sessionTitle";
import {
  canDispatchQueuedHead, dequeueQueuedMessage, queuedMessageForSubmit,
} from "../../features/sessions/model/messageQueue";
import { canAutoContinue, CONTINUE_PROMPT } from "../../features/sessions/model/inFlight";
import { USAGE_LIMIT_RESUME_GRACE_MS, usageLimitResumeDue } from "../../features/sessions/model/usageLimit";
import {
  applyBtwHarnessEvent, buildBtwPrompt, btwTurnHarness, harnessForTurn,
  replaceBtwThread, sealBtwResponseBlocks, supportsBtwHarness,
} from "../../features/sessions/model/btw";
import type { UserQuestionReply } from "../../features/sessions/model/userQuestion";
import { discardDraftSessionRecord, shouldPersistSession } from "../../features/sessions/data/sessionStore";
import {
  providerAccountExists, selectedProviderAccountId,
} from "../../features/providers/model/providerAccounts";
import { composeNoteMessage, noteCardMeta, type NoteComposerCard } from "../../features/notes";
import { looksLikeProject } from "../../features/projects/model/recents";
import { isNativeCommandPrompt } from "../../features/skills/model/skills";
import { loadFollowUpBehavior, type FollowUpBehavior } from "../../features/settings/model/settings";
import type { SubmissionAcceptance } from "../model/submissionAcceptance";
import type { SessionRuntime } from "./useSessionRuntime";

export type SubmitOptions = ComposerTurnOptions & {
  followUpBehavior?: FollowUpBehavior;
  noteCard?: NoteComposerCard;
  queuedMessageId?: string;
  refreshTitle?: boolean;
  projectLocationReady?: boolean;
};
type Submit = (sessionId: string, text: string, attachments?: Attachment[], options?: SubmitOptions) => SubmissionAcceptance;
type SubmissionOptions = {
  runtime: SessionRuntime;
  /** Resolve a moved project and update session paths before accepting a turn. */
  synchronizeProject?: (cwd: string) => Promise<void>;
  onDraftDiscarded?: (sessionId: string) => void;
};

function shellPath(path: string): string {
  return `'${path.replace(/'/g, `'"'"'`)}'`;
}

async function operatorPrompt(): Promise<string> {
  const cli = `${shellPath(await invoke<string>("app_cli_path"))} app`;
  return `\n\n<loci_app>\nThe user's Operator command enables app access in this thread, including later turns without the command. You can start session tabs or split session panes right or down, read and continue other project sessions, save unsent drafts, organize session folders, and read or write saved notes through its local CLI. You can also list, create, rename, and delete Excalidraw canvases, and read or write their scene data (Excalidraw JSON) via canvas.read-data and canvas.write-data in the current project. Read the existing scene before extending it: write-data replaces the whole scene and updates open panes. Basic programmatic shapes support labels and are normalized by Excalidraw; full scenes retain images and bindings. Each write must use either all native elements or all shorthand elements; normalize new elements before appending to a native scene. If an external Excalidraw MCP is available, use it for diagram design or preview; its checkpoint is separate from a Loci canvas. Persist the actual scene through this CLI, excluding MCP cameraUpdate/delete/restoreCheckpoint commands. Run \`${cli} --help\` for exact commands and JSON fields, then use it as needed for the user's request. When reading another session, start with its latest two or three user/assistant exchanges. Request older exchanges with nextBefore or a larger excerpt only if needed. The CLI uses a session credential already in your environment; never print it. New sessions inherit this session's permission mode unless runtimeMode is set explicitly. For a new session with a draft, call sessions.start with its prompt and draft:true; do not submit a seed prompt. The returned ID can be used as besideSessionId to split its pane again or moved into a folder immediately. A normal sessions.start submits its prompt but returns after acceptance, so do not wait for that agent to finish before organizing it.\n</loci_app>`;
}

function withHarnessChoice(session: Session, harness: HarnessId, model: string, modelSettings: Record<string, string>): Session {
  return {
    ...session, harness, model, modelSettings,
    title: session.blocks.length === 0 ? HARNESS_LABEL[harness]
      : formatSessionTitle(harness, sessionDisplayTitle(session.title, session.harness)),
    ...(session.model === model ? {} : { context: dropContextWindow(session.context) }),
    ...(session.harness === harness ? {} : { providerSessionId: undefined, providerAccountId: undefined }),
  };
}

/** Coordinates ordinary turns and their local UI operations without owning layout. */
export function useSessionSubmission(options: SubmissionOptions) {
  const { runtime } = options;
  const { sessions, sessionsRef, updateSessions: setSessions, enqueueEvent: enqueueHarnessEvent,
    flushEvents: flushHarnessEvents, persistSession } = runtime;
  const optionsRef = useRef(options);
  optionsRef.current = options;
  const runtimeRef = useRef(runtime);
  runtimeRef.current = runtime;
  const editedResends = useRef(createEditedResendCoordinator()).current;
  const submitRef = useRef<Submit>(() => false);
  const projectSyncs = useRef(new Map<string, Promise<void>>());
  const btwRequestsRef = useRef(new Map<string, { sessionId: string; controller: AbortController }>());
  const queueDispatchingRef = useRef(new Set<string>());
  const usageResumingRef = useRef(new Set<string>());

  const submitSession = useCallback<Submit>((sessionId, text, attachments = [], options) => {
    const rt = runtimeRef.current;
    if (editedResends.isActive(sessionId)) return false;
    flushHarnessEvents();
    const stored = sessionsRef.current.find((session) => session.id === sessionId);
    if (!stored || isPreparingHandoff(stored)) return false;
    if (options?.appRequestId && stored.busy) return false;
    const receipt = options?.appRequestId
      ? stored.blocks.find((block) => block.appRequestId === options.appRequestId && !block.draft)
      : undefined;
    if (receipt) return receipt.text === text;
    const draft = options?.draftBlockId
      ? stored.blocks.find((block) => block.id === options.draftBlockId && block.role === "user" && block.draft)
      : undefined;
    if (options?.draftBlockId && !draft) return false;
    let current = draft ? { ...stored, blocks: stored.blocks.filter((block) => block.id !== draft.id) } : stored;
    const edited = options?.resendEdited ? createEditedResendAttempt(current, options.onResendRejected) : undefined;
    if (options?.resendEdited && !edited) return false;
    if (edited) current = { ...current, blocks: edited.blocks };
    if (options?.queuedMessageId && !queuedMessageForSubmit(current, options.queuedMessageId,
      options.followUpBehavior === "steer" ? "steer" : "dispatch")) return false;
    const noteCard = options && "noteCard" in options ? options.noteCard : current.noteCard;
    if (!text.trim() && !attachments.length && !noteCard) return false;
    const activation = consumeOperatorCommand(text);
    const visibleText = activation.matched ? activation.text.trim() || "Explain what you can do in Loci with the app CLI." : text;
    const appAccess = activation.matched || operatorEnabledInThread(current.blocks);
    const rawCommand = !activation.matched && isNativeCommandPrompt(text, current.harness);
    const promptText = rawCommand ? text : composeNoteMessage(noteCard, visibleText);
    const pendingSwitch = current.pendingSwitch?.from !== current.harness ? current.pendingSwitch : undefined;
    const visible = displayAttachments(attachments);
    const cards = {
      ...(!rawCommand && noteCard ? { noteCard: noteCardMeta(noteCard) } : {}),
      ...(activation.matched ? { loci: true } : {}),
      ...((options?.appRequestId ?? draft?.appRequestId)
        ? { appRequestId: options?.appRequestId ?? draft?.appRequestId } : {}),
    };
    if (current.busy && !pendingSwitch) {
      if (activation.matched && options?.queuedMessageId && options.followUpBehavior === "steer") return false;
      const followUp = activation.matched ? "queue"
        : current.backgroundTasks?.length ? "steer" : options?.followUpBehavior ?? loadFollowUpBehavior();
      if (followUp === "queue") {
        setSessions((previous) => previous.map((session) => session.id === sessionId ? {
          ...session, noteCard: rawCommand ? session.noteCard : undefined,
          queuedMessages: [...(session.queuedMessages ?? []), { id: crypto.randomUUID(), text, attachments, noteCard }],
          queueStatus: session.queueStatus === "paused" ? "paused" : "active",
        } : session));
        rt.continued(sessionId);
        return true;
      }
      if (!canSteerHarness(current.harness)) return false;
      setSessions((previous) => previous.map((session) => {
        if (session.id !== sessionId) return session;
        const dequeued = options?.queuedMessageId ? dequeueQueuedMessage(session, options.queuedMessageId) : session;
        return appendSteerUser({ ...dequeued, noteCard: rawCommand ? session.noteCard : undefined }, visibleText, visible, cards);
      }));
      rt.continued(sessionId);
      void (async () => {
        try {
          const prepared = await prepareAttachments(attachments);
          const prompt = await preparePrompt(promptText, { harness: current.harness, sessionId, cwd: current.cwd });
          await steerHarnessTurn({ harness: current.harness, sessionId, cwd: current.cwd,
            model: current.model, modelSettings: current.modelSettings, text: prompt, attachments: prepared });
        } catch (error) {
          enqueueHarnessEvent(sessionId, { type: "session.error", message: String(error) });
          flushHarnessEvents();
        }
      })();
      return true;
    }
    if (!options?.projectLocationReady && looksLikeProject(current.cwd) && optionsRef.current.synchronizeProject) {
      let sync = projectSyncs.current.get(current.cwd);
      if (!sync) {
        sync = optionsRef.current.synchronizeProject(current.cwd);
        projectSyncs.current.set(current.cwd, sync);
        void sync.then(() => projectSyncs.current.delete(current.cwd), () => projectSyncs.current.delete(current.cwd));
      }
      return sync.then(() => submitRef.current(sessionId, text, attachments, { ...options, projectLocationReady: true }))
        .catch((error: unknown) => {
          enqueueHarnessEvent(sessionId, { type: "session.error", message: error instanceof Error ? error.message : String(error) });
          flushHarnessEvents();
          edited?.reject();
          return false;
        });
    }
    const providerAccountId = current.providerAccountId ?? selectedProviderAccountId(current.harness, current.cwd);
    if (!providerAccountExists(current.harness, providerAccountId)) {
      enqueueHarnessEvent(sessionId, { type: "session.error", message: "This conversation uses a removed provider account. Switch accounts from the usage control to start a new conversation." });
      flushHarnessEvents();
      return false;
    }
    if (!isLiveHarness(current.harness)) return false;
    saveRecentModelChoice(current.harness, current.model);
    const generation = rt.beginTurn(sessionId);
    const isCurrent = () => rt.isCurrentTurn(sessionId, generation);
    const firstTurn = current.blocks.length === 0;
    const placeholder = canReplaceSessionTitle(current.title, current.harness, HARNESS_LABEL[current.harness]) || !!draft;
    const titleSeed = firstTurn && !noteCard && placeholder
      ? titleFromPrompt(visibleText, current.harness, attachments) : current.title;
    const queuedHandoff = !pendingSwitch ? pendingHandoff(current) : null;
    if (pendingSwitch && current.busy) void cancelHarnessTurn(pendingSwitch.from, sessionId);
    const commitSubmittedTurn = () => setSessions((previous) => previous.map((session) => {
      if (session.id !== sessionId) return session;
      let next: Session = {
        ...session, providerAccountId, usageLimit: undefined,
        noteCard: rawCommand ? session.noteCard : undefined,
        title: firstTurn ? titleSeed : session.title,
        ...(session.queueStatus === "resuming" ? { queueStatus: "active" as const } : {}),
        blocks: draft ? session.blocks.filter((block) => block.id !== draft.id) : session.blocks,
      };
      if (edited) next = edited.replace(next);
      if (options?.queuedMessageId) next = dequeueQueuedMessage(next, options.queuedMessageId);
      if (pendingSwitch) next = appendPreparingHandoff(stopStreaming({ ...next, pendingSwitch: undefined }), pendingSwitch.from, next.harness);
      return appendUser(next, visibleText, visible, cards);
    }));
    if (edited) editedResends.start(sessionId);
    else commitSubmittedTurn();
    rt.continued(sessionId);
    if (shouldGenerateSessionTitle(firstTurn, placeholder, options?.refreshTitle)) {
      void generateHarnessTitle(current.harness, { sessionId, cwd: current.cwd, message: promptText || attachments.map((file) => file.name).join(", "), providerAccountId })
        .then((generated) => {
          if (!generated || !isCurrent()) return;
          setSessions((previous) => previous.map((session) => session.id === sessionId &&
            (options?.refreshTitle || canReplaceSessionTitle(session.title, session.harness, titleSeed))
            ? { ...session, title: formatSessionTitle(session.harness, generated.title) } : session));
        }).catch(() => undefined);
    }
    void (async () => {
      let wrap = queuedHandoff;
      let providerFailed = false;
      const heldEvents: HarnessEvent[] = [];
      const applyEvent = (event: HarnessEvent) => {
        if (!isCurrent()) return;
        if (event.type === "session.error") providerFailed = true;
        if (wrap && (event.type === "session.started" || event.type === "session.providerBound")) {
          setSessions((previous) => previous.map((session) => session.id === sessionId && isPreparingHandoff(session)
            ? { ...completeHandoff(session, wrap!.text), busy: true } : session));
        }
        enqueueHarnessEvent(sessionId, event);
      };
      const accepted = () => {
        if (!edited || edited.isAccepted() || !isCurrent()) return;
        commitSubmittedTurn();
        edited.markAccepted();
        for (const event of heldEvents) applyEvent(event);
        heldEvents.length = 0;
      };
      try {
        if (pendingSwitch) {
          let answer = "";
          if (shouldAskOutgoingAgent(current)) answer = await requestOutgoingHandoff({
            harness: pendingSwitch.from, sessionId, cwd: current.cwd,
            model: pendingSwitch.fromModel, modelSettings: pendingSwitch.fromSettings,
            providerAccountId: pendingSwitch.fromProviderAccountId, userRequest: text,
          });
          if (!isCurrent()) return;
          const latest = sessionsRef.current.find((session) => session.id === sessionId);
          const brief = chooseHandoffBrief(answer, latest ?? current, text);
          await forgetHarnessSession(pendingSwitch.from, sessionId);
          if (!isCurrent()) return;
          wrap = { from: pendingSwitch.from, to: current.harness, text: brief };
        }
        const prepared = await prepareAttachments(attachments);
        const prompt = await preparePrompt(promptText, { harness: current.harness, sessionId, cwd: current.cwd });
        if (!isCurrent()) return;
        if (edited && canRewindHarnessLastTurn(current.harness)) {
          await rewindHarnessLastTurn({ harness: current.harness, sessionId, cwd: current.cwd,
            model: current.model, modelSettings: current.modelSettings, providerAccountId,
            runtimeMode: current.runtimeMode, providerTurnId: edited.providerTurnId,
            onEvent: (event) => { if (isCurrent()) enqueueHarnessEvent(sessionId, event); } });
          edited.markProviderRewound();
          flushHarnessEvents();
          if (!isCurrent()) {
            const latest = sessionsRef.current.find((session) => session.id === sessionId);
            if (latest && !latest.busy && latest.providerSessionId === current.providerSessionId) {
              await forgetHarnessSession(current.harness, sessionId);
              setSessions((previous) => previous.map((session) => session.id === sessionId ? {
                ...edited.recoverAfterFailure(session), providerSessionId: undefined,
              } : session));
            }
            return;
          }
        }
        let sendText = wrap && !rawCommand ? wrapHandoffPrompt(wrap.text, wrap.from, prompt.trim() || CONTINUE_PROMPT,
          queuedHandoff ? userMessagesAfterHandoff(current) : []) : prompt;
        if (activation.matched) sendText += await operatorPrompt();
        if (!isCurrent()) return;
        await sendHarnessTurn({ harness: current.harness, sessionId, cwd: current.cwd,
          model: current.model, modelSettings: current.modelSettings, providerAccountId,
          runtimeMode: current.runtimeMode, appAccess, text: sendText, attachments: prepared,
          ...(edited ? { onAccepted: accepted } : {}),
          onEvent: (event) => {
            if (!isCurrent()) return;
            if (edited && !edited.isAccepted()) heldEvents.push(event);
            else applyEvent(event);
          } });
        accepted();
        if (isCurrent() && wrap) setSessions((previous) => previous.map((session) => {
          if (session.id !== sessionId) return session;
          const ready = isPreparingHandoff(session) ? completeHandoff(session, wrap!.text) : session;
          return rawCommand ? ready : consumeHandoff(ready);
        }));
      } catch (error) {
        if (!isCurrent()) return;
        if (edited && !edited.isAccepted()) {
          heldEvents.length = 0;
          setSessions((previous) => previous.map((session) => session.id === sessionId ? edited.recoverAfterFailure(session) : session));
        }
        if (!providerFailed) enqueueHarnessEvent(sessionId, { type: "session.error", message: error instanceof Error ? error.message : String(error) });
        providerFailed = true;
      } finally {
        edited?.reject();
        if (edited) editedResends.finish(sessionId);
        if (isCurrent()) {
          flushHarnessEvents();
          if (providerFailed) await stopHarnessSession(current.harness, sessionId).catch(() => undefined);
          if (!isCurrent()) return;
          setSessions((previous) => previous.map((session) => {
            if (session.id !== sessionId) return session;
            let stopped = stopStreaming(session);
            if (isPreparingHandoff(stopped)) stopped = completeHandoff(stopped, wrap?.text ?? buildDeterministicHandoff(stopped));
            return stopped;
          }));
          rt.finishTurn(sessionId, generation);
          await persistSession(sessionId).catch(() => undefined);
        }
      }
    })().catch((error: unknown) => {
      if (!isCurrent()) return;
      enqueueHarnessEvent(sessionId, { type: "session.error", message: String(error) });
      flushHarnessEvents();
      rt.finishTurn(sessionId, generation);
    });
    return true;
  }, [editedResends, enqueueHarnessEvent, flushHarnessEvents, persistSession, sessionsRef, setSessions]);
  submitRef.current = submitSession;

  const onSubmit = useCallback((...args: Parameters<Submit>): boolean => {
    const acceptance = submitSession(...args);
    if (typeof acceptance === "boolean") return acceptance;
    void acceptance.catch(() => undefined);
    return true;
  }, [submitSession]);

  const updateBtwThread = useCallback(
    (
      sessionId: string,
      userBlockId: string,
      threadId: string,
      update: (thread: BtwThread | undefined) => BtwThread | undefined,
    ): Session | undefined => {
      const previous = sessionsRef.current;
      let updatedSession: Session | undefined;
      const next = previous.map((session) => {
        if (session.id !== sessionId) return session;
        const blockIndex = session.blocks.findIndex(
          (block) => block.id === userBlockId && block.role === "user",
        );
        if (blockIndex < 0) return session;
        const block = session.blocks[blockIndex];
        const current = block.btwThreads?.find(
          (thread) => thread.id === threadId,
        );
        const nextThread = update(current);
        if (!nextThread) return session;
        const nextBlock = current
          ? replaceBtwThread(block, nextThread)
          : {
              ...block,
              btwThreads: [...(block.btwThreads ?? []), nextThread],
            };
        const blocks = session.blocks.slice();
        blocks[blockIndex] = nextBlock;
        updatedSession = { ...session, blocks };
        return updatedSession;
      });
      if (!updatedSession) return undefined;
      sessionsRef.current = next;
      setSessions(next);
      void persistSession(updatedSession).catch(() => undefined);
      return updatedSession;
    },
    [persistSession],
  );

  const removeBtwThread = useCallback(
    (
      sessionId: string,
      userBlockId: string,
      threadId: string,
    ): Session | undefined => {
      const previous = sessionsRef.current;
      let updatedSession: Session | undefined;
      const next = previous.map((session) => {
        if (session.id !== sessionId) return session;
        const blockIndex = session.blocks.findIndex(
          (block) => block.id === userBlockId && block.role === "user",
        );
        if (blockIndex < 0) return session;
        const block = session.blocks[blockIndex];
        const threads = block.btwThreads ?? [];
        if (!threads.some((thread) => thread.id === threadId)) return session;
        const nextThreads = threads.filter((thread) => thread.id !== threadId);
        const nextBlock = {
          ...block,
          btwThreads: nextThreads.length > 0 ? nextThreads : undefined,
        };
        const blocks = session.blocks.slice();
        blocks[blockIndex] = nextBlock;
        updatedSession = { ...session, blocks };
        return updatedSession;
      });
      if (!updatedSession) return undefined;
      sessionsRef.current = next;
      setSessions(next);
      void persistSession(updatedSession).catch(() => undefined);
      return updatedSession;
    },
    [persistSession],
  );

  const runBtwRequest = useCallback(
    (input: {
      sessionId: string;
      userBlockId: string;
      source: Session;
      thread: BtwThread;
      harness: HarnessId;
    }) => {
      const harness = input.harness;
      if (!supportsBtwHarness(harness)) return;
      const cwd = sessionWorkCwd(input.source);
      const model = nativeModelId(
        input.thread.model ?? input.source.model,
      ).trim();
      if (!cwd || cwd === "~") {
        updateBtwThread(
          input.sessionId,
          input.userBlockId,
          input.thread.id,
          (thread) =>
            thread
              ? {
                  ...thread,
                  status: "error",
                  updatedAt: Date.now(),
                  error:
                    "A project working directory is required for this question.",
                }
              : undefined,
        );
        return;
      }
      if (!model && harness === "codex") {
        updateBtwThread(
          input.sessionId,
          input.userBlockId,
          input.thread.id,
          (thread) =>
            thread
              ? {
                  ...thread,
                  status: "error",
                  updatedAt: Date.now(),
                  error: "The selected Codex model is unavailable.",
                }
              : undefined,
        );
        return;
      }

      let prompt: string;
      try {
        prompt = buildBtwPrompt({
          blocks: input.source.blocks,
          thread: input.thread,
          cwd,
        });
      } catch (error) {
        updateBtwThread(
          input.sessionId,
          input.userBlockId,
          input.thread.id,
          (thread) =>
            thread
              ? {
                  ...thread,
                  status: "error",
                  updatedAt: Date.now(),
                  error:
                    error instanceof Error
                      ? error.message
                      : "The completed turn is no longer available.",
                }
              : undefined,
        );
        return;
      }

      const key = `${input.sessionId}:${input.thread.id}`;
      btwRequestsRef.current.get(key)?.controller.abort();
      const controller = new AbortController();
      btwRequestsRef.current.set(key, {
        sessionId: input.sessionId,
        controller,
      });

      const userMessageId =
        input.thread.messages[input.thread.messages.length - 1]?.id ??
        input.thread.id;
      const responseModel = model || input.source.model;

      void runHarnessTextPrompt({
        harness,
        cwd,
        providerAccountId: input.source.providerAccountId,
        model: model || undefined,
        modelSettings: input.thread.modelSettings ?? input.source.modelSettings,
        threadId: input.thread.providerThreadId,
        onThreadId: (providerThreadId) => {
          if (controller.signal.aborted) return;
          updateBtwThread(
            input.sessionId,
            input.userBlockId,
            input.thread.id,
            (thread) =>
              thread && thread.providerThreadId !== providerThreadId
                ? {
                    ...thread,
                    providerThreadId,
                    updatedAt: Date.now(),
                  }
                : thread,
          );
        },
        onEvent: (event) => {
          if (controller.signal.aborted) return;
          updateBtwThread(
            input.sessionId,
            input.userBlockId,
            input.thread.id,
            (thread) =>
              thread?.status === "running"
                ? {
                    ...thread,
                    updatedAt: Date.now(),
                    pendingBlocks: applyBtwHarnessEvent(
                      thread.pendingBlocks ?? [],
                      event,
                      harness,
                      responseModel,
                      userMessageId,
                    ),
                  }
                : undefined,
          );
        },
        intent: "plan",
        prompt,
        signal: controller.signal,
      })
        .then((output) => {
          if (controller.signal.aborted) return;
          const text = output.trim();
          if (!text) {
            throw new Error(
              `${HARNESS_TITLE[harness]} returned an empty side answer.`,
            );
          }
          updateBtwThread(
            input.sessionId,
            input.userBlockId,
            input.thread.id,
            (thread) => {
              if (!thread) return undefined;
              const pendingBlocks = thread.pendingBlocks ?? [];
              const blocks =
                pendingBlocks.length > 0
                  ? sealBtwResponseBlocks(
                      pendingBlocks,
                      harness,
                      responseModel,
                      userMessageId,
                    )
                  : undefined;
              return {
                ...thread,
                status: "ready",
                updatedAt: Date.now(),
                pendingBlocks: undefined,
                messages: [
                  ...thread.messages,
                  {
                    id: crypto.randomUUID(),
                    role: "assistant",
                    text,
                    createdAt: Date.now(),
                    ...(blocks?.length ? { blocks } : {}),
                  },
                ],
                error: undefined,
              };
            },
          );
        })
        .catch((error: unknown) => {
          if (controller.signal.aborted) return;
          const message =
            error instanceof Error
              ? error.message
              : `${HARNESS_TITLE[harness]} could not answer this side question.`;
          updateBtwThread(
            input.sessionId,
            input.userBlockId,
            input.thread.id,
            (thread) =>
              thread
                ? {
                    ...thread,
                    status: "error",
                    updatedAt: Date.now(),
                    pendingBlocks: undefined,
                    error: message,
                  }
                : undefined,
          );
        })
        .finally(() => {
          if (btwRequestsRef.current.get(key)?.controller === controller) {
            btwRequestsRef.current.delete(key);
          }
        });
    },
    [updateBtwThread],
  );

  const onBtwSubmit = useCallback(
    (
      sessionId: string,
      turn: Block[],
      threadId: string,
      messageId: string,
      text: string,
      model?: string,
      modelSettings?: Record<string, string>,
    ) => {
      const source = sessionsRef.current.find(
        (session) => session.id === sessionId,
      );
      const sourceUserId = turn.find((block) => block.role === "user")?.id;
      const sourceEndBlockId = turn[turn.length - 1]?.id;
      const turnHarness = source
        ? harnessForTurn(source.blocks, turn, source.harness)
        : undefined;
      const turnModel = turn.find((block) => block.role === "user")?.turnModel
        ?.id;
      const sourceBlockEarly = source?.blocks.find(
        (block) => block.id === sourceUserId && block.role === "user",
      );
      const existingEarly = sourceBlockEarly?.btwThreads?.find(
        (thread) => thread.id === threadId,
      );
      const requestHarness = source
        ? supportsBtwHarness(turnHarness)
          ? turnHarness
          : (existingEarly?.harness ??
            btwTurnHarness(source.blocks, turn, source.harness))
        : undefined;
      if (
        !source ||
        !supportsBtwHarness(requestHarness) ||
        !sourceUserId ||
        !sourceEndBlockId
      ) {
        return false;
      }
      const sourceBlock = sourceBlockEarly;
      if (!sourceBlock) return false;
      const existing = existingEarly;
      const selectedModel =
        model?.trim() ||
        existing?.model ||
        turnModel ||
        nativeModelId(source.model).trim();
      const selectedModelSettings =
        modelSettings ??
        existing?.modelSettings ??
        preferredModelSettings(
          resolveModel(requestHarness!, selectedModel || source.model),
          source.modelSettings,
        );
      if (existing?.status === "running") return false;
      if (existing && existing.sourceEndBlockId !== sourceEndBlockId) {
        return false;
      }
      const now = Date.now();
      const thread: BtwThread = existing
        ? {
            ...existing,
            harness: existing.harness ?? turnHarness,
            model: selectedModel || undefined,
            modelSettings: selectedModelSettings,
            status: "running",
            updatedAt: now,
            error: undefined,
            pendingBlocks: [],
            messages: [
              ...existing.messages,
              { id: messageId, role: "user", text, createdAt: now },
            ],
          }
        : {
            id: threadId,
            sourceEndBlockId,
            createdAt: now,
            updatedAt: now,
            status: "running",
            pendingBlocks: [],
            harness: requestHarness,
            ...(selectedModel ? { model: selectedModel } : {}),
            modelSettings: selectedModelSettings,
            messages: [{ id: messageId, role: "user", text, createdAt: now }],
          };
      const updated = updateBtwThread(
        sessionId,
        sourceUserId,
        threadId,
        () => thread,
      );
      if (!updated) return false;
      runBtwRequest({
        sessionId,
        userBlockId: sourceUserId,
        source,
        thread,
        harness: thread.harness ?? requestHarness!,
      });
      return true;
    },
    [runBtwRequest, updateBtwThread],
  );

  const onBtwModelChange = useCallback(
    (
      sessionId: string,
      turn: Block[],
      threadId: string,
      model: string,
      modelSettings: Record<string, string>,
    ) => {
      const source = sessionsRef.current.find(
        (session) => session.id === sessionId,
      );
      const sourceUserId = turn.find((block) => block.role === "user")?.id;
      const turnHarness = source
        ? harnessForTurn(source.blocks, turn, source.harness)
        : undefined;
      const nextModel = model.trim();
      const sourceBlock = source?.blocks.find(
        (block) => block.id === sourceUserId && block.role === "user",
      );
      const threadHarness = source
        ? (sourceBlock?.btwThreads?.find((thread) => thread.id === threadId)
            ?.harness ??
          btwTurnHarness(source.blocks, turn, source.harness) ??
          turnHarness)
        : undefined;
      if (
        !source ||
        !supportsBtwHarness(threadHarness) ||
        !sourceUserId ||
        !nextModel
      ) {
        return;
      }
      updateBtwThread(sessionId, sourceUserId, threadId, (thread) =>
        thread
          ? {
              ...thread,
              model: nextModel,
              modelSettings,
              updatedAt: Date.now(),
            }
          : undefined,
      );
    },
    [updateBtwThread],
  );

  const onBtwDelete = useCallback(
    (sessionId: string, turn: Block[], threadId: string) => {
      const source = sessionsRef.current.find(
        (session) => session.id === sessionId,
      );
      const sourceUserId = turn.find((block) => block.role === "user")?.id;
      const turnHarness = source
        ? harnessForTurn(source.blocks, turn, source.harness)
        : undefined;
      const sourceBlock = source?.blocks.find(
        (block) => block.id === sourceUserId && block.role === "user",
      );
      const threadHarness = source
        ? (sourceBlock?.btwThreads?.find((thread) => thread.id === threadId)
            ?.harness ??
          btwTurnHarness(source.blocks, turn, source.harness) ??
          turnHarness)
        : undefined;
      if (
        !source ||
        !supportsBtwHarness(threadHarness) ||
        !sourceUserId
      ) {
        return;
      }
      const requestKey = `${sessionId}:${threadId}`;
      btwRequestsRef.current.get(requestKey)?.controller.abort();
      btwRequestsRef.current.delete(requestKey);
      removeBtwThread(sessionId, sourceUserId, threadId);
    },
    [removeBtwThread],
  );

  // Stopping keeps whatever the side answer had streamed, like stopping a
  // main turn, and leaves the thread ready for the next question.
  const onBtwStop = useCallback(
    (sessionId: string, turn: Block[], threadId: string) => {
      const sourceUserId = turn.find((block) => block.role === "user")?.id;
      if (!sourceUserId) return;
      const key = `${sessionId}:${threadId}`;
      btwRequestsRef.current.get(key)?.controller.abort();
      btwRequestsRef.current.delete(key);
      updateBtwThread(sessionId, sourceUserId, threadId, (thread) => {
        if (!thread || thread.status !== "running") return thread;
        const harness = thread.harness;
        const userMessageId =
          thread.messages[thread.messages.length - 1]?.id ?? thread.id;
        const pending = thread.pendingBlocks ?? [];
        const blocks =
          pending.length > 0 && harness
            ? sealBtwResponseBlocks(
                pending,
                harness,
                thread.model ?? "",
                userMessageId,
              )
            : [];
        const text = blocks
          .filter((block) => block.role === "assistant")
          .map((block) => block.text)
          .join("\n\n")
          .trim();
        const now = Date.now();
        return {
          ...thread,
          status: "ready",
          updatedAt: now,
          pendingBlocks: undefined,
          error: undefined,
          messages: blocks.length
            ? [
                ...thread.messages,
                {
                  id: crypto.randomUUID(),
                  role: "assistant",
                  text,
                  createdAt: now,
                  blocks,
                },
              ]
            : thread.messages,
        };
      });
    },
    [updateBtwThread],
  );

  const onBtwRetry = useCallback(
    (sessionId: string, turn: Block[], threadId: string) => {
      const source = sessionsRef.current.find(
        (session) => session.id === sessionId,
      );
      const sourceUserId = turn.find((block) => block.role === "user")?.id;
      const turnHarness = source
        ? harnessForTurn(source.blocks, turn, source.harness)
        : undefined;
      const sourceBlock = source?.blocks.find(
        (block) => block.id === sourceUserId && block.role === "user",
      );
      const existing = sourceBlock?.btwThreads?.find(
        (thread) => thread.id === threadId,
      );
      const threadHarness = source
        ? (existing?.harness ??
          btwTurnHarness(source.blocks, turn, source.harness) ??
          turnHarness)
        : undefined;
      if (
        !source ||
        !supportsBtwHarness(threadHarness) ||
        !sourceUserId
      ) {
        return;
      }
      if (!sourceBlock || !existing || existing.status !== "error") return;
      const thread: BtwThread = {
        ...existing,
        status: "running",
        updatedAt: Date.now(),
        error: undefined,
        pendingBlocks: [],
      };
      const updated = updateBtwThread(
        sessionId,
        sourceUserId,
        threadId,
        () => thread,
      );
      if (!updated) return;
      runBtwRequest({
        sessionId,
        userBlockId: sourceUserId,
        source: updated,
        thread,
        harness: thread.harness ?? threadHarness!,
      });
    },
    [runBtwRequest, updateBtwThread],
  );


  const changeModel = useCallback((sessionId: string, harness: HarnessId, model: string) => {
    const current = sessionsRef.current.find((session) => session.id === sessionId);
    if (!current || isPreparingHandoff(current)) return;
    const resolved = resolveModel(harness, model);
    saveRecentModelChoice(resolved.harness, resolved.id);
    saveLastModelSettings(current.modelSettings, "fill");
    const settings = preferredModelSettings(resolved, current.modelSettings);
    const plan = planComposerSwitch(current, harness);
    if (plan.kind === "empty") void forgetHarnessSession(plan.forget, sessionId);
    setSessions((previous) => previous.map((session) => {
      if (session.id !== sessionId) return session;
      const next = withHarnessChoice(session, harness, resolved.id, settings);
      if (plan.kind === "arm") return { ...next, pendingSwitch: plan.pending };
      if (plan.kind === "revert") return { ...next, pendingSwitch: undefined,
        providerSessionId: plan.restoreProviderSessionId, providerAccountId: plan.restoreProviderAccountId };
      if (plan.kind === "empty") return { ...next, pendingSwitch: undefined };
      return next;
    }));
  }, [sessionsRef, setSessions]);

  const changeModelSettings = useCallback((sessionId: string, modelSettings: Record<string, string>) => {
    saveLastModelSettings(modelSettings);
    setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, modelSettings } : session));
  }, [setSessions]);
  const changeRuntimeMode = useCallback((sessionId: string, runtimeMode: RuntimeMode) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, runtimeMode } : session));
  }, [setSessions]);

  const saveDraft = useCallback((sessionId: string, text: string, attachments: Attachment[] = [], appRequestId?: string) => {
    const current = sessionsRef.current.find((session) => session.id === sessionId);
    if (!current || current.busy || sessionDraftBlock(current) || (!text.trim() && !attachments.length)) return false;
    const title = canReplaceSessionTitle(current.title, current.harness, HARNESS_LABEL[current.harness])
      ? titleFromPrompt(text, current.harness, attachments) : current.title;
    setSessions((previous) => previous.map((session) => session.id === sessionId ? {
      ...session, title, blocks: [...session.blocks, {
        id: crypto.randomUUID(), role: "user", text, draft: true,
        ...(attachments.length ? { attachments } : {}), ...(appRequestId ? { appRequestId } : {}),
      }],
    } : session));
    void persistSession(sessionId).catch(() => undefined);
    return true;
  }, [persistSession, sessionsRef, setSessions]);

  const removeDraft = useCallback((sessionId: string, draftBlockId: string) => {
    const current = sessionsRef.current.find((session) => session.id === sessionId);
    const next = current ? removeSessionDraft(current, draftBlockId) : undefined;
    if (!next) return false;
    setSessions((previous) => previous.map((session) => session.id === sessionId ? next : session));
    if (!shouldPersistSession(next)) {
      optionsRef.current.onDraftDiscarded?.(sessionId);
      void discardDraftSessionRecord(sessionId).catch(() => undefined);
    }
    return true;
  }, [sessionsRef, setSessions]);

  const stop = useCallback(async (sessionId: string) => {
    const rt = runtimeRef.current;
    rt.forgetTurn(sessionId);
    flushHarnessEvents();
    const current = sessionsRef.current.find((session) => session.id === sessionId);
    const cancellation = current ? Promise.all(sessionChildHarnesses(current).map((harness) =>
      cancelHarnessTurn(harness, sessionId).catch(() => undefined))) : Promise.resolve([]);
    setSessions((previous) => previous.map((session) => {
      if (session.id !== sessionId) return session;
      const stopped = stopStreaming(session);
      const ready = isPreparingHandoff(stopped)
        ? completeHandoff(stopped, buildDeterministicHandoff(stopped)) : stopped;
      return ready.queuedMessages?.length ? { ...ready, queueStatus: "paused" } : ready;
    }));
    await cancellation;
    await persistSession(sessionId);
  }, [flushHarnessEvents, persistSession, sessionsRef, setSessions]);

  const approve = useCallback((sessionId: string, requestId: number, decision: ApprovalDecision) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (session) respondHarnessApproval(session.harness, sessionId, requestId, decision);
  }, [sessionsRef]);
  const answer = useCallback((sessionId: string, requestId: number, reply: UserQuestionReply) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (session) respondHarnessQuestion(session.harness, sessionId, requestId, reply);
  }, [sessionsRef]);
  const keepQuestionOpen = useCallback((sessionId: string, requestId: number) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (session) keepHarnessQuestionOpen(session.harness, sessionId, requestId);
  }, [sessionsRef]);

  const compact = useCallback((sessionId: string) => {
    const current = sessionsRef.current.find((session) => session.id === sessionId);
    if (!current || current.busy || !canCompactHarnessContext(current.harness)) return false;
    const rt = runtimeRef.current;
    const generation = rt.beginTurn(sessionId);
    setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, busy: true } : session));
    enqueueHarnessEvent(sessionId, { type: "status", text: "Compacting context…" });
    void (async () => {
      try {
        await compactHarnessContext({ harness: current.harness, sessionId, cwd: current.cwd,
          model: current.model, modelSettings: current.modelSettings,
          providerAccountId: current.providerAccountId ?? selectedProviderAccountId(current.harness, current.cwd),
          runtimeMode: current.runtimeMode,
          onEvent: (event) => { if (rt.isCurrentTurn(sessionId, generation)) enqueueHarnessEvent(sessionId, event); } });
        if (rt.isCurrentTurn(sessionId, generation)) enqueueHarnessEvent(sessionId, { type: "status", text: "Compacted context" });
      } catch (error) {
        if (rt.isCurrentTurn(sessionId, generation)) enqueueHarnessEvent(sessionId, { type: "session.error", message: String(error) });
      } finally {
        if (rt.isCurrentTurn(sessionId, generation)) {
          flushHarnessEvents();
          setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, busy: false } : session));
          rt.finishTurn(sessionId, generation);
          void persistSession(sessionId).catch(() => undefined);
        }
      }
    })();
    return true;
  }, [enqueueHarnessEvent, flushHarnessEvents, persistSession, sessionsRef, setSessions]);

  const deleteQueuedMessage = useCallback((sessionId: string, messageId: string) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId ? dequeueQueuedMessage(session, messageId) : session));
  }, [setSessions]);
  const queuedMessageEditingChange = useCallback((sessionId: string, messageId?: string) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, editingQueuedMessageId: messageId } : session));
  }, [setSessions]);
  const editQueuedMessage = useCallback((sessionId: string, messageId: string, text: string) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId ? {
      ...session, editingQueuedMessageId: undefined,
      queuedMessages: session.queuedMessages?.map((message) => message.id === messageId ? { ...message, text } : message),
    } : session));
  }, [setSessions]);
  const steerQueuedMessage = useCallback((sessionId: string, messageId: string) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    const message = session ? queuedMessageForSubmit(session, messageId, "steer") : undefined;
    if (message) onSubmit(sessionId, message.text, message.attachments, {
      followUpBehavior: "steer", queuedMessageId: message.id, noteCard: message.noteCard,
    });
  }, [onSubmit, sessionsRef]);
  const resumeQueue = useCallback((sessionId: string) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (!session || session.busy || session.queueStatus !== "paused" || !session.queuedMessages?.length) return;
    setSessions((previous) => previous.map((entry) => entry.id === sessionId ? { ...entry, queueStatus: "resuming" } : entry));
    onSubmit(sessionId, CONTINUE_PROMPT, [], { followUpBehavior: "steer" });
  }, [onSubmit, sessionsRef, setSessions]);

  useEffect(() => {
    const timers: ReturnType<typeof setTimeout>[] = [];
    const scheduledIds = new Set<string>();
    for (const session of sessions) {
      if (!canDispatchQueuedHead(session) || queueDispatchingRef.current.has(session.id) || runtimeRef.current.hasActiveTurn(session.id)) continue;
      const head = session.queuedMessages?.[0];
      if (!head) continue;
      queueDispatchingRef.current.add(session.id);
      scheduledIds.add(session.id);
      timers.push(setTimeout(() => {
        queueDispatchingRef.current.delete(session.id);
        const current = sessionsRef.current.find((entry) => entry.id === session.id);
        if (!current || current.queuedMessages?.[0]?.id !== head.id || !canDispatchQueuedHead(current)) return;
        onSubmit(session.id, head.text, head.attachments, { queuedMessageId: head.id, noteCard: head.noteCard });
      }, 0));
    }
    return () => {
      timers.forEach(clearTimeout);
      for (const id of scheduledIds) queueDispatchingRef.current.delete(id);
    };
  }, [onSubmit, sessions, sessionsRef]);

  const usageLimitDismiss = useCallback((sessionId: string) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId ? { ...session, usageLimit: undefined } : session));
  }, [setSessions]);
  const usageLimitResumeAtReset = useCallback((sessionId: string, enabled: boolean) => {
    setSessions((previous) => previous.map((session) => session.id === sessionId && session.usageLimit ? {
      ...session, usageLimit: { ...session.usageLimit, resumeAtReset: enabled },
    } : session));
  }, [setSessions]);
  const usageLimitResume = useCallback((sessionId: string) => {
    const session = sessionsRef.current.find((entry) => entry.id === sessionId);
    if (!session?.usageLimit || session.busy) return;
    usageLimitDismiss(sessionId);
    onSubmit(sessionId, CONTINUE_PROMPT);
  }, [onSubmit, sessionsRef, usageLimitDismiss]);
  const [usageLimitTick, setUsageLimitTick] = useState(0);
  useEffect(() => {
    const now = Date.now();
    const timers: ReturnType<typeof setTimeout>[] = [];
    const scheduledIds = new Set<string>();
    let nextCheck = Number.POSITIVE_INFINITY;
    for (const session of sessions) {
      const limit = session.usageLimit;
      if (!limit?.resumeAtReset || limit.resetsAt == null) continue;
      if (!usageLimitResumeDue(session, now)) {
        nextCheck = Math.min(nextCheck, limit.resetsAt + USAGE_LIMIT_RESUME_GRACE_MS - now);
        continue;
      }
      if (usageResumingRef.current.has(session.id)) continue;
      usageResumingRef.current.add(session.id);
      scheduledIds.add(session.id);
      timers.push(setTimeout(() => {
        usageResumingRef.current.delete(session.id);
        const latest = sessionsRef.current.find((entry) => entry.id === session.id);
        if (latest && usageLimitResumeDue(latest, Date.now())) usageLimitResume(session.id);
      }, 0));
    }
    if (Number.isFinite(nextCheck)) timers.push(setTimeout(() => setUsageLimitTick((tick) => tick + 1), Math.max(1000, Math.min(nextCheck, 60_000))));
    return () => {
      timers.forEach(clearTimeout);
      for (const id of scheduledIds) usageResumingRef.current.delete(id);
    };
  }, [sessions, sessionsRef, usageLimitResume, usageLimitTick]);

  const autoContinueKey = sessions.filter((session) => canAutoContinue(session) && isLiveHarness(session.harness)).map((session) => session.id).join("\n");
  useEffect(() => {
    if (!autoContinueKey) return;
    const timer = setTimeout(() => {
      for (const id of autoContinueKey.split("\n")) {
        const session = sessionsRef.current.find((entry) => entry.id === id);
        if (session && canAutoContinue(session) && !runtimeRef.current.hasActiveTurn(id)) {
          runtimeRef.current.bindRestoredSession(session);
          onSubmit(id, CONTINUE_PROMPT);
        }
      }
    }, 0);
    return () => clearTimeout(timer);
  }, [autoContinueKey, onSubmit, sessionsRef]);

  useEffect(() => () => {
    for (const request of btwRequestsRef.current.values()) request.controller.abort();
    btwRequestsRef.current.clear();
  }, []);

  return {
    submit: submitSession, onSubmit, stop, approve, answer, keepQuestionOpen,
    compact, saveDraft, removeDraft, changeModel, changeModelSettings, changeRuntimeMode,
    deleteQueuedMessage, queuedMessageEditingChange, editQueuedMessage, steerQueuedMessage, resumeQueue,
    usageLimitDismiss, usageLimitResume, usageLimitResumeAtReset,
    btwSubmit: onBtwSubmit, btwRetry: onBtwRetry, btwStop: onBtwStop,
    btwDelete: onBtwDelete, btwModelChange: onBtwModelChange,
  };
}

export type SessionSubmission = ReturnType<typeof useSessionSubmission>;
