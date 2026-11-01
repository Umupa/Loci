import { agentLook, agentState, AGENT_COLORS, updateAgent, type Agent } from "../../features/agents/model/agent";
import { markAgentAccessMigrated } from "../../features/agents/model/agentAccess";
import { AGENT_AVATARS } from "../../features/agents/model/agentAvatars";
import { setAgentWorkdir } from "../../features/agents/model/agentWorkdir";
import { AGENT_TEMPLATES } from "../../features/agents/templates";
import { isHarnessAvailable } from "../../integrations/harness/core/availability";
import { modelEffortSetting, modelsFor, preferredModelId, resolveModel } from "../../features/sessions/model/models";
import { HARNESSES, RUNTIME_MODES, type Block, type HarnessId, type RuntimeMode, type Session } from "../../features/sessions/model/session";
import { RELEASE_IDENTIFIER } from "../../features/updates/model/updates";
import type { CommandContext } from "./context";
import { mentorField, resolveMentor } from "./mentor";
import { CommandError, field, type CommandDefinition, type CommandMeta } from "./registry";

/** Names people use for a provider, beside Loci's own ids. */
const PROVIDER_ALIASES: Record<string, HarnessId> = { agy: "antigravity", "claude-code": "claude", "cursor-agent": "cursor" };

export function providerId(value: string): HarnessId {
  const wanted = value.trim().toLowerCase();
  const id = (PROVIDER_ALIASES[wanted] ?? wanted) as HarnessId;
  if (!HARNESSES.includes(id)) throw new CommandError(`Unknown provider ${value}. Providers: ${HARNESSES.join(", ")}`, "usage");
  return id;
}

const settingsFields = [
  field("name", "string", "Its name", { max: 40 }),
  field("role", "string", "Its job in a few words", { max: 60 }),
  field("avatar", "string", "A face by name (see the mentor settings)", { max: 40 }),
  field("color", "string", "One of the mentor colors", { max: 40 }),
  field("workdir", "string", "Its working folder (created when missing)", { max: 4096 }),
  field("provider", "string", `The agent CLI: ${HARNESSES.join(", ")} (agy for antigravity)`),
  field("model", "string", "A model id from `loci models list`"),
  field("effort", "string", "The model's effort setting"),
  field("mode", "string", `Permissions: ${RUNTIME_MODES.join(", ")}`),
];

type Settings = Partial<Record<"name" | "role" | "avatar" | "color" | "workdir" | "provider" | "model" | "effort" | "mode", string>>;

/** Applies settings through the functions the mentor's settings and composer use. */
async function applySettings(ctx: CommandContext, agent: Agent, settings: Settings): Promise<void> {
  const avatar = settings.avatar?.trim();
  if (avatar && !AGENT_AVATARS.some((face) => face.name === avatar)) throw new CommandError(`Unknown avatar ${avatar}`, "usage");
  const color = settings.color?.trim();
  if (color && !AGENT_COLORS.includes(color as (typeof AGENT_COLORS)[number])) throw new CommandError(`color must be one of: ${AGENT_COLORS.join(", ")}`, "usage");
  const mode = settings.mode?.trim();
  if (mode && !RUNTIME_MODES.includes(mode as RuntimeMode)) throw new CommandError(`mode must be one of: ${RUNTIME_MODES.join(", ")}`, "usage");
  const harness = settings.provider ? providerId(settings.provider) : undefined;
  if (harness && !isHarnessAvailable(harness)) throw new CommandError(`${harness} is not installed or not found by Loci`);

  const look = {
    ...(settings.name !== undefined ? { name: settings.name.replace(/\s+/g, " ").trim() } : {}),
    ...(settings.role !== undefined ? { role: settings.role.replace(/\s+/g, " ").trim() } : {}),
    ...(avatar ? { avatar } : {}),
    ...(color ? { color } : {}),
  };
  if (Object.keys(look).length) updateAgent(agent.id, (current) => ({ ...current, ...look }));
  if (settings.workdir !== undefined) {
    try { await setAgentWorkdir(agent.id, settings.workdir); } catch (error) { throw new CommandError(`workdir: ${error instanceof Error ? error.message : String(error)}`); }
  }
  if (!harness && !settings.model && !settings.effort && !mode) return;
  const chat = await ctx.agentChat(agent.id);
  if (chat.busy) throw new CommandError("The mentor is busy; change its model or permissions when it is idle", "busy");
  if (harness || settings.model) {
    const target = harness ?? chat.harness;
    // A CLI-only model name (grok's custom models, say) is known once the
    // provider's catalog has been read; the picker would have done this on open.
    await ctx.refreshModels([target]);
    const model = settings.model
      ? modelsFor(target).find((entry) => entry.id === settings.model)
      : resolveModel(target, target === chat.harness ? chat.model : preferredModelId(target));
    if (!model || model.harness !== target) throw new CommandError(`Unknown model for ${target}; run \`loci models list\``, "usage");
    if (target !== chat.harness || model.id !== chat.model) ctx.submission.changeModel(chat.id, target, model.id);
  }
  if (settings.effort) {
    const current = ctx.liveSession(chat.id) ?? chat;
    const model = resolveModel(current.harness, current.model);
    const effort = modelEffortSetting(model);
    if (!effort) throw new CommandError(`${model.id} has no effort setting`, "usage");
    if (!effort.options.some((option) => option.value === settings.effort))
      throw new CommandError(`effort must be one of: ${effort.options.map((option) => option.value).join(", ")}`, "usage");
    ctx.submission.changeModelSettings(chat.id, { ...current.modelSettings, [effort.id]: settings.effort });
  }
  if (mode) {
    ctx.submission.changeRuntimeMode(chat.id, mode as RuntimeMode);
    // As choosing in the mentor's settings does: this is its access from now on.
    markAgentAccessMigrated(agent.id);
  }
  await ctx.flushPersistence();
}

/** What a mentor is, for a terminal. */
function mentorView(ctx: CommandContext, agent: Agent, chat?: Session) {
  const look = agentLook(agent);
  const reading = ctx.reader.current(agent.id);
  return {
    id: agent.id,
    name: look.name,
    ...(agent.role ? { role: agent.role } : {}),
    avatar: agent.avatar,
    color: agent.color,
    ...(agent.workdir ? { workdir: agent.workdir } : {}),
    folders: agent.projects,
    active: ctx.activeAgentId() === agent.id,
    ...(agent.sessionId ? { sessionId: agent.sessionId } : {}),
    ...(chat ? {
      provider: chat.harness,
      model: chat.model,
      modelSettings: chat.modelSettings,
      mode: chat.runtimeMode,
      status: agentState(chat).status,
    } : {}),
    ...(reading.page ? { reading: readingView(reading) } : {}),
  };
}

export function readingView({ page, lesson }: ReturnType<CommandContext["reader"]["current"]>) {
  if (!page) return { kind: "none" };
  switch (page.kind) {
    case "course": return { kind: "course", id: page.course.courseId, title: page.course.title, ...(lesson ? { lesson } : page.course.itemId ? { lesson: { id: page.course.itemId } } : {}) };
    case "document": return { kind: "source", id: page.document.id, title: page.document.title };
    case "file": return { kind: "file", path: page.path };
    default: return { kind: page.kind, id: page.id };
  }
}

/** --yes is honoured away from the installed app; there Loci still asks. */
async function confirmed(ctx: CommandContext, input: Record<string, unknown>): Promise<boolean> {
  return input.yes === true && (await ctx.identifier()) !== RELEASE_IDENTIFIER;
}

/** The turn a terminal started, found by the request that started it. */
export function turnState(chat: Session, turn: string) {
  const at = chat.blocks.findIndex((block) => block.role === "user" && block.appRequestId === turn);
  if (at < 0) throw new CommandError("No such turn in this mentor's conversation (it may have been reset or archived)", "not_found");
  const user = chat.blocks[at];
  const next = chat.blocks.findIndex((block, index) => index > at && block.role === "user" && !block.draft);
  const after = chat.blocks.slice(at + 1, next < 0 ? undefined : next);
  const text = after.filter((block) => block.role === "assistant").map((block) => block.text.trim()).filter(Boolean).join("\n\n");
  // A provider's error is a system block marked as one; status lines are not errors.
  const lastSystem = [...after].reverse().find((block: Block) => block.role === "system" && block.notice === "error")?.text;
  const base = { sessionId: chat.id, turn, text };
  if (user.draft) return { ...base, status: "queued" as const };
  const finished = user.durationMs != null || next >= 0;
  if (!finished && chat.busy) return { ...base, status: agentState(chat).status === "needs-you" ? "needs-you" as const : "running" as const };
  if (!finished && user.startedAt == null) return { ...base, status: "queued" as const };
  if (!text && lastSystem) return { ...base, status: "failed" as const, error: lastSystem };
  return { ...base, status: "done" as const };
}

const yes = field("yes", "boolean", "Do not ask (Loci Dev and QA builds only)");

export const mentorCommands: CommandDefinition<CommandContext>[] = [
  {
    name: "mentors.list",
    summary: "Every mentor, in rail order.",
    fields: [],
    callers: ["external"],
    run: async (ctx) => ({
      mentors: ctx.agents().map((agent) => mentorView(ctx, agent, agent.sessionId ? ctx.liveSession(agent.sessionId) : undefined)),
    }),
  },
  {
    name: "mentors.show",
    summary: "One mentor: identity, provider, model, permissions, status and what its reader shows.",
    fields: [mentorField(true)],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const chat = await ctx.agentChat(agent.id);
      return mentorView(ctx, resolveMentor(ctx, agent.id, meta), chat);
    },
  },
  {
    name: "mentors.create",
    summary: "Add a mentor, from a template or blank. It does not start a model.",
    fields: [
      field("template", "string", "A template id from `loci templates list` (blank when left out)"),
      ...settingsFields,
      field("switch", "boolean", "Show it in the window"),
    ],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const template = input.template === undefined ? undefined : AGENT_TEMPLATES.find((entry) => entry.id === input.template);
      if (input.template !== undefined && !template)
        throw new CommandError(`Unknown template ${String(input.template)}. Templates: ${AGENT_TEMPLATES.map((entry) => entry.id).join(", ")}`, "usage");
      if (input.provider !== undefined) providerId(input.provider as string);
      const id = await ctx.createAgent(template);
      const { template: _template, switch: show, ...settings } = input;
      const agent = resolveMentor(ctx, id, meta);
      await applySettings(ctx, agent, settings as Settings);
      if (show === true) await ctx.switchAgent(id);
      const chat = await ctx.agentChat(id);
      return { ...mentorView(ctx, resolveMentor(ctx, id, meta), ctx.liveSession(chat.id) ?? chat), created: true };
    },
  },
  {
    name: "mentors.update",
    summary: "Change a mentor's name, role, face, working folder, provider, model, effort or permissions.",
    fields: [mentorField(true), ...settingsFields],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const { mentor, ...settings } = input;
      const agent = resolveMentor(ctx, mentor, meta);
      await applySettings(ctx, agent, settings as Settings);
      const chat = await ctx.agentChat(agent.id);
      return { ...mentorView(ctx, resolveMentor(ctx, agent.id, meta), ctx.liveSession(chat.id) ?? chat), saved: true };
    },
  },
  {
    name: "mentors.delete",
    summary: "Delete a mentor, its conversation, documents and courses. Its soul and memory files stay on disk.",
    fields: [mentorField(true), yes],
    callers: ["external"],
    destructive: true,
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      if (!await ctx.removeAgent(agent.id, await confirmed(ctx, input))) throw new CommandError("Not deleted: the question was declined", "declined");
      return { id: agent.id, deleted: true };
    },
  },
  {
    name: "mentors.reset",
    summary: "Clear a mentor's conversation; its soul, memory and library stay.",
    fields: [mentorField(true), yes],
    callers: ["external"],
    destructive: true,
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      await ctx.agentChat(agent.id);
      if (!await ctx.resetAgent(agent.id, await confirmed(ctx, input))) throw new CommandError("Not reset: the question was declined", "declined");
      return { id: agent.id, reset: true };
    },
  },
  {
    name: "mentors.switch",
    summary: "Show a mentor in the window, as choosing it on the rail does.",
    fields: [mentorField(true)],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      if (!await ctx.switchAgent(agent.id)) throw new CommandError("The window stayed where it was (unsaved edits in the reader?)");
      return { id: agent.id, active: true };
    },
  },
  {
    name: "mentors.send",
    summary: "Send a message to a mentor, as typing it in its conversation does. Returns the turn to follow.",
    fields: [mentorField(true), field("text", "string", "The message (or --text-file)", { required: true, positional: true, max: 240_000 })],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const chat = await ctx.agentChat(agent.id);
      const turn = `cli-${meta.requestId}`;
      const live = ctx.liveSession(chat.id) ?? chat;
      if (live.blocks.some((block) => block.appRequestId === turn)) return { mentor: agent.id, sessionId: chat.id, turn, alreadySent: true };
      if (live.busy) throw new CommandError("The mentor is busy; wait for its turn to end", "busy");
      if (!await ctx.submission.submit(chat.id, input.text as string, [], { appRequestId: turn }))
        throw new CommandError("The mentor's conversation did not accept the message (a draft is waiting in it?)", "busy");
      await ctx.flushPersistence();
      return { mentor: agent.id, sessionId: chat.id, turn };
    },
  },
  {
    name: "mentors.turn",
    summary: "Where a turn started by `mentors send` is: queued, running, needs-you, done or failed, with the reply so far.",
    fields: [mentorField(true), field("turn", "string", "The turn id `mentors send` returned", { required: true, positional: true })],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const live = agent.sessionId ? ctx.liveSession(agent.sessionId) : undefined;
      return { mentor: agent.id, ...turnState(live ?? await ctx.agentChat(agent.id), input.turn as string) };
    },
  },
  {
    name: "mentors.read",
    summary: "Recent exchanges of a mentor's conversation, newest page first.",
    fields: [
      mentorField(true),
      field("before", "string", "nextBefore from an earlier page"),
      field("limit", "integer", "Exchanges, up to 3"),
      field("maxChars", "integer", "Characters per message (200-6000)"),
    ],
    callers: ["external"],
    run: async (ctx, input, meta: CommandMeta) => {
      const { mentor, ...options } = input;
      const agent = resolveMentor(ctx, mentor, meta);
      const chat = await ctx.agentChat(agent.id);
      return ctx.agentApp(chat, meta.requestId, "sessions.read", { sessionId: chat.id, ...options });
    },
  },
  {
    name: "mentors.stop",
    summary: "Stop the mentor's current turn.",
    fields: [mentorField(true)],
    callers: ["external"],
    run: async (ctx, input, meta) => {
      const agent = resolveMentor(ctx, input.mentor, meta);
      const chat = await ctx.agentChat(agent.id);
      await ctx.submission.stopSessionWork(chat.id);
      return { id: agent.id, stopped: true };
    },
  },
];
