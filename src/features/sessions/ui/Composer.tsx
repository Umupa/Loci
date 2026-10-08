import { getCurrentWebview } from "@tauri-apps/api/webview";
import {
useCallback,
useEffect,
useLayoutEffect,
useMemo,
useRef,
useState,
useSyncExternalStore,
type ClipboardEvent,
type KeyboardEvent,
type ReactNode,
} from "react";
import {
isFileReferenceText,
messageFilesFromClipboard,
nativeClipboardAttachments,
} from "../../../platform/tauri/clipboard";
import {
ArrowUp,
Check,
CircleDashed,
CornerDownRight,
CursorMagicSelection,
FilePlus,
ListEnd,
Pause,
Pencil,
Play,
Plus,
Square,
ExcalidrawIcon,
StickyNote,
Trash2,
X
} from "../../../shared/ui/icons";
import {
attachmentsFromFiles,
attachmentsFromPaths,
filesFromClipboard,
mergeAttachments,
pickAttachments,
revokeAttachment,
} from "../model/attachments";
import { resizeComposer } from "../model/composerResize";

import { dragPointToClient } from "../../../shared/lib/dragPoint";
import type { ContextUsage } from "../model/contextUsage";

import type { ProjectFile } from "../../../platform/tauri/fs";
import { CANVASES_CHANGED_EVENT, loadCanvases, peekCanvases, type Canvas } from "../../canvas/canvas";
import { loadProjectFiles } from "../../files/model/fileIndex";
import { buildMentionSources, mentionKind, projectCanvases, rankMentions } from "../model/mentionSources";
import {
fileMentionParts,
mentionLabel,
mentionTokenAt,
replaceMentionToken,
type MentionIndex,
type MentionToken
} from "../../notes/noteMentions";


import {
captureDraft,
dropPastedText,
insertRestoredText,
} from "../../../shared/lib/draftRestore";
import { isImeComposition } from "../../../shared/lib/keyboard";
import {
looksLikeProject,
type RecentProject,
} from "../../projects/model/recents";
import {
createBlankSkill,
hasNativeCommands,
rankSkills,
replaceSlashToken,
skillTextParts,
slashTokenAt,
type Skill,
type SlashToken
} from "../../skills/model/skills";
import type { Attachment,ComposerTurnOptions,HarnessId,MessageQueueStatus,QueuedMessage,RuntimeMode,UsageLimit } from "../model/session";
import { HARNESS_TITLE,harnessSupportsAttachments } from "../model/session";
import type {
UserQuestionPrompt,
UserQuestionReply,
} from "../model/userQuestion";
import { AccessPicker } from "./AccessPicker";

import { AttachmentChip } from "./AttachmentChip";
import { ContextMeter } from "./ContextMeter";




import { FileTypeIcon } from "../../../shared/ui/FileTypeIcon";
import { CwdPicker } from "../../projects/ui/CwdPicker";
import { McpServerPicker } from "./McpServerPicker";
import { NoteMentionPicker } from "./NoteMentionPicker";

import { NoteMiniCard } from "../../notes/ui/NoteMiniCard";

import { projectKey } from "../../../shared/lib/paths";
import { useTabGroupLogos } from "../../projects/hooks/useTabGroupLogos";
import { SkillPicker } from "../../skills/ui/SkillPicker";
import { consumeQuoteRequest,type QuoteRequest } from "../model/quoteDraft";
import { ModelControlPills,ModelPicker } from "./ModelPicker";
import { ComposerRunner } from "./ComposerRunner";
import { QuestionForm } from "./QuestionForm";

import { Popover } from "../../../shared/ui/Popover";
import {
loadNotes,
peekNotes,
type Note,
type NoteComposerCard,
} from "../../notes";
import { loadComposerRunner, subscribeComposerRunner, loadModelControls,loadNotesEnabled,subscribeModelControls,subscribeNotesEnabled } from "../../settings/model/settings";
import { resolveTabGroupLogo } from "../../workspace/model/tabGroups";
import { UsageLimitNotice } from "./UsageLimitNotice";
import { useComposerSkills } from "./useComposerSkills";

import {
consumeOperatorCommand,
OPERATOR_COMMAND,
} from "../model/operatorCommand";

import { type McpConnection } from "../../settings/model/mcp";
import {
getCachedMcpSettings,
loadMcpSettings,
subscribeMcpSettings,
type McpSettingsSnapshot,
} from "../../settings/model/mcpSettingsCache";
import {
BTW_COMMAND,
consumeBtwCommand,
consumeBtwPrefix,
supportsBtwHarness,
} from "../model/btw";
import { COMPACT_COMMAND,isCompactCommand } from "../model/compact";
import { getComposerMcpTags,setComposerMcpTags } from "../model/draftCache";
import { consumeDraftCommand,DRAFT_COMMAND } from "../model/draftCommand";
import type { LastTurnRecall } from "../model/editLastTurn";
import { isMcpCommand,MCP_COMMAND } from "../model/mcpCommand";
import {
mcpContextText,
mcpTagParts,
newMcpTag,
taggedMcpServers,
type McpTag,
} from "../model/mcpPicker";
import {
consumeSessionFolderCommand,
isSessionFolderCommand,
runsSessionFolderCommandOnSpace,
SESSION_FOLDER_COMMAND,
} from "../model/sessionFolderCommand";
import {
loadSessionFolders,
type SessionFolder,
type SessionFolderTarget,
} from "../model/sessionFolders";
import {
leadingModeCommand,
MODE_COMMAND_INDENT,
ModeCommandPill,
ModeCommandText,
type ModeCommandToken,
} from "./modeCommands";
import { SessionFolderPicker } from "./SessionFolderPicker";

type Props = {
  enabled?: boolean;
  focused: boolean;
  /** Bump to force a refocus even when `focused` was already true (e.g. window regains OS focus). */
  focusToken?: number;
  shell?: boolean;
  compact?: boolean;
  placeholder?: string;
  inputAriaLabel?: string;
  disabled?: boolean;
  allowedModelHarnesses?: readonly HarnessId[];
  harness: HarnessId;
  model: string;
  modelSettings?: Record<string, string>;
  runtimeMode: RuntimeMode;
  cwd?: string;
  executionCwd: string;
  sessionId?: string;

  recents?: RecentProject[];
  hideProjectPicker?: boolean;

  hideTopBar?: boolean;
  /** Keeps local file mentions, skills, and app modes off for host sessions. */


  context?: ContextUsage;
  compactSupported?: boolean;
  quoteRequest?: QuoteRequest;
  initialDraft?: string;
  draftResetToken?: number;

  noteCard?: NoteComposerCard;

  question?: UserQuestionPrompt;
  busy?: boolean;
  /** Allow typed text to replace Stop with Send while a turn is running. */
  allowBusySubmit?: boolean;
  editLastTurnSupported?: boolean;
  lastTurnRecall?: LastTurnRecall | null;
  queuedMessages?: QueuedMessage[];
  queueStatus?: MessageQueueStatus;
  usageLimit?: UsageLimit;
  hotkeys?: boolean;
  onFocus: () => void;
  onCwdChange: (cwd: string) => void;










  onModelChange: (harness: HarnessId, model: string) => void;
  onModelSettingsChange?: (settings: Record<string, string>) => void;
  onRuntimeModeChange: (mode: RuntimeMode) => void;
  onQuoteRequestConsumed?: (id: number) => void;

  onNoteCardDismiss?: () => void;

  onQuestionReply?: (requestId: number, reply: UserQuestionReply) => void;
  onQuestionInteraction?: (requestId: number) => void;
  onSubmit: (
    text: string,
    attachments: Attachment[],
    options?: ComposerTurnOptions,
  ) => boolean | void;
  /** `draft` opens the side question with the text unsent, for a typed `/btw `. */
  onBtwCommand?: (
    text: string,
    options?: { draft?: boolean },
  ) => boolean | void;
  canSaveDraft?: boolean;
  onSaveDraft?: (text: string, attachments: Attachment[]) => boolean | void;
  onStop?: () => void;
  onCompactContext?: () => boolean;
  onPlaceInFolder?: (target: SessionFolderTarget) => void;
  onDeleteQueuedMessage?: (messageId: string) => void;
  onEditQueuedMessage?: (messageId: string, text: string) => void;
  onQueuedMessageEditingChange?: (messageId?: string) => void;
  onSteerQueuedMessage?: (messageId: string) => void;
  onResumeQueue?: () => void;
  onUsageLimitResume?: () => void;
  onUsageLimitResumeAtReset?: (enabled: boolean) => void;
  onUsageLimitDismiss?: () => void;
  onOpenFile?: (path: string) => void;
  onDraftChange?: (text: string) => void;
  onRecallLastTurnReady?: (recall: () => void) => void;
  onEditingLastTurnChange?: (editing: boolean) => void;
  children?: ReactNode;
};

function ToolButton({
  active,
  disabled,
  label,
  onClick,
  children,
}: {
  active?: boolean;
  disabled?: boolean;
  label: string;
  onClick?: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      className={`grid size-6.5 shrink-0 place-items-center rounded-md ${
        active
          ? "bg-selection-emphasis text-content"
          : "bg-selection text-content/50 hover:bg-selection-hover hover:text-content"
      } disabled:opacity-40 disabled:hover:bg-transparent disabled:hover:text-content/50`}
    >
      {children}
    </button>
  );
}

function MessageQueue({
  messages,
  status,
  onDelete,
  onEdit,
  onEditingChange,
  onSteer,
  onResume,
}: {
  messages: QueuedMessage[];
  status?: MessageQueueStatus;
  onDelete?: (messageId: string) => void;
  onEdit?: (messageId: string, text: string) => void;
  onEditingChange?: (messageId?: string) => void;
  onSteer?: (messageId: string) => void;
  onResume?: () => void;
}) {
  const [editingId, setEditingId] = useState<string>();
  const [editDraft, setEditDraft] = useState("");
  const onEditingChangeRef = useRef(onEditingChange);
  onEditingChangeRef.current = onEditingChange;
  const editingIdRef = useRef(editingId);
  editingIdRef.current = editingId;
  useEffect(() => {
    return () => {
      if (editingIdRef.current) onEditingChangeRef.current?.();
    };
  }, []);
  if (messages.length === 0) return null;
  const paused = status === "paused";

  const startEdit = (message: QueuedMessage) => {
    setEditingId(message.id);
    setEditDraft(message.text);
    onEditingChange?.(message.id);
  };
  const cancelEdit = () => {
    setEditingId(undefined);
    setEditDraft("");
    onEditingChange?.();
  };
  const saveEdit = (message: QueuedMessage) => {
    if (!editDraft.trim() && message.attachments.length === 0) return;
    onEdit?.(message.id, editDraft);
    setEditingId(undefined);
    setEditDraft("");
  };

  return (
    <div className="px-2 text-content/55" data-message-queue>
      <div
        className="relative z-0 rounded-t-[10px] border border-b-0 border-content/10 bg-content/3 px-2 py-1"
        data-message-queue-card
      >
        {paused ? (
          <div className="flex h-7 items-center gap-2 border-b border-stroke text-[12px]">
            <Pause className="size-3.5" />
            <span className="min-w-0 flex-1 truncate">
              Queue paused because you interrupted
            </span>
            <button
              type="button"
              onClick={onResume}
              className="flex h-6 shrink-0 items-center gap-1.5 rounded-md px-1.5 hover:bg-content/10 hover:text-content"
            >
              <Play className="size-3.5" />
              Resume
            </button>
          </div>
        ) : null}
        {messages.map((message, index) => {
          const editing = editingId === message.id;
          const label =
            message.text.trim() ||
            `${message.attachments.length} attachment${message.attachments.length === 1 ? "" : "s"}`;
          return (
            <div
              key={message.id}
              className={`flex min-h-7 items-center gap-2 text-[12px] ${
                index > 0 ? "border-t border-stroke" : ""
              }`}
            >
              <ListEnd className="size-3.5 shrink-0" />
              {editing ? (
                <>
                  <textarea
                    autoFocus
                    aria-label="Edit queued message"
                    value={editDraft}
                    rows={1}
                    onChange={(event) => setEditDraft(event.target.value)}
                    onKeyDown={(event) => {
                      if (isImeComposition(event.nativeEvent)) return;
                      if (event.key === "Escape") {
                        event.preventDefault();
                        cancelEdit();
                      } else if (event.key === "Enter" && !event.shiftKey) {
                        event.preventDefault();
                        saveEdit(message);
                      }
                    }}
                    className="min-h-6 min-w-0 flex-1 resize-none rounded-md border border-content/15 bg-content/5 px-1.5 py-0.5 text-[12px] text-content outline-none focus:border-content/30"
                  />
                  <button
                    type="button"
                    title="Save queued message"
                    aria-label="Save queued message"
                    disabled={
                      !editDraft.trim() && message.attachments.length === 0
                    }
                    onClick={() => saveEdit(message)}
                    className="grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content disabled:opacity-30"
                  >
                    <Check className="size-3.5" />
                  </button>
                  <button
                    type="button"
                    title="Cancel queued message edit"
                    aria-label="Cancel queued message edit"
                    onClick={cancelEdit}
                    className="grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content"
                  >
                    <X className="size-3.5" />
                  </button>
                </>
              ) : (
                <>
                  <span className="min-w-0 flex-1 truncate text-content/80">
                    {label}
                  </span>
                  <button
                    type="button"
                    onClick={() => onSteer?.(message.id)}
                    className="flex h-6 shrink-0 items-center gap-1.5 rounded-md px-1.5 hover:bg-content/10 hover:text-content"
                  >
                    <CornerDownRight className="size-3.5" />
                    Steer
                  </button>
                  <button
                    type="button"
                    title="Edit queued message"
                    aria-label="Edit queued message"
                    onClick={() => startEdit(message)}
                    className="grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content"
                  >
                    <Pencil className="size-3.5" />
                  </button>
                  <button
                    type="button"
                    title="Remove queued message"
                    aria-label="Remove queued message"
                    onClick={() => onDelete?.(message.id)}
                    className="grid size-6 shrink-0 place-items-center rounded-md hover:bg-content/10 hover:text-content"
                  >
                    <Trash2 className="size-3.5" />
                  </button>
                </>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function Composer({
  enabled = true,
  focused,
  focusToken,
  hotkeys = false,
  shell = false,
  compact = false,
  placeholder,
  inputAriaLabel,
  disabled = false,
  harness,
  model,
  allowedModelHarnesses,
  modelSettings = {},
  runtimeMode,
  cwd = "~",
  executionCwd,
  sessionId,

  recents = [],
  hideProjectPicker = false,

  hideTopBar = false,


  context,
  compactSupported = false,
  quoteRequest,
  initialDraft,
  draftResetToken,

  noteCard,

  question,
  busy = false,
  allowBusySubmit = true,
  editLastTurnSupported = false,
  lastTurnRecall = null,
  queuedMessages = [],
  queueStatus,
  usageLimit,
  onFocus,
  onCwdChange,










  onModelChange,
  onModelSettingsChange,
  onRuntimeModeChange,
  onQuoteRequestConsumed,

  onBtwCommand,
  onNoteCardDismiss,

  onQuestionReply,
  onQuestionInteraction,
  onSubmit,
  canSaveDraft = false,
  onSaveDraft,
  onStop,
  onCompactContext,
  onPlaceInFolder,
  onDeleteQueuedMessage,
  onEditQueuedMessage,
  onQueuedMessageEditingChange,
  onSteerQueuedMessage,
  onResumeQueue,
  onUsageLimitResume,
  onUsageLimitResumeAtReset,
  onUsageLimitDismiss,
  onOpenFile,
  onDraftChange,
  onRecallLastTurnReady,
  onEditingLastTurnChange,
  children,
}: Props) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const observedFocusToken = useRef<number | undefined>(undefined);
  const boxRef = useRef<HTMLDivElement>(null);
  const plusRef = useRef<HTMLDivElement>(null);
  const highlightRef = useRef<HTMLDivElement>(null);
  const attachmentsRef = useRef<Attachment[]>([]);
  const borrowedAttachmentIdsRef = useRef(new Set<string>());
  const attachmentLifecycleRef = useRef(0);
  const consumedQuoteId = useRef<number | null>(null);
  const draftRevisionRef = useRef(0);
  const draftResetTokenRef = useRef(draftResetToken);
  /** Bumped when the draft is cleared, so a late file read cannot land on the next one. */
  const pasteGenerationRef = useRef(0);
  /** Pasted and dropped files still reading when Send is pressed. */
  const pasteFlightRef = useRef<Promise<void> | null>(null);
  const submitLockRef = useRef(false);
  const positionedInitialDraft = useRef(false);
  const slashRef = useRef<SlashToken | null>(null);
  const mentionRef = useRef<MentionToken | null>(null);
  const [draft, setDraft] = useState(initialDraft ?? "");



  const [hasValue, setHasValue] = useState(
    () =>
      (initialDraft ?? "").trim().length > 0 ||
      !!noteCard,
  );
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [pasteError, setPasteError] = useState<string | null>(null);
  const [fileDrag, setFileDrag] = useState(false);
  const [plusOpen, setPlusOpen] = useState(false);
  const runnerEnabled = useSyncExternalStore(subscribeComposerRunner, loadComposerRunner);
  const [runnerLive, setRunnerLive] = useState(() => busy && loadComposerRunner());
  useEffect(() => {
    if (!runnerEnabled) setRunnerLive(false);
    else if (busy) setRunnerLive(true);
  }, [busy, runnerEnabled]);

  const [operatorSelected, setOperatorSelected] = useState(false);

  const [draftSelected, setDraftSelected] = useState(false);
  const [slash, setSlash] = useState<SlashToken | null>(null);
  const [skillActive, setSkillActive] = useState(0);
  const [creatingSkill, setCreatingSkill] = useState(false);
  const [sessionFolderOpen, setSessionFolderOpen] = useState(false);
  const [sessionFolders, setSessionFolders] = useState<SessionFolder[]>([]);
  const [sessionFolderSelected, setSessionFolderSelected] = useState(false);
  const [mcpPickerOpen, setMcpPickerOpen] = useState(false);
  const [mcpConnections, setMcpConnections] = useState<McpConnection[]>([]);
  const [mcpStatus, setMcpStatus] = useState<Map<string, string>>(new Map());
  const [mcpLoading, setMcpLoading] = useState(false);
  const [mcpError, setMcpError] = useState("");
  const [selectedMcp, setSelectedMcp] = useState<McpTag[]>(() =>
    sessionId ? getComposerMcpTags(sessionId) : [],
  );
  const mcpInsertAt = useRef<number | null>(null);
  const [createError, setCreateError] = useState<string | null>(null);
  const [createBusy, setCreateBusy] = useState(false);

  // Use the selected project for local skills and MCP settings.
  const localCwd = executionCwd;

  const notesEnabled = useSyncExternalStore(
    subscribeNotesEnabled,
    loadNotesEnabled,
    () => true,
  );
  const modelControls = useSyncExternalStore(
    subscribeModelControls,
    loadModelControls,
    () => "menu" as const,
  );
  const controlsBeside = modelControls === "beside";
  const [notes, setNotes] = useState<Note[]>(() => peekNotes() ?? []);
  const [canvases, setCanvases] = useState<Canvas[]>(() => peekCanvases() ?? []);
  const [projectFiles, setProjectFiles] = useState<ProjectFile[]>([]);
  const [mention, setMention] = useState<MentionToken | null>(null);
  const [mentionActive, setMentionActive] = useState(0);
  const [resendEdited, setResendEdited] = useState(false);


  const groupLogos = useTabGroupLogos();
  const projectLogoPath = resolveTabGroupLogo(projectKey(cwd), groupLogos);

  slashRef.current = slash;
  mentionRef.current = mention;

  attachmentsRef.current = attachments;

  const mentionOpen =
    mention !== null && (looksLikeProject(cwd) || notesEnabled);
  const navigationEmpty =
    draft.length === 0 &&
    attachments.length === 0 &&
    !noteCard;
  const skillPickerOpen = creatingSkill || slash !== null;
  const pickerOpen = skillPickerOpen || sessionFolderOpen || mcpPickerOpen;
  const skillCatalog = useComposerSkills({
    harness,
    executionCwd: localCwd,
    sessionId,
    pickerOpen: pickerOpen,
  });
  const skills = skillCatalog.skills;
  const slashItems = useMemo(() => [
    SESSION_FOLDER_COMMAND, MCP_COMMAND, OPERATOR_COMMAND,
    ...(canSaveDraft && onSaveDraft ? [DRAFT_COMMAND] : []), COMPACT_COMMAND,
    ...(supportsBtwHarness(harness) ? [BTW_COMMAND] : []),
    ...skills.filter((skill) => skill.kind === "native" ||
      ![OPERATOR_COMMAND.name, COMPACT_COMMAND.name, SESSION_FOLDER_COMMAND.name,
        MCP_COMMAND.name, DRAFT_COMMAND.name, BTW_COMMAND.name].includes(skill.name)),
  ], [harness, skills, canSaveDraft, onSaveDraft]);
  const skillLimit = hasNativeCommands(harness)
    ? Number.POSITIVE_INFINITY
    : undefined;
  const rankedSkills = rankSkills(slashItems, slash?.query ?? "", skillLimit);
  const attachmentsSupported = harnessSupportsAttachments(harness);
  const skillNames = useMemo(
    () => new Set(slashItems.map((skill) => skill.invocation)),
    [slashItems],
  );
  const leadingMode = leadingModeCommand(draft, skillNames);
  const modeIndent = leadingMode ? MODE_COMMAND_INDENT : undefined;
  useLayoutEffect(() => {
    // The indent can rewrap the first line after the input already resized.
    if (ref.current) resizeComposer(ref.current);
  }, [modeIndent]);
  const inProject = looksLikeProject(cwd);
  const mentionSources = useMemo(() => ({
    notes: notesEnabled ? notes : [],
    canvases: inProject ? projectCanvases(canvases, cwd) : [],
    files: inProject ? projectFiles : [],
  }), [notesEnabled, notes, inProject, canvases, cwd, projectFiles]);
  const mentionIndex = useMemo(() => buildMentionSources(mentionSources), [mentionSources]);
  const mentionIndexRef = useRef<MentionIndex>(mentionIndex);
  mentionIndexRef.current = mentionIndex;
  const rankedFiles = useMemo(
    () => mentionOpen ? rankMentions(mentionSources, mention?.query ?? "") : [],
    [mentionOpen, mentionSources, mention?.query],
  );

  const syncHasValue = useCallback(
    (text: string, files: Attachment[]) => {
      setHasValue(
        text.trim().length > 0 ||
          files.length > 0 ||
          !!noteCard,
      );
    },
    [noteCard],
  );

  // A leading mode command in the text shows the same pill as picking the mode.
  const operatorActive =
    operatorSelected || leadingMode?.name === OPERATOR_COMMAND.name;

  const draftActive = draftSelected || leadingMode?.name === DRAFT_COMMAND.name;


  /** Turning a mode off also drops its leading command from the text. */
  const clearLeadingMode = (name: string) => {
    const el = ref.current;
    if (!el || leadingModeCommand(el.value, skillNames)?.name !== name) return;
    const next = el.value.replace(/^\/[a-z]+\s?/, "");
    el.value = next;
    resizeComposer(el);
    el.setSelectionRange(0, 0);
    setDraft(next);
    onDraftChange?.(next);
    syncHasValue(next, attachmentsRef.current);
  };

  const openMcpPicker = useCallback(() => {
    setMcpConnections([]);
    setMcpStatus(new Map());
    setMcpError("");
    setMcpLoading(true);
    setMcpPickerOpen(true);
  }, []);

  useEffect(() => {
    if (!mcpPickerOpen) return;
    const apply = (snapshot: McpSettingsSnapshot) => {
      setMcpConnections(snapshot.servers);
      setMcpStatus(
        new Map(
          snapshot.servers
            .filter((server) => server.provider === "claude")
            .map((server) => [server.name, server.status]),
        ),
      );
      setMcpError(snapshot.error);
      setMcpLoading(false);
    };
    const stop = subscribeMcpSettings(executionCwd, apply);
    const cached = getCachedMcpSettings(executionCwd);
    if (cached) apply(cached);
    void loadMcpSettings(executionCwd, false, {
      claudeHealth: harness === "claude",
    });
    return stop;
  }, [executionCwd, harness, mcpPickerOpen]);

  useEffect(() => {
    setMcpPickerOpen(false);
  }, [executionCwd, harness, sessionId]);

  useEffect(() => {
    if (sessionId) setComposerMcpTags(sessionId, selectedMcp);
  }, [sessionId, selectedMcp]);

  useEffect(() => {
    syncHasValue(ref.current?.value ?? "", attachmentsRef.current);
  }, [noteCard, syncHasValue]);

  const addAttachments = useCallback(
    (incoming: Attachment[]) => {
      if (!harnessSupportsAttachments(harness) || incoming.length === 0) return;
      const next = mergeAttachments(attachmentsRef.current, incoming);
      attachmentsRef.current = next;
      setAttachments(next);
      setPasteError(null);
      draftRevisionRef.current += 1;
      syncHasValue(ref.current?.value ?? "", next);
      ref.current?.focus();
    },
    [harness, syncHasValue],
  );
  // Native listener registration crosses several IPC hops. Keep changing
  // composer callbacks and capabilities out of its subscription dependencies.
  const fileDropStateRef = useRef({
    attachmentsSupported,

    addAttachments,
  });
  fileDropStateRef.current = { attachmentsSupported, addAttachments };

  const rememberAttachmentRead = useCallback((work: Promise<void>) => {
    const flight = work.then(
      () => undefined,
      () => undefined,
    );
    const previous = pasteFlightRef.current;
    const joined = previous ? previous.then(() => flight) : flight;
    pasteFlightRef.current = joined;
    void joined.finally(() => {
      if (pasteFlightRef.current === joined) pasteFlightRef.current = null;
    });
  }, []);

  const readDroppedAttachments = useCallback(
    (read: () => Promise<Attachment[]>) => {
      const generation = pasteGenerationRef.current;
      setPasteError(null);
      rememberAttachmentRead(
        read()
          .then((incoming) => {
            if (
              pasteGenerationRef.current !== generation ||
              !fileDropStateRef.current.attachmentsSupported
            ) {
              incoming.forEach(revokeAttachment);
              return;
            }
            if (incoming.length === 0) {
              setPasteError(
                "Nothing to attach from that drop — the file may have been moved, renamed, or deleted.",
              );
              return;
            }
            fileDropStateRef.current.addAttachments(incoming);
          })
          .catch((reason: unknown) => {
            if (pasteGenerationRef.current !== generation) return;
            setPasteError(
              reason instanceof Error ? reason.message : String(reason),
            );
          }),
      );
    },
    [rememberAttachmentRead],
  );

  const removeAttachment = useCallback(
    (id: string) => {
      const previous = attachmentsRef.current;
      const removed = previous.find((file) => file.id === id);
      if (removed && !borrowedAttachmentIdsRef.current.delete(removed.id)) {
        revokeAttachment(removed);
      }
      const next = previous.filter((file) => file.id !== id);
      attachmentsRef.current = next;
      draftRevisionRef.current += 1;
      setAttachments(next);
      setPasteError(null);
      syncHasValue(ref.current?.value ?? "", next);
      ref.current?.focus();
    },
    [syncHasValue],
  );
  useEffect(() => {
    const lifecycle = ++attachmentLifecycleRef.current;
    return () => {
      queueMicrotask(() => {
        if (attachmentLifecycleRef.current !== lifecycle) return;
        pasteGenerationRef.current += 1;
        for (const file of attachmentsRef.current) {
          if (!borrowedAttachmentIdsRef.current.delete(file.id)) {
            revokeAttachment(file);
          }
        }
        attachmentsRef.current = [];
        borrowedAttachmentIdsRef.current.clear();
      });
    };
  }, []);

  useEffect(() => {
    if (harnessSupportsAttachments(harness)) return;
    const previous = attachmentsRef.current;
    if (previous.length === 0) return;
    for (const file of previous) {
      if (!borrowedAttachmentIdsRef.current.delete(file.id)) {
        revokeAttachment(file);
      }
    }
    attachmentsRef.current = [];
    setAttachments([]);
    syncHasValue(ref.current?.value ?? "", []);
  }, [harness, syncHasValue]);




  useEffect(() => {
    setSkillActive(0);
  }, [slash?.query, cwd]);

  useEffect(() => {
    setSessionFolderOpen(false);
    setSessionFolderSelected(false);
  }, [cwd]);

  useEffect(() => {
    setSkillActive((index) =>
      rankedSkills.length === 0 ? 0 : Math.min(index, rankedSkills.length - 1),
    );
  }, [rankedSkills.length]);



  // What `@` can reach is loaded when the picker opens, and also while the
  // draft already holds an `@`, so a restored draft highlights its mentions.
  const mentionsWanted = mentionOpen || draft.includes("@");
  useEffect(() => {
    if (!mentionsWanted || !notesEnabled) return;
    let cancelled = false;
    void loadNotes().then((next) => {
      if (!cancelled) setNotes(next);
    });
    return () => {
      cancelled = true;
    };
  }, [mentionsWanted, notesEnabled]);

  useEffect(() => {
    if (!mentionsWanted || !inProject) return;
    let cancelled = false;
    const refresh = () => {
      void loadCanvases().then((next) => {
        if (!cancelled) setCanvases(next);
      }).catch(() => undefined);
    };
    refresh();
    window.addEventListener(CANVASES_CHANGED_EVENT, refresh);
    return () => {
      cancelled = true;
      window.removeEventListener(CANVASES_CHANGED_EVENT, refresh);
    };
  }, [mentionsWanted, inProject]);

  // The listing is cached per project and dropped when the folder changes, so
  // asking again each time the picker opens is cheap and never stale.
  useEffect(() => {
    if (!mentionsWanted || !inProject) return;
    let cancelled = false;
    void loadProjectFiles(cwd).then((next) => {
      if (!cancelled) setProjectFiles(next);
    }).catch(() => {
      if (!cancelled) setProjectFiles([]);
    });
    return () => {
      cancelled = true;
    };
  }, [mentionsWanted, mentionOpen, inProject, cwd]);

  useEffect(() => {
    setMentionActive(0);
  }, [mention?.query, cwd]);

  useEffect(() => {
    setMentionActive((index) =>
      rankedFiles.length === 0 ? 0 : Math.min(index, rankedFiles.length - 1),
    );
  }, [rankedFiles.length]);

  useEffect(() => {
    const el = ref.current;
    if (!el || !initialDraft) return;
    if (el.value !== initialDraft) el.value = initialDraft;
    if (!positionedInitialDraft.current) {
      const end = el.value.length;
      el.setSelectionRange(end, end);
      positionedInitialDraft.current = true;
    }
    resizeComposer(el);
  }, [initialDraft]);

  // Drafts changed while hidden could not be measured. Session panes are portaled
  // into place by a parent effect that runs after this one, so the first pass
  // can still find no layout box; retry once the move has landed.
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || !enabled) return;
    resizeComposer(el);
    if (el.scrollHeight !== 0) return;
    const frame = requestAnimationFrame(() => {
      if (ref.current === el) resizeComposer(el);
    });
    return () => cancelAnimationFrame(frame);
  }, [enabled]);

  useEffect(() => {
    onDraftChange?.(draft);
  }, [draft, onDraftChange]);
  useEffect(() => {
    if (
      draftResetToken == null ||
      draftResetTokenRef.current === draftResetToken
    ) {
      return;
    }
    draftResetTokenRef.current = draftResetToken;
    pasteGenerationRef.current += 1;
    draftRevisionRef.current += 1;
    if (ref.current) {
      ref.current.value = "";
      ref.current.style.height = "auto";
    }
    setDraft("");
    onDraftChange?.("");
    setDraftSelected(false);


    setSessionFolderSelected(false);
    setSessionFolderOpen(false);
    setMcpPickerOpen(false);
    setSelectedMcp([]);
    setPlusOpen(false);
    setSlash(null);
    setMention(null);
    setCreatingSkill(false);
    setCreateError(null);
    syncHasValue("", attachmentsRef.current);
  }, [draftResetToken, onDraftChange, syncHasValue]);

  const syncHighlightScroll = useCallback((el: HTMLTextAreaElement) => {
    const highlight = highlightRef.current;
    if (!highlight) return;
    highlight.scrollTop = el.scrollTop;
    highlight.scrollLeft = el.scrollLeft;
  }, []);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;

    // The textarea can scroll itself to keep the caret visible before React
    // commits the updated highlight text. Sync again after that commit, when
    // the overlay has enough scrollable content to accept the same offset.
    syncHighlightScroll(el);
    const frame = requestAnimationFrame(() => {
      if (ref.current === el) syncHighlightScroll(el);
    });
    return () => cancelAnimationFrame(frame);
  }, [draft, syncHighlightScroll]);

  const syncTokensFromTextarea = (el: HTMLTextAreaElement) => {
    if (creatingSkill) return;
    const cursor = el.selectionStart ?? 0;
    const token = slashTokenAt(el.value, cursor, hasNativeCommands(harness));
    setSlash(token);
    setMention(token ? null : mentionTokenAt(el.value, cursor));
  };

  const openSessionFolderPicker = useCallback(() => {
    setSessionFolders(loadSessionFolders(cwd));
    setSessionFolderOpen(true);
  }, [cwd]);

  useEffect(() => {
    const el = ref.current;
    if (!el || !quoteRequest) return;

    const result = consumeQuoteRequest(
      el.value,
      consumedQuoteId.current,
      quoteRequest,
    );
    consumedQuoteId.current = result.consumedId;
    if (result.changed) {
      el.value = result.draft;
      resizeComposer(el);
      setDraft(result.draft);
      syncHasValue(result.draft, attachmentsRef.current);
      setSlash(null);
      setMention(null);
      setCreatingSkill(false);
      setCreateError(null);
      el.setSelectionRange(result.draft.length, result.draft.length);
      el.focus();
    }
    onQuoteRequestConsumed?.(quoteRequest.id);
  }, [onQuoteRequestConsumed, quoteRequest, syncHasValue]);

  // `/btw ` opens the side conversation as soon as it is typed, carrying any
  // text after it over as the unsent side question.
  const enterBtwFromPrefix = useCallback(
    (el: HTMLTextAreaElement) => {
      if (!onBtwCommand || noteCard) return false;
      if (attachmentsRef.current.length > 0) return false;
      const rest = consumeBtwPrefix(el.value);
      if (rest == null || onBtwCommand(rest, { draft: true }) === false) {
        return false;
      }
      el.value = "";
      resizeComposer(el);
      draftRevisionRef.current += 1;
      setDraft("");
      onDraftChange?.("");
      syncHasValue("", attachmentsRef.current);
      setSlash(null);
      setMention(null);
      return true;
    },
    [


      noteCard,
      onBtwCommand,
      onDraftChange,
      syncHasValue,
    ],
  );

  const pickSkill = useCallback(
    (skill: Skill) => {
      const el = ref.current;
      const token = slashRef.current;
      if (!el || !token) {
        setSlash(null);
        setCreatingSkill(false);
        return;
      }
      if (skill.kind === "builtin" && skill.name === MCP_COMMAND.name) {
        const next = `${el.value.slice(0, token.start)}${el.value.slice(token.end).replace(/^\s/, "")}`;
        el.value = next;
        resizeComposer(el);
        mcpInsertAt.current = token.start;
        el.setSelectionRange(token.start, token.start);
        setDraft(next);
        onDraftChange?.(next);
        syncHasValue(next, attachmentsRef.current);
        setSlash(null);
        openMcpPicker();
        return;
      }
      const sessionFolderCommand =
        skill.kind === "builtin" &&
        skill.name === SESSION_FOLDER_COMMAND.name &&
        !!onPlaceInFolder;
      if (sessionFolderCommand) {
        const next = replaceSlashToken(
          el.value,
          token,
          SESSION_FOLDER_COMMAND.invocation,
        );
        el.value = next;
        resizeComposer(el);
        let cursor = token.start + SESSION_FOLDER_COMMAND.invocation.length + 1;
        if (next[cursor] === " ") cursor += 1;
        el.setSelectionRange(cursor, cursor);
        setDraft(next);
        syncHasValue(next, attachmentsRef.current);
        setSlash(null);
        setCreatingSkill(false);
        openSessionFolderPicker();
        return;
      }
      const next = replaceSlashToken(el.value, token, skill.invocation);
      el.value = next;
      resizeComposer(el);
      let cursor = token.start + skill.invocation.length + 1;
      if (next[cursor] === " ") cursor += 1;
      el.setSelectionRange(cursor, cursor);
      setDraft(next);
      syncHasValue(next, attachmentsRef.current);
      setSlash(null);
      setCreatingSkill(false);
      if (skill.kind === "builtin" && skill.name === BTW_COMMAND.name) {
        enterBtwFromPrefix(el);
      }
      el.focus();
    },
    [
      enterBtwFromPrefix,
      onDraftChange,
      onPlaceInFolder,
      openMcpPicker,
      openSessionFolderPicker,
      syncHasValue,
    ],
  );

  const pickMention = useCallback(
    (file: ProjectFile) => {
      const el = ref.current;
      const token = mentionRef.current;
      if (!el || !token) {
        setMention(null);
        return;
      }
      // Notes and drawings are always written with their `note/` or `canvas/` label.
      const label = mentionKind(file.path) === "file"
        ? mentionLabel(file, mentionIndexRef.current)
        : file.relative;
      const next = replaceMentionToken(el.value, token, label);
      el.value = next;
      resizeComposer(el);
      let cursor = token.start + label.length + 1;
      if (next[cursor] === " ") cursor += 1;
      el.setSelectionRange(cursor, cursor);
      setDraft(next);
      syncHasValue(next, attachmentsRef.current);
      setMention(null);
      el.focus();
    },
    [syncHasValue],
  );

  useEffect(() => {
    const explicitlyRequested = focusToken !== undefined &&
      focusToken !== observedFocusToken.current;
    observedFocusToken.current = focusToken;
    if (!focused || disabled) return;

    const composer = ref.current?.closest("[data-composer]");
    const activeComposer = document.activeElement?.closest("[data-composer]");
    const activeComposerHidden = activeComposer?.closest(
      '[aria-hidden="true"], [inert]',
    );
    // Inactive workspace tabs stay mounted, so focus can still be sitting in
    // their composer when a new session becomes active. Only preserve focus
    // for another composer that is still visible (for example, a split pane).
    if (activeComposer && activeComposer !== composer && !activeComposerHidden &&
        !explicitlyRequested)
      return;

    if (
      composer?.querySelector(
        "[data-skill-picker], [data-session-folder-picker], [data-mention-picker], [data-mcp-picker], [data-composer-plus], [data-question-form]",
      )
    )
      return;
    // Model/access/settings pickers render through a portal into
    // document.body (see Popover.tsx), so they never appear under this
    // composer's own DOM subtree — check the whole document for those.
    if (
      document.querySelector(
        "[data-model-picker], [data-access-picker], [data-model-settings]",
      )
    )
      return;
    ref.current?.focus();
  }, [disabled, focused, question, busy, focusToken]);

  useEffect(() => {
    if (!enabled || disabled) {
      setFileDrag(false);
      return;
    }
    const dropRoot = () =>
      boxRef.current?.closest("[data-session-drop]") as HTMLElement | null;
    let nativeDropAt = 0;
    let cancelled = false;

    const overTarget = (x: number, y: number) => {
      const root = dropRoot();
      if (!root) return false;
      const rect = root.getBoundingClientRect();
      return (
        x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom
      );
    };

    const onDragOver = (event: DragEvent) => {
      const data = event.dataTransfer;
      if (!hasFiles(data)) return;
      event.preventDefault();
      const supported = fileDropStateRef.current.attachmentsSupported;
      data.dropEffect = supported ? "copy" : "none";
      setFileDrag(supported);
    };
    const onDragLeave = (event: DragEvent) => {
      const root = dropRoot();
      if (!root) return;
      const next = event.relatedTarget as Node | null;
      if (next && root.contains(next)) return;
      setFileDrag(false);
    };
    const onDrop = (event: DragEvent) => {
      const data = event.dataTransfer;
      if (!hasFiles(data)) return;
      event.preventDefault();
      setFileDrag(false);
      if (!fileDropStateRef.current.attachmentsSupported) return;
      if (Date.now() - nativeDropAt < 250) return;
      const files = filesFromClipboard(data);
      if (files.length === 0) return;
      readDroppedAttachments(() => attachmentsFromFiles(files));
    };



    const root = dropRoot();
    root?.addEventListener("dragover", onDragOver);
    root?.addEventListener("dragleave", onDragLeave);
    root?.addEventListener("drop", onDrop);


    let unlisten: (() => void) | undefined;
    void getCurrentWebview()
      .onDragDropEvent((event) => {
        if (cancelled) return;
        if (event.payload.type === "leave") {
          setFileDrag(false);
          return;
        }
        const { x, y } = event.payload.position;
        const point = dragPointToClient(x, y);
        const over = overTarget(point.x, point.y);
        const supported = fileDropStateRef.current.attachmentsSupported;
        if (event.payload.type === "enter" || event.payload.type === "over") {
          setFileDrag(over && supported);
          return;
        }
        if (event.payload.type !== "drop") return;
        setFileDrag(false);
        if (!over || !supported) return;
        if (event.payload.paths.length === 0) {
          setPasteError(
            "This drag did not provide a file. Save the image, then drag the saved file here.",
          );
          return;
        }
        nativeDropAt = Date.now();
        const paths = event.payload.paths;
        readDroppedAttachments(() => attachmentsFromPaths(paths));
      })
      .then((fn) => {
        if (cancelled) fn();
        else unlisten = fn;
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
      root?.removeEventListener("dragover", onDragOver);
      root?.removeEventListener("dragleave", onDragLeave);
      root?.removeEventListener("drop", onDrop);

      unlisten?.();
    };
  }, [disabled, enabled, readDroppedAttachments]);
  useEffect(() => {
    if (!attachmentsSupported) setFileDrag(false);
  }, [attachmentsSupported]);
  const restoreDraft = useCallback(
    (
      text: string,
      nextAttachments: Attachment[],
      borrowedIds: ReadonlySet<string> = borrowedAttachmentIdsRef.current,
    ) => {
      setDraft(text);
      onDraftChange?.(text);
      if (ref.current) {
        ref.current.value = text;
        resizeComposer(ref.current);
      }

      const nextIds = new Set(nextAttachments.map((file) => file.id));
      for (const file of attachmentsRef.current) {
        if (
          nextIds.has(file.id) ||
          borrowedAttachmentIdsRef.current.delete(file.id)
        ) {
          continue;
        }
        revokeAttachment(file);
      }
      borrowedAttachmentIdsRef.current = new Set(
        nextAttachments
          .filter((file) => borrowedIds.has(file.id))
          .map((file) => file.id),
      );
      attachmentsRef.current = nextAttachments;
      setAttachments(nextAttachments);
      syncHasValue(text, nextAttachments);
      ref.current?.focus();
    },
    [onDraftChange, syncHasValue],
  );

  const exitEditMode = useCallback(() => {
    draftRevisionRef.current += 1;
    pasteGenerationRef.current += 1;
    if (ref.current) {
      ref.current.value = "";
      ref.current.style.height = "auto";
    }
    setDraft("");
    onDraftChange?.("");
    const previous = attachmentsRef.current;
    for (const file of previous) {
      if (!borrowedAttachmentIdsRef.current.delete(file.id)) {
        revokeAttachment(file);
      }
    }
    attachmentsRef.current = [];
    setAttachments([]);
    setResendEdited(false);
    onEditingLastTurnChange?.(false);
    setPlusOpen(false);
    setSlash(null);
    setMention(null);
    setMcpPickerOpen(false);
    setSelectedMcp([]);
    syncHasValue("", []);
    ref.current?.focus();
  }, [onDraftChange, onEditingLastTurnChange, syncHasValue]);

  const recallLastTurn = useCallback(() => {
    if (!editLastTurnSupported || !lastTurnRecall) return;
    if (resendEdited) {
      exitEditMode();
      return;
    }
    restoreDraft(
      lastTurnRecall.text,
      lastTurnRecall.attachments,
      new Set(lastTurnRecall.attachments.map((file) => file.id)),
    );
    setResendEdited(true);
    onEditingLastTurnChange?.(true);
  }, [
    editLastTurnSupported,
    exitEditMode,
    lastTurnRecall,
    onEditingLastTurnChange,
    resendEdited,
    restoreDraft,
  ]);

  useEffect(() => {
    draftRevisionRef.current += 1;
    setResendEdited(false);
    onEditingLastTurnChange?.(false);
  }, [sessionId, onEditingLastTurnChange]);

  useEffect(() => {
    if (editLastTurnSupported) return;
    setResendEdited(false);
    onEditingLastTurnChange?.(false);
  }, [editLastTurnSupported, onEditingLastTurnChange]);

  useEffect(() => {
    if (!editLastTurnSupported || !onRecallLastTurnReady) return;
    onRecallLastTurnReady(recallLastTurn);
  }, [editLastTurnSupported, onRecallLastTurnReady, recallLastTurn]);

  const submit = (value: string) => {
    if (disabled || submitLockRef.current) return;
    submitLockRef.current = true;
    void completeSubmit(value).finally(() => {
      submitLockRef.current = false;
    });
  };
  const completeSubmit = async (submittedValue: string) => {
    let pending = pasteFlightRef.current;
    const generation = pasteGenerationRef.current;
    while (pending) {
      await pending;
      // A reset or an earlier send retired this draft while the read was out.
      if (pasteGenerationRef.current !== generation) return;
      pending = pasteFlightRef.current;
    }
    const value = ref.current?.value ?? submittedValue;
    if (disabled) return;
    if (isMcpCommand(value)) {
      mcpInsertAt.current = 0;
      if (ref.current) {
        ref.current.value = "";
        ref.current.style.height = "auto";
      }
      setDraft("");
      onDraftChange?.("");
      setSlash(null);
      syncHasValue("", attachments);
      openMcpPicker();
      return;
    }
    const draftCommand = canSaveDraft
      ? consumeDraftCommand(value)
      : { text: value, matched: false };
    if ((draftSelected || draftCommand.matched) && onSaveDraft) {
      const files = attachmentsRef.current;
      const text = draftCommand.text;
      if (!text.trim() && files.length === 0) return;
      const accepted = onSaveDraft(
        mcpContextText(taggedMcpServers(text, selectedMcp), text),
        files,
      );
      if (accepted === false || !ref.current) return;
      pasteGenerationRef.current += 1;
      ref.current.value = "";
      ref.current.style.height = "auto";
      setDraft("");
      onDraftChange?.("");
      setAttachments([]);
      setDraftSelected(false);
      setSelectedMcp([]);
      setPlusOpen(false);
      setSlash(null);
      setMention(null);
      setCreatingSkill(false);
      setCreateError(null);
      syncHasValue("", []);
      return;
    }
    const folderCommand = consumeSessionFolderCommand(value);
    const btwCommand = consumeBtwCommand(value);
    if (
      btwCommand.matched &&
      onBtwCommand &&
      attachmentsRef.current.length === 0 &&
      !noteCard
    ) {
      const accepted = onBtwCommand(btwCommand.text);
      if (accepted === false) return;
      pasteGenerationRef.current += 1;
      if (ref.current) {
        ref.current.value = "";
        ref.current.style.height = "auto";
      }
      setDraft("");
      onDraftChange?.("");
      setPlusOpen(false);
      setSlash(null);
      setMention(null);
      setCreatingSkill(false);
      setCreateError(null);
      syncHasValue("", []);
      return;
    }
    if (folderCommand.matched && onPlaceInFolder && !sessionFolderSelected) {
      openSessionFolderPicker();
      return;
    }

    if (isCompactCommand(value)) {
      if (!onCompactContext?.()) return;
      if (!ref.current) return;
      pasteGenerationRef.current += 1;
      ref.current.value = "";
      ref.current.style.height = "auto";
      setDraft("");
      onDraftChange?.("");
      setPlusOpen(false);
      setSlash(null);
      setMention(null);
      setCreatingSkill(false);
      setCreateError(null);
      syncHasValue("", attachmentsRef.current);
      return;
    }

    const text = folderCommand.matched && sessionFolderSelected ? folderCommand.text : value;
    const submittedText =
      operatorSelected && !consumeOperatorCommand(text).matched
        ? `/operator ${text}`
        : text;
    const files = attachmentsRef.current;
    if (!text && files.length === 0 && !noteCard) return;
    // Clear the parent draft before onSubmit. The app can synchronously remount
    // the composer when the first message leaves an empty session (EmptySession →
    // docked layout). If draftRef still holds the sent text, the new instance
    // resurrects it as initialDraft.
    const resendDraftRevision = draftRevisionRef.current;
    const resendBorrowedAttachmentIds = new Set(
      borrowedAttachmentIdsRef.current,
    );
    const resendSelectedMcp = selectedMcp;
    onDraftChange?.("");
    const accepted = onSubmit(
      mcpContextText(
        taggedMcpServers(submittedText, selectedMcp),
        submittedText,
      ),
      files,
      {
        ...(resendEdited
          ? {
              resendEdited: true,
              onResendRejected: ({ providerRewound }) => {
                if (draftRevisionRef.current !== resendDraftRevision) return;
                restoreDraft(text, files, resendBorrowedAttachmentIds);
                setSelectedMcp(resendSelectedMcp);
                setResendEdited(!providerRewound);
                onEditingLastTurnChange?.(!providerRewound);
              },
            }
          : {}),
      },
    );
    // Preserve the draft when the application rejects a turn before acceptance.
    if (accepted === false) {
      restoreDraft(text, files);
      return;
    }
    pasteGenerationRef.current += 1;
    if (ref.current) {
      ref.current.value = "";
      ref.current.style.height = "auto";
    }
    setDraft("");
    onDraftChange?.("");
    borrowedAttachmentIdsRef.current.clear();
    attachmentsRef.current = [];
    setAttachments([]);
    setSelectedMcp([]);
    setResendEdited(false);
    onEditingLastTurnChange?.(false);

    setOperatorSelected(false);

    setSessionFolderSelected(false);
    setSessionFolderOpen(false);
    setPlusOpen(false);
    setSlash(null);
    setMention(null);
    setCreatingSkill(false);
    setCreateError(null);
    setPasteError(null);
    syncHasValue("", []);
  };
  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (disabled) return;
    if (isImeComposition(e.nativeEvent)) return;
    if (creatingSkill) return;
    if (
      e.key === "Enter" &&
      !e.shiftKey &&
      consumeBtwCommand(e.currentTarget.value).matched
    ) {
      e.preventDefault();
      submit(e.currentTarget.value);
      return;
    }

    if (
      e.key === " " &&
      runsSessionFolderCommandOnSpace({
        text: e.currentTarget.value,
        selectionStart: e.currentTarget.selectionStart,
        selectionEnd: e.currentTarget.selectionEnd,
        altKey: e.altKey,
        ctrlKey: e.ctrlKey,
        metaKey: e.metaKey,
      })
    ) {
      e.preventDefault();
      openSessionFolderPicker();
      return;
    }

    if (mentionOpen) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (rankedFiles.length === 0) return;
        setMentionActive((index) => (index + 1) % rankedFiles.length);
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        if (rankedFiles.length === 0) return;
        setMentionActive(
          (index) => (index - 1 + rankedFiles.length) % rankedFiles.length,
        );
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        setMention(null);
        return;
      }
      if (e.key === "Tab") {
        e.preventDefault();
        const file = rankedFiles[mentionActive];
        if (file) pickMention(file);
        return;
      }
      if (e.key === "Enter" && !e.shiftKey) {
        const file = rankedFiles[mentionActive];
        if (file) {
          e.preventDefault();
          pickMention(file);
          return;
        }
        setMention(null);
      }
    }

    if (
      e.key === "Enter" &&
      !e.shiftKey &&
      (isCompactCommand(e.currentTarget.value) ||
        isMcpCommand(e.currentTarget.value) ||
        isSessionFolderCommand(e.currentTarget.value))
    ) {
      e.preventDefault();
      submit(e.currentTarget.value);
      return;
    }

    if (slash) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (rankedSkills.length === 0) return;
        setSkillActive((index) => (index + 1) % rankedSkills.length);
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        if (rankedSkills.length === 0) return;
        setSkillActive(
          (index) => (index - 1 + rankedSkills.length) % rankedSkills.length,
        );
        return;
      }
      if (e.key === "Escape") {
        e.preventDefault();
        setSlash(null);
        return;
      }
      if (e.key === "Tab") {
        e.preventDefault();
        const skill = rankedSkills[skillActive];
        if (skill) pickSkill(skill);
        return;
      }
      if (e.key === "Enter" && !e.shiftKey) {
        const skill = rankedSkills[skillActive];
        if (skill) {
          e.preventDefault();
          pickSkill(skill);
          return;
        }
        if (!slash.query) {
          e.preventDefault();
          return;
        }
        setSlash(null);
      }
    }

    if (
      e.key === "ArrowUp" &&
      editLastTurnSupported &&
      navigationEmpty &&
      e.currentTarget.selectionStart === 0 &&
      e.currentTarget.selectionEnd === 0
    ) {
      e.preventDefault();
      recallLastTurn();
      return;
    }

    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit(e.currentTarget.value);
    }
  };



  const onPaste = (e: ClipboardEvent<HTMLTextAreaElement>) => {
    setPasteError(null);
    const messageFiles = messageFilesFromClipboard(e.clipboardData);
    if (messageFiles) {
      e.preventDefault();
      const generation = pasteGenerationRef.current;
      const captured = captureDraft(e.currentTarget);
      const text = e.clipboardData.getData("text/plain");
      if (captured) insertRestoredText(captured, text);
      if (!attachmentsSupported) return;
      rememberAttachmentRead(
        attachmentsFromFiles(messageFiles).then((pasted) => {
          if (pasteGenerationRef.current !== generation) {
            pasted.forEach(revokeAttachment);
            return;
          }
          addAttachments(pasted);
        }),
      );
      return;
    }
    const files = filesFromClipboard(e.clipboardData);
    if (files.length === 0) {
      // A webview reports a paste as text only, so a screenshot or a file
      // copied in a file manager arrives with nothing to attach; both live on
      // the native clipboard.
      if (!attachmentsSupported) return;
      const text = e.clipboardData.getData("text/plain");
      // Prose and whitespace alike are the webview's to insert.
      if (text && !isFileReferenceText(text)) return;
      // A file URI becomes a chip, so it is kept out of the draft; with no text
      // at all the paste carried an image the webview cannot see.
      e.preventDefault();
      // Captured before the read crosses an IPC hop. Send and draft reset bump
      // the generation, so a finished read cannot attach onto a draft that is gone.
      const generation = pasteGenerationRef.current;
      const captured = isFileReferenceText(text)
        ? captureDraft(e.currentTarget)
        : null;
      rememberAttachmentRead(
        nativeClipboardAttachments(text)
          .then(({ files: pasted, warning }) => {
            if (pasteGenerationRef.current !== generation) {
              pasted.forEach(revokeAttachment);
              return;
            }
            if (pasted.length) {
              // WebKit can insert the URI after preventDefault. The chip
              // replaces it, so the draft must not keep that text.
              if (captured) dropPastedText(captured, text);
              addAttachments(pasted);
            } else if (captured) insertRestoredText(captured, text);
            if (warning) setPasteError(warning);
          })
          .catch((reason: unknown) => {
            if (pasteGenerationRef.current !== generation) return;
            setPasteError(
              reason instanceof Error ? reason.message : String(reason),
            );
          }),
      );
      return;
    }
    e.preventDefault();
    if (!attachmentsSupported) return;
    const generation = pasteGenerationRef.current;
    rememberAttachmentRead(
      attachmentsFromFiles(files).then((pasted) => {
        if (pasteGenerationRef.current !== generation) {
          pasted.forEach(revokeAttachment);
          return;
        }
        addAttachments(pasted);
      }),
    );
  };

  const attachFromPicker = () => {
    if (!attachmentsSupported) return;
    void pickAttachments().then((files) => {
      addAttachments(files);
      ref.current?.focus();
    });
  };

  return (
    <div
      data-composer
      className={`relative shrink-0 ${shell || compact ? "" : "p-1.5 pt-0"}`}
      onMouseDown={disabled ? undefined : onFocus}
    >
      {question && onQuestionReply ? (
        <QuestionForm
          prompt={question}
          onReply={onQuestionReply}
          onInteraction={onQuestionInteraction}
        />
      ) : null}
      {children}
      {usageLimit ? (
        <UsageLimitNotice
          limit={usageLimit}
          onResume={onUsageLimitResume}
          onResumeAtReset={onUsageLimitResumeAtReset}
          onDismiss={onUsageLimitDismiss}
        />
      ) : null}
      <MessageQueue
        messages={queuedMessages}
        status={queueStatus}
        onDelete={onDeleteQueuedMessage}
        onEdit={onEditQueuedMessage}
        onEditingChange={onQueuedMessageEditingChange}
        onSteer={onSteerQueuedMessage}
        onResume={onResumeQueue}
      />
      <div className="relative overflow-visible">
        {mcpPickerOpen ? (
          <div className="absolute inset-x-0 bottom-full z-30 mb-1">
            <McpServerPicker
              connections={mcpConnections}
              harness={harness}
              claudeStatus={mcpStatus}
              loading={mcpLoading}
              error={mcpError}
              onPick={(server) => {
                const el = ref.current;
                if (!el) return;
                const previous = selectedMcp.find(
                  (item) =>
                    item.server.provider === server.provider &&
                    item.server.name === server.name &&
                    item.server.scope === server.scope &&
                    item.server.configPath === server.configPath,
                );
                const tag = previous ?? newMcpTag(server, selectedMcp);
                if (!previous) setSelectedMcp((current) => [...current, tag]);
                if (!previous || !taggedMcpServers(el.value, [tag]).length) {
                  const at = Math.min(
                    mcpInsertAt.current ?? el.selectionStart,
                    el.value.length,
                  );
                  const before = el.value.slice(0, at);
                  const after = el.value.slice(at);
                  const leading = before && !/\s$/.test(before) ? " " : "";
                  const trailing = after && /^\s/.test(after) ? "" : " ";
                  const insertion = `${leading}${tag.token}${trailing}`;
                  const next = before + insertion + after;
                  el.value = next;
                  resizeComposer(el);
                  el.setSelectionRange(
                    at + insertion.length,
                    at + insertion.length,
                  );
                  draftRevisionRef.current += 1;
                  setDraft(next);
                  syncHasValue(next, attachmentsRef.current);
                  setMention(null);
                }
                mcpInsertAt.current = null;
                setMcpPickerOpen(false);
                el.focus();
              }}
              onManage={() => {
                mcpInsertAt.current = null;
                setMcpPickerOpen(false);
                window.dispatchEvent(new Event("loci:open-mcp-settings"));
              }}
              onDismiss={(reason) => {
                mcpInsertAt.current = null;
                setMcpPickerOpen(false);
                if (reason === "escape") ref.current?.focus();
              }}
            />
          </div>
        ) : sessionFolderOpen ? (
          <div className="absolute inset-x-0 bottom-full z-30 mb-1">
            <SessionFolderPicker
              folders={sessionFolders}
              onPick={(target) => {
                setSessionFolderOpen(false);
                setSessionFolderSelected(true);
                onPlaceInFolder?.(target);
                const el = ref.current;
                if (!el) return;
                const cursor = el.selectionStart ?? el.value.length;
                if (/^\s*\/add-to-folder$/i.test(el.value)) {
                  el.value = `${el.value} `;
                  resizeComposer(el);
                  setDraft(el.value);
                  syncHasValue(el.value, attachmentsRef.current);
                  el.setSelectionRange(el.value.length, el.value.length);
                } else {
                  el.setSelectionRange(cursor, cursor);
                }
                requestAnimationFrame(() => el.focus());
              }}
              onDismiss={() => {
                setSessionFolderOpen(false);
                ref.current?.focus();
              }}
            />
          </div>
        ) : skillPickerOpen ? (
          <div className="absolute inset-x-0 bottom-full z-30 mb-1">
            <SkillPicker
              skills={rankedSkills}
              query={slash?.query ?? ""}
              active={skillActive}
              creating={creatingSkill}
              cwd={executionCwd}
              error={createError}
              busy={createBusy}
              onActive={setSkillActive}
              onPick={pickSkill}
              onStartCreate={() => {
                setCreatingSkill(true);
                setCreateError(null);
              }}
              onCancelCreate={() => {
                setCreatingSkill(false);
                setCreateError(null);
                const el = ref.current;
                if (el) syncTokensFromTextarea(el);
                el?.focus();
              }}
              onCreate={(name, scope) => {
                setCreateBusy(true);
                setCreateError(null);
                void createBlankSkill({ cwd: executionCwd, name, scope })
                  .then((path) => {
                    const el = ref.current;
                    const token = slashRef.current;
                    if (el && token) {
                      const rest = el.value.slice(token.end).replace(/^\s/, "");
                      const next = `${el.value.slice(0, token.start)}${rest}`;
                      el.value = next;
                      resizeComposer(el);
                      el.setSelectionRange(token.start, token.start);
                      setDraft(next);
                      syncHasValue(next, attachments);
                    }
                    setCreatingSkill(false);
                    setSlash(null);
                    setCreateError(null);
                    void skillCatalog
                      .refresh({ refresh: true })
                      .catch(() => undefined);
                    onOpenFile?.(path);
                    el?.focus();
                  })
                  .catch((err: unknown) => {
                    setCreateError(
                      err instanceof Error ? err.message : String(err),
                    );
                  })
                  .finally(() => setCreateBusy(false));
              }}
            />
          </div>
        ) : null}
        {mentionOpen && !pickerOpen ? (
          <div className="absolute inset-x-0 bottom-full z-30 mb-1">
            <NoteMentionPicker
              files={rankedFiles}
              query={mention?.query ?? ""}
              active={mentionActive}

              onActive={setMentionActive}
              onPick={pickMention}
            />
          </div>
        ) : null}
        <div
          ref={boxRef}
          data-composer-box
          data-composer-editing={resendEdited ? "" : undefined}
          className={`relative z-10 border bg-content/3 backdrop-blur-sm ${
            resendEdited
              ? "edit-last-turn-composer rounded-lg"
              : "rounded-lg border-content/10 has-focus:border-content/20"
          } ${
            fileDrag
              ? "border-accent/60"
              : resendEdited
                ? ""
                : "border-content/10 has-focus:border-content/20"
          }`}
        >
          {fileDrag ? (
            <div className="pointer-events-none absolute inset-0 z-20 grid place-items-center rounded-lg bg-accent/8 text-[12px] text-content/70">
              Drop files to attach
            </div>
          ) : null}
          {/* The row only holds the project picker, so it is gone when that is. */}
          {hideTopBar || hideProjectPicker ? null : (
            <div className="flex min-w-0 items-center gap-2.5 overflow-hidden px-3 pt-2.5">
              <CwdPicker
                cwd={cwd}
                recents={recents}
                projectLogoPath={projectLogoPath}
                enabled={enabled}
                onCwdChange={onCwdChange}

                onClose={() => ref.current?.focus()}
              />
            </div>
          )}

          {attachments.length > 0 ? (
            <div className="flex flex-wrap gap-1.5 px-3 pt-2">
              {attachments.map((file) => (
                <AttachmentChip
                  key={file.id}
                  attachment={file}
                  onRemove={() => removeAttachment(file.id)}
                />
              ))}
            </div>
          ) : null}

          {pasteError ? (
            <p role="alert" className="px-3 pt-2 text-xs text-red-400">
              {pasteError}
            </p>
          ) : null}



          {noteCard ? (
            <NoteMiniCard card={noteCard} onDismiss={onNoteCardDismiss} />
          ) : null}



          <div className="relative">
            <div
              ref={highlightRef}
              aria-hidden
              style={{ textIndent: modeIndent }}
              className={`composer-highlight pointer-events-none absolute inset-0 max-h-40 overflow-hidden whitespace-pre-wrap wrap-break-word px-3 text-sm leading-5.5 text-content font-sans ${
                shell ? "py-4" : "py-3"
              }`}
            >
              <ComposerHighlight
                text={draft}
                mode={leadingMode}
                names={skillNames}
                mentions={mentionIndex.labels}
                mcpTags={selectedMcp}
              />
            </div>
            <textarea
              ref={ref}
              data-composer-empty={navigationEmpty ? "true" : undefined}
              style={{ textIndent: modeIndent }}
              rows={2}
              spellCheck={false}
              defaultValue={initialDraft}
              placeholder={noteCard ? "Add a message, or send…" : (placeholder ?? "Ask, / for commands, @ for files, notes, drawings…")}
              aria-label={inputAriaLabel}
              disabled={disabled}
              className={`composer-field scrollbar-none relative max-h-52 w-full resize-none overflow-x-hidden whitespace-pre-wrap wrap-break-word bg-transparent px-3 text-sm leading-5.5 outline-none placeholder:overflow-hidden placeholder:text-ellipsis placeholder:whitespace-nowrap font-sans ${
                shell ? "py-4" : "py-3"
              }`}
              onFocus={onFocus}
              onKeyDown={onKeyDown}
              onPaste={onPaste}
              onScroll={(e) => syncHighlightScroll(e.currentTarget)}
              onClick={(e) => syncTokensFromTextarea(e.currentTarget)}
              onKeyUp={(e) => syncTokensFromTextarea(e.currentTarget)}
              onSelect={(e) => syncTokensFromTextarea(e.currentTarget)}
              onInput={(e) => {
                const el = e.currentTarget;
                if (enterBtwFromPrefix(el)) return;
                resizeComposer(el);
                draftRevisionRef.current += 1;
                setDraft(el.value);
                setSelectedMcp((current) => {
                  const retained = current.filter(
                    (tag) => taggedMcpServers(el.value, [tag]).length > 0,
                  );
                  return retained.length === current.length
                    ? current
                    : retained;
                });
                setPasteError(null);
                if (
                  sessionFolderSelected &&
                  !consumeSessionFolderCommand(el.value).matched
                ) {
                  setSessionFolderSelected(false);
                }
                syncHasValue(el.value, attachments);
                syncTokensFromTextarea(el);
              }}
            />
          </div>

          <div className="flex items-center gap-1 px-2 pb-2">
            <div
              ref={plusRef}
              className={compact ? "hidden" : "relative shrink-0"}
            >
              <ToolButton
                label="Add files or choose a mode"
                active={plusOpen}
                onClick={() => setPlusOpen((open) => !open)}
              >
                <Plus className="size-3.5" strokeWidth={1.5} />
              </ToolButton>
              {plusOpen ? (
                <Popover
                  anchor={plusRef}
                  side="top"
                  align="start"
                  width={250}
                  onDismiss={() => setPlusOpen(false)}
                  data-composer-plus
                  className="p-1.5"
                >
                  <p className="px-2 pb-1 pt-0.5 text-[10px] font-medium uppercase tracking-wide text-content/40">
                    Add to message
                  </p>
                  <button
                    type="button"
                    disabled={!attachmentsSupported}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => {
                      setPlusOpen(false);
                      attachFromPicker();
                    }}
                    className="flex w-full items-start gap-2.5 rounded-lg px-2 py-2 text-left text-content hover:bg-content/10 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    <FilePlus className="mt-0.5 size-4 shrink-0" />
                    <span className="min-w-0">
                      <span className="block text-[13px]">Upload file</span>
                      <span className="block truncate whitespace-nowrap text-[11px] leading-4 text-content/45">
                        {attachmentsSupported
                          ? "Attach files or images"
                          : `${HARNESS_TITLE[harness]} does not support attachments`}
                      </span>
                    </span>
                  </button>

                  {(
                    <button
                      type="button"
                      aria-pressed={operatorActive}
                      onMouseDown={(event) => event.preventDefault()}
                      onClick={() => {
                        setOperatorSelected(!operatorActive);
                        if (operatorActive) {
                          clearLeadingMode(OPERATOR_COMMAND.name);
                        }


                        setDraftSelected(false);
                        setPlusOpen(false);
                        ref.current?.focus();
                      }}
                      className="flex w-full items-start gap-2.5 rounded-lg px-2 py-2 text-left text-content hover:bg-content/10"
                    >
                      <CursorMagicSelection className="mt-0.5 size-4 shrink-0 text-sky-300/80" />
                      <span className="min-w-0 flex-1">
                        <span className="block text-[13px]">Operator</span>
                        <span className="block truncate whitespace-nowrap text-[11px] leading-4 text-content/45">
                          Give this thread access to Loci
                        </span>
                      </span>
                      {operatorActive ? (
                        <Check className="mt-0.5 size-3.5 shrink-0 text-sky-300/80" />
                      ) : null}
                    </button>
                  )}

                  {canSaveDraft && onSaveDraft ? (
                    <button
                      type="button"
                      aria-pressed={draftActive}
                      onMouseDown={(event) => event.preventDefault()}
                      onClick={() => {
                        setDraftSelected(!draftActive);
                        if (draftActive) clearLeadingMode(DRAFT_COMMAND.name);

                        setOperatorSelected(false);

                        setPlusOpen(false);
                        ref.current?.focus();
                      }}
                      className="flex w-full items-start gap-2.5 rounded-lg px-2 py-2 text-left text-content hover:bg-content/10"
                    >
                      <CircleDashed className="mt-0.5 size-4 shrink-0 text-content/60" />
                      <span className="min-w-0 flex-1">
                        <span className="block text-[13px]">Draft</span>
                        <span className="block truncate whitespace-nowrap text-[11px] leading-4 text-content/45">
                          Save this message without starting the agent
                        </span>
                      </span>
                      {draftActive ? (
                        <Check className="mt-0.5 size-3.5 shrink-0 text-accent" />
                      ) : null}
                    </button>
                  ) : null}
                </Popover>
              ) : null}
            </div>
            {!compact && operatorActive ? (
              <ModeCommandPill
                name={OPERATOR_COMMAND.name}
                onClear={() => {
                  setOperatorSelected(false);
                  clearLeadingMode(OPERATOR_COMMAND.name);
                  ref.current?.focus();
                }}
              />
            ) : null}


            {!compact && draftActive ? (
              <ModeCommandPill
                name={DRAFT_COMMAND.name}
                onClear={() => {
                  setDraftSelected(false);
                  clearLeadingMode(DRAFT_COMMAND.name);
                  ref.current?.focus();
                }}
              />
            ) : null}
            <div
              className="composer-toolbar flex min-w-0 flex-1 items-center"
              onWheel={(e) => {
                if (
                  e.target instanceof Element &&
                  e.target.closest(
                    "[data-model-picker], [data-model-control], [data-access-picker], [data-model-settings]",
                  )
                ) {
                  return;
                }
                const el = e.currentTarget;
                if (el.scrollWidth <= el.clientWidth) return;
                if (e.deltaX === 0 && e.deltaY !== 0) el.scrollLeft += e.deltaY;
              }}
            >
              <div className="flex shrink-0 items-center gap-1">
                <ModelPicker
                  harness={harness}
                  model={model}
                  values={modelSettings}
                  allowedHarnesses={allowedModelHarnesses}
                  project={cwd}
                  hideSettings={controlsBeside}
                  hotkeys={hotkeys && enabled}
                  onChange={onModelChange}
                  onSettingsChange={(settings) =>
                    onModelSettingsChange?.(settings)
                  }
                  onClose={() => ref.current?.focus()}
                />
                {controlsBeside ? (
                  <ModelControlPills
                    harness={harness}
                    model={model}
                    values={modelSettings}
                    onSettingsChange={(settings) =>
                      onModelSettingsChange?.(settings)
                    }
                    onClose={() => ref.current?.focus()}
                  />
                ) : null}
                {!compact ? (
                  <AccessPicker
                    value={runtimeMode}
                    busy={busy}
                    onChange={onRuntimeModeChange}
                    onClose={() => ref.current?.focus()}
                  />
                ) : null}
                {/* The context gauge sits with the controls it relates to. */}
                <div className="ml-1 flex shrink-0 items-center" data-context-meter-slot>
                  <ContextMeter
                    usage={context}
                    onCompact={compactSupported ? onCompactContext : undefined}
                    compactDisabled={busy}
                    detailed={!compact}
                  />
                </div>
              </div>
            </div>

            {resendEdited ? (
              <button
                type="button"
                title="Stop editing last message"
                aria-label="Stop editing last message"
                onMouseDown={(event) => event.preventDefault()}
                onClick={exitEditMode}
                className="edit-last-turn-button flex h-6.5 shrink-0 items-center gap-1 rounded-md border border-current/20 px-2 text-[11px] font-medium transition-[background-color,color,border-color] hover:border-current/35 hover:bg-content/15 hover:text-content focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-accent"
              >
                <X className="size-3" strokeWidth={1.8} />
                <span>Cancel edit</span>
              </button>
            ) : null}
            <div className="flex shrink-0 items-center gap-1">
              <ComposerAction
                busy={busy}
                disabled={disabled}
                hasValue={hasValue}
                allowBusySubmit={allowBusySubmit}
                label={draftActive ? "Save draft" : "Send"}
                onSend={() => submit(ref.current?.value ?? "")}
                onStop={() => onStop?.()}
              />
            </div>
          </div>
        </div>
        {runnerLive && runnerEnabled ? (
          <ComposerRunner boxRef={boxRef} cwd={cwd} busy={busy} enabled={enabled} onExited={() => setRunnerLive(false)} />
        ) : null}
      </div>
    </div>
  );
}

function ComposerHighlight({
  text,
  mode,
  names,
  mentions,
  mcpTags,
}: {
  text: string;
  mode: ModeCommandToken | null;
  names: ReadonlySet<string>;
  mentions: ReadonlyMap<string, ProjectFile>;
  mcpTags: McpTag[];
}) {
  const rest = mode ? text.slice(mode.end) : text;
  const parts = skillTextParts(rest, names);
  return (
    <>
      {mode ? <ModeCommandText text={text} mode={mode} /> : null}
      {parts.map((part, index) =>
        part.skill ? (
          <span key={index} className="text-skill">
            {part.text}
          </span>
        ) : (
          // Skill tokens always end on whitespace, so each remaining run still
          // starts on a boundary `@mention` matching can rely on.
          <MentionRuns
            key={index}
            text={part.text}
            mentions={mentions}
            mcpTags={mcpTags}
          />
        ),
      )}
      {text.endsWith("\n") ? "\n" : null}
    </>
  );
}

function MentionRuns({
  text,
  mentions,
  mcpTags,
}: {
  text: string;
  mentions: ReadonlyMap<string, ProjectFile>;
  mcpTags: McpTag[];
}) {
  return (
    <>
      {mcpTagParts(text, mcpTags).map((part, index) =>
        part.tag ? (
          <span
            key={index}
            className="text-mention"
            data-mcp-tag={part.tag.token}
          >
            {part.text}
          </span>
        ) : (
          <FileMentionRuns key={index} text={part.text} mentions={mentions} />
        ),
      )}
    </>
  );
}

function FileMentionRuns({
  text,
  mentions,
}: {
  text: string;
  mentions: ReadonlyMap<string, ProjectFile>;
}) {
  const parts = fileMentionParts(text, mentions);
  return (
    <>
      {parts.map((part, index) =>
        part.file ? (
          <span key={index} className="text-mention">
            {/* The `@` keeps its width so the textarea underneath stays in
                lockstep; the file icon sits on top of it. */}
            <span className="relative text-transparent">
              {"@"}
              {/* `indent-0`: a leading mode command indents the first line,
                  and this box would otherwise inherit that indent. */}
              {/* The `@` is transparent so the icon can sit on it, and a glyph
                  drawn in `currentColor` would inherit that: give it the mention
                  colour back. */}
              <span className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 indent-0 text-mention">
                {mentionKind(part.file.path) === "note" ? (
                  <StickyNote className="size-3.5" strokeWidth={1.75} />
                ) : mentionKind(part.file.path) === "canvas" ? (
                  <ExcalidrawIcon className="size-3.5" strokeWidth={1.75} />
                ) : (
                  <FileTypeIcon
                    name={part.file.name}
                    isDir={Boolean(part.file.isDir)}
                    size={13}
                  />
                )}
              </span>
            </span>
            {part.text.slice(1)}
          </span>
        ) : (
          part.text
        ),
      )}
    </>
  );
}

export function ComposerAction({
  busy,
  disabled = false,
  hasValue,
  allowBusySubmit = true,
  label = "Send",
  onSend,
  onStop,
}: {
  busy: boolean;
  disabled?: boolean;
  hasValue: boolean;
  allowBusySubmit?: boolean;
  label?: string;
  onSend: () => void;
  onStop: () => void;
}) {
  if (disabled) {
    return (
      <button
        type="button"
        title={label}
        aria-label={label}
        disabled
        className="composer-send primary-action grid size-6.5 place-items-center rounded-md disabled:cursor-default"
      >
        <ArrowUp className="size-3.5" strokeWidth={2.25} />
      </button>
    );
  }
  if (busy) {
    return hasValue && allowBusySubmit ? (
      <button
        type="button"
        title={label}
        aria-label={label}
        onClick={onSend}
        className="composer-send primary-action grid size-6.5 place-items-center rounded-md"
      >
        <ArrowUp className="size-3.5" strokeWidth={2.25} />
      </button>
    ) : (
      <button
        type="button"
        title="Stop"
        aria-label="Stop"
        onClick={onStop}
        className="grid size-6.5 place-items-center rounded-md bg-white text-black hover:bg-white/90"
      >
        <Square className="size-2.5 fill-current" strokeWidth={0} />
      </button>
    );
  }

  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={!hasValue}
      onClick={onSend}
      className="composer-send primary-action grid size-6.5 place-items-center rounded-md disabled:cursor-default"
    >
      <ArrowUp className="size-3.5" strokeWidth={2.25} />
    </button>
  );
}

function hasFiles(data: DataTransfer | null): data is DataTransfer {
  if (!data) return false;
  return (
    data.files.length > 0 ||
    [...data.types].some(
      (type) => type === "Files" || type === "application/x-moz-file",
    ) ||
    Array.from(data.items ?? []).some((item) => item.kind === "file")
  );
}
