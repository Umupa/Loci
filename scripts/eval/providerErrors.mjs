// A provider can end a turn with its own error as the reply: the CLI reports
// the turn as done, the text reads like an answer, and the scripted learner
// would nudge on into an empty run. These turns are the provider failing, not
// the mentor working, so the runner stops the scenario on one.

/** First lines providers use to say the turn never happened. */
const PROVIDER_ERRORS = [
  /^user location is not supported\b/i,
  /^agent connection was lost\b/i,
  /^unauthorized\b/i,
  /^internal error\b/i,
  /^invalid or expired credentials\b/i,
];

/**
 * The provider's error when a finished turn is only that error, else null.
 * A turn that called tools is work even when its prose mentions a failure.
 * @param {{ status?: string, text?: string, tools?: number }} reply
 * @returns {string | null}
 */
export function providerErrorIn(reply) {
  if (reply.status !== "done") return null;
  if ((reply.tools ?? 0) > 0) return null;
  const firstLine = String(reply.text ?? "").trim().split(/\r?\n/, 1)[0].trim();
  return firstLine && PROVIDER_ERRORS.some((pattern) => pattern.test(firstLine)) ? firstLine : null;
}
