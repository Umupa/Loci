import type { Block, Session } from "../../sessions/model/session";
import { agentLook, type Agent } from "./agent";
import {
  AGENT_PROMPT_VERSION,
  agentContext,
  loadAgentFiles,
  needsAppContextReset,
  planAgentContext,
  recordAgentContext,
  recordAppContext,
} from "./agentFiles";
import { readingLesson, takeReadingContext, type SharedReading } from "./agentReading";
import { effectiveLearningLanguage, languageContext } from "./learningLanguage";
import { ensureAgentWorkdir } from "./agentWorkdir";
import {
  loadAgentRotation,
  planRotation,
  rotationReason,
  saveAgentRotation,
} from "./agentRotation";

export type AppTurnContext = {
  /** What the app puts ahead of the user's message this turn. */
  context: string[];
  /** Whether this turn tells a fresh provider session who it is. */
  introduces: boolean;
  /** The provider session must be dropped before sending. */
  rotates: boolean;
  /** A previous attempt created a fresh provider but did not finish sending its context. */
  recovering: boolean;
  /** The lesson open beside the chat, which this message is asked on. */
  lesson?: { courseId: string; lessonId: string };
  /** Call once the provider session is fresh, so the next rotation starts here. */
  commitRotation(): void;
  /** Call once the provider accepted the turn, with the session it ran in. */
  record(providerSessionId: string | undefined): void;
};

/**
 * Agent sessions carry the soul once and memory again when it changes, and
 * rotate when their context is nearly full. All sessions carrying the removed
 * global policy are replaced once using the same transcript-excerpt path.
 */
export async function prepareAppTurn(
  agent: Agent | undefined,
  session: Pick<Session, "id" | "providerSessionId" | "context" | "blocks">,
  /** `reading`: what another device's reader shows, when the message came from there. */
  options: { canRotate: boolean; now?: number; reading?: SharedReading | null },
): Promise<AppTurnContext> {
  const previous = loadAgentRotation(session.id);
  const pending = previous?.pending;
  const recovering = !!pending &&
    (!session.providerSessionId || session.providerSessionId !== pending.replacedProvider);
  const reset = needsAppContextReset(session.id, session.providerSessionId);
  const reason = options.canRotate && !recovering
    ? (agent ? rotationReason(session) : undefined) ?? (reset ? "policy" : undefined)
    : undefined;
  const rotation = reason
    ? planRotation(
        session.blocks,
        previous,
        reason,
        options.now ?? Date.now(),
      )
    : undefined;
  // A turn must not fail over its memory or its folder; it goes without, and
  // tries again next time.
  const workdir = agent
    ? await ensureAgentWorkdir(agent.id).catch(() => agent.workdir)
    : undefined;
  const look = agent && agentLook(workdir ? { ...agent, workdir } : agent);
  const files = agent
    ? await loadAgentFiles(agent.id).catch(() => undefined)
    : undefined;
  // Identity and folders are refreshed with the soul when they change.
  const handed = files && look && {
    ...files,
    soulHash: `${files.soulHash}:${look.name}:${look.role ?? ""}:${look.workdir ?? ""}:${AGENT_PROMPT_VERSION}`,
  };
  const plan = handed
    ? planAgentContext(
        session.id,
        rotation || recovering ? undefined : session.providerSessionId,
        handed,
      )
    : undefined;
  const context: string[] = [];
  const brief = rotation || recovering
    ? pending?.brief ?? rotation?.brief(session.id)
    : undefined;
  if (brief) context.push(brief);
  if (brief && pending && previous) {
    // Preserve the original snapshot and the task whose failed send followed
    // it, so a later user message of only "retry" still has its request.
    const after = session.blocks.findIndex((block) => block.id === previous.afterBlockId);
    const tail = session.blocks.slice(after + 1);
    if (tail.length)
      context.push(planRotation(tail, undefined, "policy", options.now ?? Date.now()).brief(session.id));
  }
  if (files && look && plan && (plan.soul || plan.memory))
    context.push(agentContext(look, files, plan));
  // The learning language goes every turn: a change applies at once, and it
  // outranks the "reply in the learner's language" of an older Soul.
  const language = agent ? languageContext(effectiveLearningLanguage(agent.language)) : undefined;
  if (language) context.push(language);
  // The local time goes every turn too, so dates in memory and replies are right,
  // with how long the learner was away since their last message.
  if (agent) context.push(localTimeContext(options.now ?? Date.now()));
  const away = agent ? sinceLastMessageContext(session.blocks, options.now ?? Date.now()) : undefined;
  if (away) context.push(away);
  // What is open beside the chat changes from turn to turn, so it goes every time.
  // A selection the message already carries as a source is not sent twice, and
  // a page the user dismissed from the composer stays out of this turn only.
  const lastUser = [...session.blocks].reverse().find((block) => block.role === "user");
  const attached = lastUser?.sources?.map((source) => source.quote) ?? [];
  // The lesson this message is asked on, read before the reader's one-turn dismissal is spent.
  const lesson = agent ? readingLesson(agent.id, options.reading) : undefined;
  const reading = agent ? takeReadingContext(agent.id, attached, options.reading) : undefined;
  if (reading) context.push(reading);
  return {
    context,
    ...(lesson ? { lesson } : {}),
    introduces: !!plan?.soul,
    rotates: !!rotation,
    recovering,
    commitRotation: () => {
      if (rotation && brief)
        saveAgentRotation(session.id, {
          ...(previous?.pending ? previous : rotation.rotation),
          pending: { brief, replacedProvider: session.providerSessionId },
        });
    },
    record: (providerSessionId) => {
      // Editing must retain its provider history. Keep the old receipt until
      // that provider can be replaced, or a model switch returns a new one.
      if (
        reset &&
        !recovering &&
        !rotation &&
        (!providerSessionId || providerSessionId === session.providerSessionId)
      )
        return;
      const saved = loadAgentRotation(session.id);
      if (providerSessionId && providerSessionId === saved?.pending?.replacedProvider)
        return;
      if (handed) recordAgentContext(session.id, providerSessionId, handed);
      else recordAppContext(session.id, providerSessionId);
      if (saved?.pending)
        saveAgentRotation(session.id, { ...saved, pending: undefined });
    },
  };
}

/** The user's local date and time with its zone, e.g. 2026-11-04 21:30 (Asia/Shanghai, UTC+08:00). */
/** How long ago a moment was, in the largest whole unit: "3 days", "1 hour", "under a minute". */
export function elapsedPhrase(ms: number): string {
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 1) return "under a minute";
  const [count, unit] = minutes < 60 ? [minutes, "minute"] : minutes < 48 * 60 ? [Math.floor(minutes / 60), "hour"] : [Math.floor(minutes / (24 * 60)), "day"];
  return `${count} ${unit}${count === 1 ? "" : "s"}`;
}

/** The time since the learner's message before this one; nothing for a first message. */
export function sinceLastMessageContext(blocks: readonly Block[], now: number): string | undefined {
  const sent = blocks.filter((block) => block.role === "user" && !block.draft && !block.agentSessionCompletion && !block.agentSetup && block.startedAt != null);
  const previous = sent.length >= 2 ? sent[sent.length - 2] : undefined;
  if (!previous?.startedAt) return undefined;
  return `<since_last_message>
${elapsedPhrase(Math.max(0, now - previous.startedAt))}
</since_last_message>`;
}

export function localTimeContext(now: number): string {
  const date = new Date(now);
  const pad = (value: number) => String(Math.trunc(value)).padStart(2, "0");
  const offset = -date.getTimezoneOffset();
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const utc = `UTC${offset < 0 ? "-" : "+"}${pad(Math.abs(offset) / 60)}:${pad(Math.abs(offset) % 60)}`;
  const day = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  return `<local_time>\n${day} ${pad(date.getHours())}:${pad(date.getMinutes())} (${zone ? `${zone}, ` : ""}${utc})\n</local_time>`;
}
