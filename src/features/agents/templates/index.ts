import learningGuide from "./learning-guide.md?raw";
import repoLens from "./repo-lens.md?raw";

/** A ready-made agent: its look and the Soul it starts with. */
export type AgentTemplate = {
  id: string;
  name: string;
  role: string;
  summary: string;
  avatar: string;
  soul: string;
};

/**
 * The agents Loci is used with, one per kind of work. Adding one writes its
 * Soul once; edits afterwards belong to that agent alone.
 */
export const AGENT_TEMPLATES: readonly AgentTemplate[] = [
  {
    id: "learning-guide", name: "Mentor", role: "Domain guide", avatar: "nova", soul: learningGuide,
    summary: "Agrees on a goal one question at a time, gathers primary sources and arranges them into a course, then reads along with you.",
  },
  {
    id: "repo-lens", name: "Lens", role: "Open-source reader", avatar: "tide", soul: repoLens,
    summary: "Give it a repository: it clones it, writes a one-page brief and a code-tour course of the files worth reading.",
  },
];
