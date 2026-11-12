import { AGENT_TEMPLATES, type AgentTemplate } from "../../agents/templates";

/** What the start page offers to fill in: one subject, one repository, one systems question. */
export const START_EXAMPLES = [
  "How Kubernetes is designed inside. I'm preparing for platform interviews; I use it every day but can't explain it.",
  "Read the design of github.com/firecracker-microvm/firecracker",
  "How a packet travels through Linux. iptables is only a word to me.",
] as const;

const REPO = /(?:https?:\/\/)?(?:www\.)?github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?(?=[/#?\s]|$)/i;

/** The repository a request names, if it names one on GitHub. */
export function repositoryIn(text: string): { owner: string; repo: string } | null {
  const match = text.match(REPO);
  return match ? { owner: match[1], repo: match[2] } : null;
}

const FILLER = new Set(["i", "i'd", "i'm", "want", "would", "like", "to", "learn", "understand", "know", "how", "what", "why", "the", "a", "an", "about", "read", "study", "me", "teach", "explain", "is", "are", "does", "do", "works", "work", "design", "of", "in", "inside", "my", "please"]);
const CJK_PREFIX = /^(?:我想(?:要)?|想要|想|请|帮我|我要)?(?:学(?:习|会)?|了解|弄懂|搞懂|读懂|看懂|理解)?/u;

/**
 * A short name for the mentor a request starts: the repository's name, else
 * the first technical word of its first clause ("K8s", "Linux"), else its
 * first few words. The mentor can be renamed in its settings.
 */
export function mentorName(text: string): string {
  const repo = repositoryIn(text);
  if (repo) return repo.repo.slice(0, 40);
  const clause = text.trim().split(/[\n,，.。;；:：!?！？、(（]/u)[0]?.trim() ?? "";
  const latin = clause.match(/[A-Za-z][A-Za-z0-9+#._-]*/g) ?? [];
  const words = latin.filter((word) => !FILLER.has(word.toLowerCase()));
  const technical = words.find((word) => /[A-Z0-9]/.test(word));
  const cjk = /\p{Script=Han}/u.test(clause);
  if (technical) return technical.slice(0, 24);
  if (cjk) {
    const rest = clause.replace(CJK_PREFIX, "").replace(/\s+/g, "");
    if (rest) return [...rest].slice(0, 6).join("");
  }
  if (words.length) return words.slice(0, 3).map((word) => word[0].toUpperCase() + word.slice(1)).join(" ").slice(0, 32);
  return "Mentor";
}

/** The mentor a start-page request makes: Lens for a repository, else Mentor, with its short name. */
export function mentorForRequest(text: string): { template: AgentTemplate; name: string } {
  const id = repositoryIn(text) ? "repo-lens" : "learning-guide";
  const template = AGENT_TEMPLATES.find((entry) => entry.id === id) ?? AGENT_TEMPLATES[0];
  return { template, name: mentorName(text) };
}
