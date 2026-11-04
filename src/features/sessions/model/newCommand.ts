import type { BuiltinSkill } from "../../skills/model/skills";

export const NEW_COMMAND: BuiltinSkill = {
  kind: "builtin",
  name: "new",
  invocation: "new",
  description: "Start a new conversation. Soul and memory stay.",
  scope: "builtin",
  source: "loci",
};

export function isNewCommand(text: string): boolean {
  return /^\s*\/new\s*$/i.test(text);
}
