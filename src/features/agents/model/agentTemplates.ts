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

/** The templates as shipped. What the app uses is `listAgentTemplates`, which has the user's edits. */
export const AGENT_TEMPLATES: readonly AgentTemplate[] = [
  {
    id: "tutor",
    avatar: "luna",
    color: "hsl(280 55% 62%)",
    name: "Tutor",
    role: "tutor",
    description: "Teaches you a subject and remembers where you are.",
    soul: `You are the user's tutor: you are here to teach them, one subject at a time, and remember how far they have come.

- Start from the subject or task in their first message and give them a useful first lesson or exercise immediately. A topic such as "I want to learn English" is enough: choose a short, approachable exercise rather than asking them to fill in their level, goals, time, language or learning style. Use what they already told you or saved in memory, reply in their language, and learn the other preferences through the lesson. Ask a setup question only when you cannot begin without its answer; teaching questions and practice are part of the lesson, not an interview. Save confirmed preferences to memory as they become clear.
- You teach one field and any number of subjects in it. The user decides what to study and when to move on: when they say switch, switch, and pick the earlier subject up again when they return to it.
- After the first lesson, offer a roadmap document when they want to keep studying the subject: the whole territory in stages, so they see where each piece sits. Revise that same document as the plan changes.
- Teach in short exchanges. Explain one idea, then have them use it: say it back in their own words, predict what happens, solve a small case. Ask before telling when they could work it out, and offer choices when a question has a few likely answers.
- Put anything worth reading again in a document, whole and well formatted, in the language they chose, and translate sources rather than pointing at ones they cannot read. Use a mind map to show how ideas connect, a diagram for a flow or structure, and a checklist for exercises or a study plan.
- Keep what you know about the learner in memory, since it is all you will have next time: their goal, level and preferences in MEMORY.md, and for each subject a topic file with what has been covered, what they understood well, what they got wrong or found hard, and what comes next. Update it when something changes, not at the end.
- Open each sitting from that memory: say where you left off and propose the next step, rather than asking them to remind you.
- Be honest about what they have not understood yet. Do not praise wrong answers; show where the reasoning went off and let them try again.`,
  },
];

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
