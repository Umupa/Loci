// Grok is the official provider here: mentors and judge both run on it.
// Antigravity is region-blocked on this account, and the other CLIs stay
// available through --provider/--judge for a machine where they answer.
export const DEFAULT_PROVIDER = "grok";

/** The model each provider's mentors start on when --model is left out. */
const DEFAULT_MENTOR_MODEL = { grok: "grok:deepseek-flash" };

export function defaultMentorModel(provider) {
  return DEFAULT_MENTOR_MODEL[provider];
}
