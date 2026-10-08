/**
 * Claude catalogs can advertise short version ids that the CLI cannot launch.
 * Only normalize known Claude shorthands: proxy routes and custom model ids
 * are opaque, even when they contain digits or resolve to a Claude model.
 */
export function claudeModelId(model: string, resolvedModel?: string): string {
  if (!/^(?:opus|sonnet|haiku|fable)-\d+(?:[.-]\d+)*$/.test(model)) {
    return model;
  }
  if (resolvedModel?.startsWith("claude-")) return resolvedModel;
  return `claude-${model.replace(/\./g, "-")}`;
}
