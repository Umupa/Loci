import type { BuiltinSkill } from "../../skills/model/skills";

export const NEW_COMMAND: BuiltinSkill = {
  kind: "builtin",
  name: "new",
  invocation: "new",
  description: "Start over with a fresh context. The chat above stays.",
  scope: "builtin",
  source: "loci",
};

export function isNewCommand(text: string): boolean {
  return /^\s*\/new\s*$/i.test(text);
}
