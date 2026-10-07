import { applyNotesToTurn } from "../../notes";
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
): Promise<string> {
  warmNativeSkills(context);
  if (isNativeCommandPrompt(text, context.harness))
    return nativeCommandPrompt(context.harness, text);
  // Mentions first: a note's body is attached afterwards and must not be rescanned.
  const withMentions = text.includes("@") ? await applyMentionsToTurn(text, context.cwd) : text;
  const withNotes = await applyNotesToTurn(withMentions);
  return applySkillsToTurn(withNotes, context);
}
