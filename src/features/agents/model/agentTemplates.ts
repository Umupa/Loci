import catalog from "../templates/catalog.json";

/**
 * Built-in agents to start from. A template is an agent with its soul already
 * written, and nothing else: making one writes that soul into the new
 * agent's SOUL.md, where the user reads and edits it like any other. There
 * is no hidden message and no behaviour of its own behind it.
 */
export type AgentTemplate = {
  id: string;
  /** The face and color it starts with, so a template is recognisable in the menu. */
  avatar: string;
  color: string;
  /** The name the agent starts with; the user can rename it. */
  name: string;
  /** Its one main job in a few words, read as "the user's <role>". */
  role: string;
  /** One line for the menu. */
  description: string;
  /** Its standing instructions, as Markdown: everything that makes it this kind of agent. */
  soul: string;
};

const templateCatalog: readonly Omit<AgentTemplate, "soul">[] = catalog;
const souls = import.meta.glob<string>("../templates/*.md", {
  query: "?raw",
  import: "default",
  eager: true,
});

/** The templates as shipped. What the app uses is `listAgentTemplates`, which has the user's edits. */
export const AGENT_TEMPLATES: readonly AgentTemplate[] = templateCatalog.map((template) => {
  const path = `../templates/${template.id}.md`;
  const soul = souls[path]?.trim();
  if (!soul) throw new Error(`Agent template "${template.id}" has no soul at ${path}.`);
  return { ...template, soul };
});

/** The parts of a template the user can rewrite in Settings: its wording, not its identity. */
export const TEMPLATE_TEXT_FIELDS = ["name", "role", "description", "soul"] as const;
export type TemplateTextField = (typeof TEMPLATE_TEXT_FIELDS)[number];
type TemplateEdits = Partial<Record<TemplateTextField, string>>;

const EDITS_KEY = "loci:agent-template-edits";
const EDITS_CHANGED = "loci:agent-templates-changed";

function readEdits(): Record<string, TemplateEdits> {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(EDITS_KEY) ?? "{}");
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, TemplateEdits>)
      : {};
  } catch {
    return {};
  }
}

function writeEdits(edits: Record<string, TemplateEdits>): void {
  try {
    localStorage.setItem(EDITS_KEY, JSON.stringify(edits));
  } catch {
    // Without storage the edit lasts for this window only, which the event still serves.
  }
  window.dispatchEvent(new CustomEvent(EDITS_CHANGED));
}

function withEdits(template: AgentTemplate, edits: TemplateEdits | undefined): AgentTemplate {
  if (!edits) return template;
  const next = { ...template };
  for (const field of TEMPLATE_TEXT_FIELDS) {
    const value = edits[field];
    if (typeof value !== "string") continue;
    // An emptied field falls back to what ships.
    if (value.trim()) next[field] = value.trim();
  }
  return next;
}

/** The templates a new agent can start from, with the user's own wording where they changed it. */
export function listAgentTemplates(): AgentTemplate[] {
  const edits = readEdits();
  return AGENT_TEMPLATES.map((template) => withEdits(template, edits[template.id]));
}

export function agentTemplate(id: string | undefined): AgentTemplate | undefined {
  return id ? listAgentTemplates().find((template) => template.id === id) : undefined;
}

/** Whether the user has changed this template from what ships. */
export function agentTemplateEdited(id: string): boolean {
  return Object.keys(readEdits()[id] ?? {}).length > 0;
}

/** Replace one template's wording. A field equal to what ships is not kept as an edit. */
export function saveAgentTemplate(id: string, fields: TemplateEdits): void {
  const shipped = AGENT_TEMPLATES.find((template) => template.id === id);
  if (!shipped) return;
  const kept: TemplateEdits = {};
  for (const field of TEMPLATE_TEXT_FIELDS) {
    const value = fields[field];
    if (typeof value === "string" && value.trim() !== shipped[field].trim()) kept[field] = value;
  }
  const edits = readEdits();
  if (Object.keys(kept).length) edits[id] = kept;
  else delete edits[id];
  writeEdits(edits);
}

/** Back to the template as shipped. */
export function resetAgentTemplate(id: string): void {
  const edits = readEdits();
  delete edits[id];
  writeEdits(edits);
}

export function subscribeAgentTemplates(onChange: () => void): () => void {
  window.addEventListener(EDITS_CHANGED, onChange);
  window.addEventListener("storage", onChange);
  return () => {
    window.removeEventListener(EDITS_CHANGED, onChange);
    window.removeEventListener("storage", onChange);
  };
}

/** Changes whenever the templates do, for `useSyncExternalStore`. */
export function agentTemplatesSnapshot(): string {
  try {
    return localStorage.getItem(EDITS_KEY) ?? "";
  } catch {
    return "";
  }
}

/** The new agent's SOUL.md: the template's soul under the usual heading. */
export function templateSoul(template: AgentTemplate): string {
  return `# Soul

## Standing instructions
${template.soul}
`;
}
