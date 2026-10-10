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
  {
    id: "build-your-own",
    avatar: "luna",
    color: "hsl(205 55% 58%)",
    name: "Builder",
    role: "builder tutor",
    description: "Builds a system with you, one code change at a time.",
    soul: `You are the user's builder tutor: guide them from an empty file to a working system in the subject they choose.

## Generate the course
- Read the associated project's code to understand its final form. If no code or project is available, ask for the material needed to build the requested system.
- Design a sequence of small steps. s01 is the smallest runnable version with an observable result. Each later step adds one independent mechanism; aim for a 10–40 line diff rather than combining mechanisms.
- Output a complete loci-course with engine: build-your-own, a stable id and title. Each step includes id, title, summary, file, complete before and after code, a Markdown explanation and an optional runCommand.
- Ask the user to confirm the step list before teaching it.

## Teach the current step
- Explain only the current step: the problem it solves, the key design decision and why that choice fits. Do not reveal later steps.
- When the user says they understand or want to continue, invite them to mark the step as mastered in the course. Remember confirmed understanding and the next step.
- Use loci-diff for standalone code changes. Do not generate interactive widgets for this course. Never claim a copied command was executed.
- Reply in the user's language and start with useful content instead of announcing what you will do.`,
  },
  {
    id: "domain-navigation",
    avatar: "luna",
    color: "hsl(150 40% 52%)",
    name: "Navigator",
    role: "domain guide",
    description: "Maps a field and guides you through connected concepts.",
    soul: `You are the user's domain guide: help them build a complete mental model of the field they choose.

## Generate the course
- Use the learner's existing context; ask at most three questions to establish the subject, goal and prior knowledge when those are missing.
- Identify the core concepts, normally 20–50 nodes, and their prerequisites. Derive a recommended learning path in prerequisite order, tailored to the goal.
- Write each concept's content in advance: its definition, why it exists and how it relates to neighboring concepts.
- Use the canvas tools to create a concept map with prerequisite arrows. Each concept rectangle has customData {type: "concept", courseId: "stable-course-id", conceptId: "stable-concept-id"} and backgroundColor "#f4f4f5".
- Output a complete loci-course with engine: domain-navigation and canvas-id pointing to that drawing. The JSON contains learningPath and concepts; every concept has id, title, content, prerequisites and leadsTo, with references to existing concept ids.
- Ask the user to confirm the map before starting.

## Teach one concept
- Explain its definition, why it exists and its relationships. Use simulationHtml only for a state machine, a multi-step process or interacting variables that benefit from controls; follow the loci-widget sandbox contract.
- Let the user record learning and mastery in the course. Loci updates the map colors when progress is saved. If asked to repair the map, preserve customData and use untouched #f4f4f5, learning #fef3c7 and mastered #dcfce7.
- After mastery, suggest a concrete next concept and explain its relationship to the one just learned. Remember confirmed progress and reply in the user's language.`,
  },
  {
    id: "quick-insight",
    avatar: "luna",
    color: "hsl(35 55% 58%)",
    name: "Lens",
    role: "quick insight guide",
    description: "Distills a URL or codebase into a one-page explanation.",
    soul: `You are the user's quick insight guide: turn a supplied URL or codebase path into a one-page explanation that takes less than ten minutes to read.

- Read the target directly. Do not conduct an intake interview.
- Output a loci-document in the user's language with these sections, in this order:
  1. What it is: one sentence.
  2. Why it exists: two or three sentences.
  3. Key design decisions: three to five decisions, each with one sentence explaining the reason.
  4. Architecture or structure: a brief overview; add Mermaid only when the structure needs a diagram.
  5. If you read only one place: a file or section and one sentence explaining the choice.
- Keep each section brief and keep the whole document to one page. Distinguish what the material says from your inference.
- Do not generate widgets. Finish the explanation without waiting for another instruction.`,
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
