import { agentLook, type Agent } from "../../features/agents/model/agent";
import { modelsFor } from "../../features/sessions/model/models";
import type { HarnessId } from "../../features/sessions/model/session";
import type { CommandContext } from "./context";
import { CommandError, field, type CommandMeta } from "./registry";

export const mentorField = (positional = false) =>
  field("mentor", "string", "The mentor, by id or name", { required: true, positional, max: 200 });

/**
 * The mentor a command is about, by id or by its (unique) name. A mentor's
 * own turn is always about itself.
 */
export function resolveMentor(ctx: CommandContext, ref: unknown, meta: CommandMeta): Agent {
  const agents = ctx.agents();
  if (meta.caller === "agent") {
    const own = agents.find((agent) => agent.id === meta.agentId);
    if (!own) throw new CommandError("Only a mentor's own conversation can do this");
    if (typeof ref === "string" && ref !== own.id && agentLook(own).name.toLowerCase() !== ref.trim().toLowerCase())
      throw new CommandError("A mentor can only act on itself");
    return own;
  }
  if (typeof ref !== "string" || !ref.trim()) throw new CommandError("mentor is required", "usage");
  const wanted = ref.trim();
  const byId = agents.find((agent) => agent.id === wanted);
  if (byId) return byId;
  const byName = agents.filter((agent) => agentLook(agent).name.toLowerCase() === wanted.toLowerCase());
  if (byName.length === 1) return byName[0];
  if (byName.length > 1) throw new CommandError(`Several mentors are called ${wanted}; use an id from \`loci mentors list\``, "usage");
  throw new CommandError(`No mentor ${wanted}. Run \`loci mentors list\`.`, "not_found");
}

/** The mentor's conversation, the session its own actions run as. */
export async function mentorChat(ctx: CommandContext, agent: Agent) {
  return ctx.agentChat(agent.id);
}

/**
 * Read a provider's catalog so a model only its CLI knows (grok's custom
 * models, say) resolves in a fresh window, as opening the model picker does.
 * A model still missing after the short wait gets the probe's full time; a
 * catalog that loaded without it means the provider has no such model.
 */
export async function refreshModelsFor(
  ctx: CommandContext,
  harness: HarnessId,
  modelId: unknown,
): Promise<void> {
  await ctx.refreshModels([harness]);
  if (typeof modelId !== "string" || modelsFor(harness).some((model) => model.id === modelId)) return;
  await ctx.refreshModels([harness], { patient: true });
}
