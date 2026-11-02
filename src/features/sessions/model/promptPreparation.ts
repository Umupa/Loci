import { applyNotesToTurn } from "../../notes";
import { applyLibraryMentionsToTurn } from "./libraryMentions";
import { applyMentionsToTurn } from "./mentionSources";
import {
  applySkillsToTurn,
  warmNativeSkills,
  isNativeCommandPrompt,
  type SkillCatalogContext,
} from "../../skills/model/skills";
import { nativeCommandPrompt } from "../../../integrations/harness/core/nativeCommands";

export async function preparePrompt(
  text: string,
  context: SkillCatalogContext,
  /** A mentor's turn: its `@lesson/…`, `@source/…` and other library mentions are resolved too. */
  agentId?: string,
): Promise<string> {
  warmNativeSkills(context);
  if (isNativeCommandPrompt(text, context.harness))
    return nativeCommandPrompt(context.harness, text);
  // Mentions first: a note's body is attached afterwards and must not be rescanned.
  const withMentions = text.includes("@") ? await applyMentionsToTurn(text, context.cwd) : text;
  const withLibrary = agentId && withMentions.includes("@") ? await applyLibraryMentionsToTurn(withMentions, agentId) : withMentions;
  const withNotes = await applyNotesToTurn(withLibrary);
  return applySkillsToTurn(withNotes, context);
}
