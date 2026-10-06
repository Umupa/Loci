import {
memo,
useCallback,
useEffect,
useRef,
useState,
useSyncExternalStore,
type CSSProperties,
type PointerEvent as ReactPointerEvent,
} from "react";
import { ChevronDown,GripVertical,X } from "../../../shared/ui/icons";
import { Composer } from "./Composer";




import {
canCompactHarnessContext,
type ApprovalDecision,
type UserQuestionReply,
} from "../../../integrations/harness";
import { MOD } from "../../../platform/tauri/platform";
import { projectKey } from "../../../shared/lib/paths";
import { createNote,noteTitle } from "../../notes";
import {
loadProjectChatBackgroundSettings,
projectChatBackgroundImageRevision,
projectChatBackgroundRevision,
subscribeProjectChatBackground,
} from "../../projects/model/projectChatBackground";
import {
looksLikeProject,
type RecentProject,
} from "../../projects/model/recents";
import { useProjectBackgroundEffect } from "../../projects/ui/useProjectBackgroundEffect";
import {
loadChatBackgroundPath,
loadNewThreadBackgroundEffect,
subscribeChatBackgroundPath,
} from "../../settings/model/appearance";
import {
loadNotesEnabled,
subscribeNotesEnabled,
} from "../../settings/model/settings";
import { GradientBlurBackground } from "../../settings/ui/GradientBlurBackground";
import { isAstraModel } from "../model/astraWelcome";
import { sessionHasBtwThreads,supportsBtwHarness } from "../model/btw";
import { getComposerDraft,setComposerDraft } from "../model/draftCache";
import { canEditLastTurn,lastTurnRecall } from "../model/editLastTurn";
import { resolveModel } from "../model/models";
import { isOpus55Model } from "../model/opusWelcome";
import {
acknowledgeQuoteRequest,
ADD_TO_CHAT_EVENT,
type AddToChatRequest,
type QuoteRequest,
} from "../model/quoteDraft";
import { sessionDisplayTitle,sessionDraftBlock,sessionWorkCwd,type Attachment,type Block,type ComposerTurnOptions,type HarnessId,type RuntimeMode,type Session } from "../model/session";
import type { SessionFolderTarget } from "../model/sessionFolders";
import {
clearTranscriptJump,
peekTranscriptJump,
subscribeTranscriptJump,
} from "../model/transcriptJump";
import { AgentTranscript } from "./AgentTranscript";
import { AstraWelcome } from "./AstraWelcome";
import { BtwSheet,useBtwConversation } from "./BtwSheet";
import { EmptySession } from "./EmptySession";
import { OpusWelcome } from "./OpusWelcome";
import { PromptOutline } from "./PromptOutline";
import { TranscriptFind } from "./TranscriptFind";
import { PooledTranscript,type TranscriptPool } from "./TranscriptPool";
import { useComposerDockMotion } from "./useComposerDockMotion";




export type SessionPaneProps = {
  session: Session;


  visible: boolean;
  focused: boolean;
  addToChatTarget?: boolean;
  inSplit: boolean;
  composerFocused: boolean;
  composerFocusToken?: number;
  recents: RecentProject[];
  hideProjectPicker?: boolean;
  onFocus: (sessionId: string) => void;
  onClose: (sessionId: string) => void;
  onCwdChange: (sessionId: string, cwd: string) => void;






  onModelChange: (sessionId: string, harness: HarnessId, model: string) => void;
  onModelSettingsChange: (
    sessionId: string,
    settings: Record<string, string>,
  ) => void;
  onRuntimeModeChange: (sessionId: string, mode: RuntimeMode) => void;
  onSubmit: (
    sessionId: string,
    text: string,
    attachments: Attachment[],
    options?: ComposerTurnOptions,
  ) => boolean | void;
  onSaveDraft: (
    sessionId: string,
    text: string,
    attachments: Attachment[],
  ) => boolean | void;
  onRemoveDraft: (sessionId: string, draftBlockId: string) => boolean | void;
  onStop: (sessionId: string) => void;
  onCompactContext: (sessionId: string) => boolean;
  onPlaceSessionInFolder: (
    sessionId: string,
    target: SessionFolderTarget,
  ) => void;
  onDeleteQueuedMessage: (sessionId: string, messageId: string) => void;
  onEditQueuedMessage: (
    sessionId: string,
    messageId: string,
    text: string,
  ) => void;
  onQueuedMessageEditingChange: (sessionId: string, messageId?: string) => void;
  onSteerQueuedMessage: (sessionId: string, messageId: string) => void;
  onResumeQueue: (sessionId: string) => void;
  onUsageLimitResume: (sessionId: string) => void;
  onUsageLimitResumeAtReset: (sessionId: string, enabled: boolean) => void;
  onUsageLimitDismiss: (sessionId: string) => void;


  onNoteCardDismiss?: (sessionId: string) => void;
  onSaveToCanvas?: (text: string) => void | Promise<void>;


  onApproval: (
    sessionId: string,
    requestId: number,
    decision: ApprovalDecision,
  ) => void;
  onQuestionReply: (
    sessionId: string,
    requestId: number,
    reply: UserQuestionReply,
  ) => void;
  onQuestionInteraction?: (sessionId: string, requestId: number) => void;
  onOpenFile: (path: string) => void;





  onBtwSubmit?: (
    sessionId: string,
    turn: Block[],
    threadId: string,
    messageId: string,
    text: string,
    model?: string,
    modelSettings?: Record<string, string>,
  ) => boolean | void;
  onBtwRetry?: (sessionId: string, turn: Block[], threadId: string) => void;
  onBtwDelete?: (sessionId: string, turn: Block[], threadId: string) => void;
  onBtwStop?: (sessionId: string, turn: Block[], threadId: string) => void;
  onBtwModelChange?: (
    sessionId: string,
    turn: Block[],
    threadId: string,
    model: string,
    modelSettings: Record<string, string>,
  ) => void;


  onPaneDragStart?: (event: ReactPointerEvent<HTMLElement>) => void;
  /** Keeps this transcript mounted after the pane closes. */
  transcriptPool?: TranscriptPool;
};

type Props = SessionPaneProps & {
  /** The session runtime is on another machine. */


  /** An opened host conversation whose transcript has not arrived yet. */


  allowedModelHarnesses?: readonly HarnessId[];
};



export const SessionPane = memo(function SessionPane({




  allowedModelHarnesses,
  session,


  visible,
  focused,
  addToChatTarget = focused,
  inSplit,
  composerFocused,
  composerFocusToken,
  recents,
  hideProjectPicker,
  onFocus,
  onClose,
  onCwdChange,





  onModelChange,
  onModelSettingsChange,
  onRuntimeModeChange,
  onSaveDraft,
  onRemoveDraft,
  onSubmit,
  onStop,
  onCompactContext,
  onPlaceSessionInFolder,
  onDeleteQueuedMessage,
  onEditQueuedMessage,
  onQueuedMessageEditingChange,
  onSteerQueuedMessage,
  onResumeQueue,
  onUsageLimitResume,
  onUsageLimitResumeAtReset,
  onUsageLimitDismiss,


  onNoteCardDismiss,
  onSaveToCanvas,

  onApproval,
  onQuestionReply,
  onQuestionInteraction,
  onOpenFile,





  onBtwSubmit,
  onBtwRetry,
  onBtwDelete,
  onBtwStop,
  onBtwModelChange,

  onPaneDragStart,
  transcriptPool,
}: Props) {


  const title = sessionDisplayTitle(session.title, session.harness);
  const isEmpty = session.blocks.length === 0;
  const recallLastTurnRef = useRef<(() => void) | null>(null);

  const editLastTurnSupported = canEditLastTurn(session);
  const turnRecall = editLastTurnSupported ? lastTurnRecall(session) : null;
  const draftBlock = sessionDraftBlock(session);
  useSyncExternalStore(
    subscribeProjectChatBackground,
    projectChatBackgroundRevision,
    projectChatBackgroundRevision,
  );
  const globalBackgroundPath = useSyncExternalStore(
    subscribeChatBackgroundPath,
    loadChatBackgroundPath,
    loadChatBackgroundPath,
  );
  const globalBackgroundEffect = useSyncExternalStore(
    subscribeChatBackgroundPath,
    loadNewThreadBackgroundEffect,
    loadNewThreadBackgroundEffect,
  );
  const projectBackground = loadProjectChatBackgroundSettings(
    projectKey(session.cwd),
  );
  const projectBackgroundUrl = useProjectBackgroundEffect(
    projectBackground?.path ?? null,
    projectBackground?.effect ?? "none",
    projectChatBackgroundImageRevision(),
  );
  const projectBackgroundStyle = projectBackground
    ? ({
        "--chat-background-image": projectBackgroundUrl
          ? `url(${JSON.stringify(projectBackgroundUrl)})`
          : "none",
        "--chat-background-empty-opacity": String(
          projectBackground.emptyOpacity,
        ),
        "--chat-background-session-opacity": String(
          projectBackground.sessionOpacity,
        ),
      } as CSSProperties)
    : undefined;
  const approve = useCallback(
    (requestId: number, decision: ApprovalDecision) =>
      onApproval(session.id, requestId, decision),
    [onApproval, session.id],
  );
  const replyQuestion = useCallback(
    (requestId: number, reply: UserQuestionReply) =>
      onQuestionReply(session.id, requestId, reply),
    [onQuestionReply, session.id],
  );


  const jumpToBottomRef = useRef<(() => void) | null>(null);
  const transcriptScope = useRef<HTMLDivElement>(null);
  const [transcriptScroller, setTranscriptScroller] =
    useState<HTMLDivElement | null>(null);
  const focusPane = useCallback(
    () => onFocus(session.id),
    [onFocus, session.id],
  );
  const quoteRequestId = useRef(0);
  const [showJumpToBottom, setShowJumpToBottom] = useState(false);
  const [editingLastTurn, setEditingLastTurn] = useState(false);
  useEffect(() => {
    setEditingLastTurn(false);
  }, [session.id, editLastTurnSupported]);
  const modelWelcomeSequence = useRef(0);
  const [modelWelcome, setModelWelcome] = useState<{
    kind: "astra" | "opus";
    run: number;
  } | null>(null);
  const dismissModelWelcome = useCallback(() => setModelWelcome(null), []);
  useEffect(() => {
    if (!visible) setModelWelcome(null);
  }, [visible]);

  const [quoteRequest, setQuoteRequest] = useState<QuoteRequest>();
  const btw = useBtwConversation({
    available:
      !isEmpty &&
      !!onBtwSubmit &&
      !!onBtwRetry &&
      (supportsBtwHarness(session.harness) ||
        sessionHasBtwThreads(session.blocks)),
    blocks: session.blocks,
    harness: session.harness,

    model: session.model,
    modelSettings: session.modelSettings,
    onSubmit: (turn, threadId, messageId, text, model, modelSettings) =>
      onBtwSubmit?.(
        session.id,
        turn,
        threadId,
        messageId,
        text,
        model,
        modelSettings,
      ),
    onRetry: (turn, threadId) => onBtwRetry?.(session.id, turn, threadId),
    onDelete: (turn, threadId) => onBtwDelete?.(session.id, turn, threadId),
    onStop: (turn, threadId) => onBtwStop?.(session.id, turn, threadId),
    onModelChange: (turn, threadId, model, modelSettings) =>
      onBtwModelChange?.(session.id, turn, threadId, model, modelSettings),
  });
  const onJumpToBottomReady = useCallback((jump: () => void) => {
    jumpToBottomRef.current = jump;
  }, []);
  const revealBlockRef = useRef<((blockId: string) => boolean) | null>(null);
  const onRevealReady = useCallback((reveal: (blockId: string) => boolean) => {
    revealBlockRef.current = reveal;
  }, []);
  const revealBlock = useCallback(
    (blockId: string) => revealBlockRef.current?.(blockId) ?? false,
    [],
  );
  const navigateBlockRef = useRef<
    ((blockId: string | null, query?: string) => boolean) | null
  >(null);
  const [navigatorReady, setNavigatorReady] = useState(false);
  const onNavigateReady = useCallback(
    (navigate: (blockId: string | null, query?: string) => boolean) => {
      navigateBlockRef.current = navigate;
      setNavigatorReady(true);
    },
    [],
  );
  const navigateBlock = useCallback(
    (blockId: string | null, query?: string) =>
      navigateBlockRef.current?.(blockId, query) ?? false,
    [],
  );
  const jumpRequest = useSyncExternalStore(
    subscribeTranscriptJump,
    () => peekTranscriptJump(session.id),
    () => null,
  );
  useEffect(() => {
    if (!visible || !navigatorReady || !jumpRequest) return;
    const frame = requestAnimationFrame(() => {
      if (navigateBlock(jumpRequest.blockId, jumpRequest.query)) {
        clearTranscriptJump(session.id, jumpRequest.token);
      }
    });
    return () => cancelAnimationFrame(frame);
  }, [visible, navigatorReady, jumpRequest, navigateBlock, session.id]);
  const addSelectionToChat = useCallback(
    (text: string, mode?: QuoteRequest["mode"]) => {
      quoteRequestId.current += 1;
      setQuoteRequest({ id: quoteRequestId.current, text, mode });
    },
    [],
  );
  const acknowledgeQuote = useCallback((handledId: number) => {
    setQuoteRequest((current) => acknowledgeQuoteRequest(current, handledId));
  }, []);
  const notesEnabled = useSyncExternalStore(
    subscribeNotesEnabled,
    loadNotesEnabled,
    () => true,
  );
  const saveNote = useCallback(
    async (text: string) => {
      const sessionTitle = sessionDisplayTitle(session.title, session.harness);
      await createNote({
        title:
          sessionTitle && sessionTitle !== "New session"
            ? sessionTitle
            : noteTitle(text),
        body: text,
        sourceSessionId: session.id,
        sourceCwd: session.cwd,
      });
    },
    [session.cwd, session.harness, session.id, session.title],
  );
  const saveSelectionNote = useCallback(
    async (text: string) => {
      await createNote({
        title: noteTitle(text),
        body: text,
        sourceSessionId: session.id,
        sourceCwd: session.cwd,
      });
    },
    [session.cwd, session.id],
  );

  useEffect(() => {
    if (!addToChatTarget) return;
    const onAdd = (event: Event) => {
      const detail = (event as CustomEvent<AddToChatRequest>).detail;
      if (!detail?.text) return;
      addSelectionToChat(detail.text, detail.mode);
    };
    window.addEventListener(ADD_TO_CHAT_EVENT, onAdd);
    return () => window.removeEventListener(ADD_TO_CHAT_EVENT, onAdd);
  }, [addSelectionToChat, addToChatTarget]);
  const workCwd = sessionWorkCwd(session);
  const showDeckProjectPicker = isEmpty && !looksLikeProject(session.cwd);
  const dockComposer = !draftBlock && (!isEmpty || inSplit);
  const composerDockMotion = useComposerDockMotion(dockComposer);
  const draftRef = useRef<string | undefined>(getComposerDraft(session.id));
  const composer = (
    <Composer
      key={session.id}



      allowedModelHarnesses={allowedModelHarnesses}
      enabled={visible}
      focused={focused && composerFocused && !btw.open}
      focusToken={composerFocusToken}
      hotkeys={focused && !btw.open}
      shell={!dockComposer}
      harness={session.harness}
      model={session.model}
      modelSettings={session.modelSettings}
      runtimeMode={session.runtimeMode}
      cwd={session.cwd}
      executionCwd={workCwd}
      sessionId={session.id}
      compactSupported={canCompactHarnessContext(session.harness)}
      recents={recents}
      hideProjectPicker={
        (hideProjectPicker ? !showDeckProjectPicker : false)
      }


      context={session.context}
      quoteRequest={quoteRequest}
      initialDraft={
        draftRef.current ??
        (session.noteCard
          ? undefined
          : session.composerSeed)
      }
      onDraftChange={(text) => {
        draftRef.current = text;
        setComposerDraft(session.id, text);
      }}

      noteCard={session.noteCard}

      question={session.pendingQuestion}
      onQuoteRequestConsumed={acknowledgeQuote}

      onNoteCardDismiss={() => onNoteCardDismiss?.(session.id)}

      onQuestionReply={replyQuestion}
      onQuestionInteraction={(id) => onQuestionInteraction?.(session.id, id)}
      onFocus={() => onFocus(session.id)}
      onCwdChange={(cwd) => onCwdChange(session.id, cwd)}










      onModelChange={(harness, model) => {
        onModelChange(session.id, harness, model);
        const selected = resolveModel(harness, model);
        // A new key restarts the animation and its cleanup timer on every pick.
        const kind = isAstraModel(selected)
          ? "astra"
          : isOpus55Model(selected)
            ? "opus"
            : null;
        setModelWelcome(kind && { kind, run: ++modelWelcomeSequence.current });
      }}
      onModelSettingsChange={(settings) =>
        onModelSettingsChange(session.id, settings)
      }
      onRuntimeModeChange={(mode) => onRuntimeModeChange(session.id, mode)}
      canSaveDraft={!session.busy && !draftBlock && !session.noteCard}
      onSaveDraft={(text, attachments) =>
        onSaveDraft(session.id, text, attachments)
      }
      onSubmit={(text, attachments, options) => {
        if (!dockComposer) composerDockMotion.captureLaunch();
        return onSubmit(session.id, text, attachments, options);
      }}
      onBtwCommand={btw.openWith}
      onStop={() => onStop(session.id)}
      onCompactContext={() => onCompactContext(session.id)}
      onPlaceInFolder={(target) => onPlaceSessionInFolder(session.id, target)}
      queuedMessages={session.queuedMessages}
      queueStatus={session.queueStatus}
      onDeleteQueuedMessage={(messageId) =>
        onDeleteQueuedMessage(session.id, messageId)
      }
      onEditQueuedMessage={(messageId, text) =>
        onEditQueuedMessage(session.id, messageId, text)
      }
      onQueuedMessageEditingChange={(messageId) =>
        onQueuedMessageEditingChange(session.id, messageId)
      }
      onSteerQueuedMessage={(messageId) =>
        onSteerQueuedMessage(session.id, messageId)
      }
      onResumeQueue={() => onResumeQueue(session.id)}
      usageLimit={session.usageLimit}
      onUsageLimitResume={() => onUsageLimitResume(session.id)}
      onUsageLimitResumeAtReset={(enabled) =>
        onUsageLimitResumeAtReset(session.id, enabled)
      }
      onUsageLimitDismiss={() => onUsageLimitDismiss(session.id)}
      onOpenFile={onOpenFile}
      busy={!!session.busy}
      editLastTurnSupported={editLastTurnSupported}
      lastTurnRecall={turnRecall}
      onRecallLastTurnReady={(recall) => {
        recallLastTurnRef.current = recall;
      }}
      onEditingLastTurnChange={setEditingLastTurn}
    />
  );

  return (
    <div
      data-session-drop={session.id}
      data-session-empty={isEmpty}
      data-project-chat-background={!!projectBackground}
      data-project-background-effect={projectBackground?.effect}
      data-project-background-scope={projectBackground?.scope}
      style={projectBackgroundStyle}
      className="chat-pane-background relative isolate flex h-full min-h-0 min-w-0 flex-1 flex-col"
      onMouseDown={() => onFocus(session.id)}
    >
      {projectBackground?.effect === "gradient-blur" ||
      (!projectBackground &&
        globalBackgroundPath &&
        globalBackgroundEffect === "gradient-blur") ? (
        <GradientBlurBackground />
      ) : null}
      {modelWelcome && visible ? (
        modelWelcome.kind === "astra" ? (
          <AstraWelcome key={modelWelcome.run} onDone={dismissModelWelcome} />
        ) : (
          <OpusWelcome key={modelWelcome.run} onDone={dismissModelWelcome} />
        )
      ) : null}
      {inSplit ? (
        <div
          className={`flex h-9 shrink-0 touch-none items-center gap-1.5 border-b border-stroke px-2 select-none ${
            onPaneDragStart ? "cursor-grab active:cursor-grabbing" : ""
          }`}
          onPointerDown={(event) => {
            if (event.button !== 0 || !onPaneDragStart) return;
            if (
              (event.target as HTMLElement | null)?.closest("[data-no-drag]")
            ) {
              return;
            }
            onPaneDragStart(event);
          }}
        >
          {onPaneDragStart ? (
            <GripVertical
              className="size-3.5 shrink-0 text-content/35"
              strokeWidth={1.75}
            />
          ) : null}
          <span
            className={`size-2 shrink-0 rounded-full ${focused ? "bg-accent" : "bg-transparent"}`}
          />
          <span
            className="min-w-0 flex-1 truncate text-xs text-content"
            title={title}
          >
            {title}
          </span>
          <button
            type="button"
            title={`Close Pane (${MOD}W)`}
            aria-label="Close pane"
            data-no-drag
            className="grid size-5 shrink-0 place-items-center rounded text-content/50 hover:bg-content/10 hover:text-content"
            onPointerDown={(e) => e.stopPropagation()}
            onMouseDown={(e) => e.stopPropagation()}
            onClick={(e) => {
              e.stopPropagation();
              onClose(session.id);
            }}
          >
            <X className="size-3" strokeWidth={1.75} />
          </button>
        </div>
      ) : null}
      <div className="relative flex min-h-0 min-w-0 flex-1 flex-col">
        <div
          ref={transcriptScope}
          className={`@container relative min-h-0 flex-1${
            dockComposer ? " transcript-composer-fade" : ""
          }`}
        >

          {isEmpty ? (
            (
              <EmptySession
                cwd={session.cwd}

                composer={
                  dockComposer ? undefined : (
                    <div
                      ref={composerDockMotion.centeredRef}
                      data-session-composer
                    >
                      {composer}
                    </div>
                  )
                }
              />
            )
          ) : (
            <>
              <PooledTranscript
                pool={transcriptPool}
                sessionId={session.id}
                onMouseDown={focusPane}
              >
                <AgentTranscript
                  blocks={session.blocks}
                  busy={!!session.busy}
                  visible={visible}
                  cwd={workCwd}
                  harness={session.harness}
                  model={session.model}
                  modelSettings={session.modelSettings}
                  pendingQuestion={!!session.pendingQuestion}
                  backgroundTasks={session.backgroundTasks}
                  onApproval={approve}
                  onAddToChat={addSelectionToChat}
                  onSaveNote={notesEnabled ? saveNote : undefined}
                  onSaveToCanvas={onSaveToCanvas}
                  onSendDraft={
                    draftBlock
                      ? (block) =>
                          onSubmit(
                            session.id,
                            block.text,
                            block.attachments ?? [],
                            {
                              draftBlockId: block.id,
                              ...(block.appRequestId
                                ? { appRequestId: block.appRequestId }
                                : {}),
                            },
                          )
                      : undefined
                  }
                  onRemoveDraft={
                    draftBlock
                      ? (block) => onRemoveDraft(session.id, block.id)
                      : undefined
                  }
                  onSaveSelectionNote={
                    notesEnabled ? saveSelectionNote : undefined
                  }
                  onOpenFile={onOpenFile}






                  onJumpToBottomChange={setShowJumpToBottom}
                  onJumpToBottomReady={onJumpToBottomReady}
                  onRevealReady={onRevealReady}
                  onNavigateReady={onNavigateReady}
                  onScrollerChange={setTranscriptScroller}
                  editingLastTurn={editingLastTurn}
                  onEditLastTurn={
                    editLastTurnSupported
                      ? () => {
                          onFocus(session.id);
                          recallLastTurnRef.current?.();
                        }
                      : undefined
                  }

                />
              </PooledTranscript>
              {(
                <TranscriptFind
                  blocks={session.blocks}
                  visible={visible}
                  focused={focused}
                  onNavigate={navigateBlock}
                  side="right"
                />
              )}
              <PromptOutline
                blocks={session.blocks}
                scope={transcriptScope}
                scroller={transcriptScroller}
                visible={visible}
                revealBlock={revealBlock}
              />
              {showJumpToBottom ? (
                <div className="pointer-events-none absolute inset-x-0 bottom-2 z-30 flex justify-center">
                  <button
                    type="button"
                    title="Jump to latest"
                    aria-label="Jump to latest"
                    data-jump-to-bottom
                    onClick={() => jumpToBottomRef.current?.()}
                    className="pointer-events-auto grid size-6 place-items-center rounded-md border border-content/15 bg-content/10 text-content shadow-md hover:bg-content/5 backdrop-blur-md"
                  >
                    <ChevronDown className="size-4" strokeWidth={2} />
                  </button>
                </div>
              ) : null}
            </>
          )}
        </div>
        {dockComposer ? (
          <div
            ref={composerDockMotion.dockedRef}
            data-session-composer
            inert={btw.open}
            className="mx-auto w-full max-w-4xl shrink-0"
          >
            {composer}
          </div>
        ) : null}
        <BtwSheet
          btw={btw}
          cwd={workCwd}
          visible={visible}
          origin={() =>
            composerDockMotion.dockedRef.current?.querySelector<HTMLElement>(
              "[data-composer-box]",
            ) ?? null
          }
          onSaveNote={notesEnabled ? saveNote : undefined}
          onOpenFile={onOpenFile}

        />
      </div>
    </div>
  );
});
