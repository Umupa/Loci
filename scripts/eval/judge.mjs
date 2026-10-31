// The rubric judge: one prompt per scenario (judge-prompt.md), run through an
// agent CLI in print mode from an empty folder, so it sees only the evidence.
// The official judge is Antigravity (agy) with a pinned model; others exist so
// the harness can be checked when agy cannot run, and are labelled as such.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const RUBRIC = ["firstHand", "courseStructure", "grounding", "firstTenMinutes"];
export const DEFAULT_JUDGE_MODEL = { agy: "claude-opus-4-6-thinking" };
const LIMITS = { reply: 4000, source: 1500, transcript: 60_000, courses: 12_000 };

const clip = (text, max) => (text.length > max ? `${text.slice(0, max)}\n…[${text.length - max} more characters]` : text);

/** The judge prompt for one scenario run, filled from the template in the repo. */
export function judgePrompt({ scenario, checks, sources, courses, turns }, template = readFileSync(join(HERE, "judge-prompt.md"), "utf8")) {
  const transcript = turns.map((turn) => `#### ${turn.role === "mentor" ? "Mentor" : turn.probe ? "Learner (probe)" : "Learner"}\n${clip(String(turn.text ?? ""), LIMITS.reply)}`).join("\n\n");
  const sourceList = sources.length
    ? sources.map((source) => `- **${source.title}** (${source.id}, ${source.kind ?? (source.sourceUrl ? "source" : "guide")}${source.sourceUrl ? `, ${source.sourceUrl}` : ""})\n\n  ${clip(String(source.body ?? "").replace(/\n+/g, " "), LIMITS.source)}`).join("\n")
    : "(none saved)";
  const fill = {
    persona: scenario.learner?.background ?? "",
    opening: scenario.opening,
    template: scenario.template,
    checks: JSON.stringify(checks, null, 1),
    sources: sourceList,
    courses: clip(JSON.stringify(courses.map((course) => ({ id: course.id, title: course.title, chapters: (course.data ?? course).chapters ?? [] })), null, 1), LIMITS.courses),
    transcript: clip(transcript, LIMITS.transcript),
  };
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => fill[key] ?? "");
}

/** The verdict in a judge's output: the first JSON object with all rubric scores, or null. */
export function parseVerdict(output) {
  const text = String(output ?? "");
  const candidates = [];
  // A CLI's JSON envelope may carry the reply as a string.
  try {
    const whole = JSON.parse(text);
    for (const key of ["result", "response", "text", "output", "content"]) if (typeof whole?.[key] === "string") candidates.push(whole[key]);
    candidates.push(JSON.stringify(whole.scores ? whole : whole.structured_output ?? whole));
  } catch { /* not a single JSON document */ }
  candidates.push(text);
  for (const candidate of candidates) {
    for (let start = candidate.indexOf("{"); start >= 0; start = candidate.indexOf("{", start + 1)) {
      let depth = 0;
      for (let end = start; end < candidate.length; end++) {
        if (candidate[end] === "{") depth++;
        else if (candidate[end] === "}" && --depth === 0) {
          try {
            const parsed = JSON.parse(candidate.slice(start, end + 1));
            if (parsed?.scores && RUBRIC.every((key) => Number.isInteger(parsed.scores[key]?.score) && parsed.scores[key].score >= 1 && parsed.scores[key].score <= 5))
              return { scores: Object.fromEntries(RUBRIC.map((key) => [key, { score: parsed.scores[key].score, reason: String(parsed.scores[key].reason ?? "").trim() }])), worst: String(parsed.worst ?? "").trim() };
          } catch { /* keep looking */ }
          break;
        }
      }
    }
  }
  return null;
}

/** The command line for a judge provider. */
export function judgeCommand(provider, model, promptFile, prompt) {
  if (provider === "agy" || provider === "antigravity")
    return ["agy", ["-p", prompt, "--print-timeout", "600s", ...(model ? ["--model", model] : [])]];
  if (provider === "grok")
    return ["grok", ["--prompt-file", promptFile, "--disable-web-search", "--no-subagents", ...(model ? ["--model", model] : [])]];
  if (provider === "claude")
    return ["claude", ["-p", prompt, ...(model ? ["--model", model] : [])]];
  if (provider === "codex")
    return ["codex", ["exec", "--skip-git-repo-check", ...(model ? ["-m", model] : []), prompt]];
  throw new Error(`No judge for provider ${provider}; use agy, grok, claude, codex or none`);
}

function exec(command, args, { cwd, timeoutMs }) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let out = ""; let err = "";
    const timer = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
    child.stdout.on("data", (chunk) => { out += chunk; });
    child.stderr.on("data", (chunk) => { err += chunk; });
    child.on("error", (error) => { clearTimeout(timer); resolve({ code: -1, out, err: String(error) }); });
    child.on("close", (code) => { clearTimeout(timer); resolve({ code, out, err }); });
  });
}

/** Runs the judge once; never throws, so a failed judge leaves the automatic checks standing. */
export async function judge(evidence, { provider, model, timeoutMs = 11 * 60_000 }) {
  const prompt = judgePrompt(evidence);
  const cwd = mkdtempSync(join(tmpdir(), "loci-eval-judge-"));
  const promptFile = join(cwd, "prompt.md");
  writeFileSync(promptFile, prompt);
  try {
    const [command, args] = judgeCommand(provider, model, promptFile, prompt);
    const started = Date.now();
    const result = await exec(command, args, { cwd, timeoutMs });
    const verdict = parseVerdict(result.out);
    return { provider, model: model ?? null, seconds: Math.round((Date.now() - started) / 1000), prompt, raw: result.out.slice(-20_000), error: verdict ? null : (result.err || result.out).trim().slice(-2000) || `exit ${result.code}`, verdict };
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}

/**
 * Whether an agent CLI can run a turn here: ok, missing, not-signed-in or
 * region (Antigravity's eligibility check), with its own words.
 */
export async function probeProvider(provider) {
  const [command, args] = judgeCommand(provider, undefined, "/dev/null", "Reply with the single word OK.");
  const promptArgs = provider === "grok" ? ["-p", "Reply with the single word OK.", "--disable-web-search"] : args;
  const cwd = mkdtempSync(join(tmpdir(), "loci-eval-probe-"));
  try {
    const result = await exec(command, promptArgs, { cwd, timeoutMs: 120_000 });
    const said = `${result.out}\n${result.err}`.trim();
    if (result.code === -1 && /ENOENT/.test(result.err)) return { state: "missing", said };
    if (/not (currently )?available in your location|not eligible/i.test(said)) return { state: "region", said };
    if (/log ?in|sign ?in|unauthori[sz]ed|authenticat|credentials/i.test(said) && !/\bOK\b/.test(result.out)) return { state: "not-signed-in", said };
    if (/\bOK\b/i.test(result.out)) return { state: "ok", said };
    return { state: "failed", said };
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
}
