// The rubric judge: one prompt per scenario (judge-prompt.md), run through an
// agent CLI in print mode from an empty folder, so it sees only the evidence.
// Grok is the official judge here; Antigravity (agy, with a pinned model) and
// the other CLIs stay available where they answer.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const RUBRIC = ["firstHand", "courseStructure", "grounding", "firstTenMinutes"];
/** Rubric items a scenario opts into; code tours and a learning path are the v0.4 sandbox additions. */
export const RUBRIC_EXTENSIONS = {
  codeTours: "Do the code-tour lessons show the real call path, are they pinned to a commit (`commit` or `repos/<repo>@<sha>:path`), and is each line range accurate for what the lesson says? 1 = no code tours, unpinned lessons, or ranges that do not show the claim; 3 = some tours pinned and mostly accurate, but the path skips entry points or jumps between unrelated files; 5 = every code lesson pinned, its lines accurate, and the lessons follow the call path in reading order.",
  path: "Is the learning path progressive: 3–5 short courses in an order where each builds on the last, with no overlap and with prerequisites that name earlier courses? 1 = no path, or one course dressed up as a path; 3 = a path exists but courses overlap or repeat material, or the order does not build; 5 = a clear progression from one distinct focus to the next, prerequisites shown, no repeated lessons.",
};
/** The rubric keys one scenario asks for. */
export function rubricFor(scenario) {
  const extra = Array.isArray(scenario?.rubric) ? scenario.rubric.filter((key) => Object.hasOwn(RUBRIC_EXTENSIONS, key)) : [];
  return [...RUBRIC, ...extra];
}
/** Pinned per judge, in the CLI's own model spelling, so a run's rubric has one model. */
export const DEFAULT_JUDGE_MODEL = { agy: "claude-opus-4-6-thinking", grok: "deepseek-flash" };
const LIMITS = { reply: 4000, source: 1500, transcript: 60_000, courses: 12_000, tours: 8000 };

const clip = (text, max) => (text.length > max ? `${text.slice(0, max)}\n…[${text.length - max} more characters]` : text);

/** The code-tour evidence the judge reads: what each lesson shows, and how its pin stands. */
export function codeToursEvidence(tours) {
  if (!Array.isArray(tours) || !tours.length) return "(no code-tour lessons)";
  return tours.map((tour) => {
    const place = `${tour.file}${tour.lines ? `#L${tour.lines[0]}-${tour.lines[1]}` : ""}${tour.commit ? ` @ ${String(tour.commit).slice(0, 12)}` : " (unpinned)"}`;
    const state = tour.state ? ` · pin ${tour.state}` : "";
    const excerpt = String(tour.excerpt ?? "").trim();
    return `- **${tour.course}/${tour.lesson}** — ${tour.title} · ${place}${state}${excerpt ? `\n\n  \`\`\`\n${clip(excerpt, 900).replace(/\n/g, "\n  ")}\n  \`\`\`` : ""}`;
  }).join("\n");
}

/** The judge prompt for one scenario run, filled from the template in the repo. */
export function judgePrompt({ scenario, checks, sources, courses, turns, codeTours = [] }, template = readFileSync(join(HERE, "judge-prompt.md"), "utf8")) {
  const transcript = turns.map((turn) => `#### ${turn.role === "mentor" ? "Mentor" : turn.probe ? "Learner (probe)" : "Learner"}\n${clip(String(turn.text ?? ""), LIMITS.reply)}`).join("\n\n");
  const sourceList = sources.length
    ? sources.map((source) => `- **${source.title}** (${source.id}, ${source.kind ?? (source.sourceUrl ? "source" : "guide")}${source.sourceUrl ? `, ${source.sourceUrl}` : ""})\n\n  ${clip(String(source.body ?? "").replace(/\n+/g, " "), LIMITS.source)}`).join("\n")
    : "(none saved)";
  const keys = rubricFor(scenario);
  const extra = keys.slice(RUBRIC.length);
  const rubricExtra = extra.map((key, index) => `${RUBRIC.length + index + 1}. **${key}** — ${RUBRIC_EXTENSIONS[key]}`).join("\n\n");
  const outputShape = `{"scores":{${keys.map((key) => `"${key}":{"score":1,"reason":"..."}`).join(",")}},"worst":"..."}`;
  const fill = {
    persona: scenario.learner?.background ?? "",
    opening: scenario.opening,
    template: scenario.template,
    checks: JSON.stringify(checks, null, 1),
    sources: sourceList,
    courses: clip(JSON.stringify(courses.map((course) => ({ id: course.id, title: course.title, chapters: (course.data ?? course).chapters ?? [] })), null, 1), LIMITS.courses),
    codeTours: clip(codeToursEvidence(codeTours), LIMITS.tours),
    transcript: clip(transcript, LIMITS.transcript),
    rubricExtra,
    outputShape,
  };
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => fill[key] ?? "");
}

/** The verdict in a judge's output: the first JSON object with all the scenario's rubric scores, or null. */
export function parseVerdict(output, keys = RUBRIC) {
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
      let inString = false;
      for (let end = start; end < candidate.length; end++) {
        const char = candidate[end];
        // Braces inside a JSON string (a reason quoting code) do not count.
        if (inString) { if (char === "\\") end++; else if (char === '"') inString = false; continue; }
        if (char === '"') inString = true;
        else if (char === "{") depth++;
        else if (char === "}" && --depth === 0) {
          try {
            const parsed = JSON.parse(candidate.slice(start, end + 1));
            if (parsed?.scores && keys.every((key) => Number.isInteger(parsed.scores[key]?.score) && parsed.scores[key].score >= 1 && parsed.scores[key].score <= 5))
              return { scores: Object.fromEntries(keys.map((key) => [key, { score: parsed.scores[key].score, reason: String(parsed.scores[key].reason ?? "").trim() }])), worst: String(parsed.worst ?? "").trim() };
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
  const keys = rubricFor(evidence.scenario);
  const prompt = judgePrompt(evidence);
  const cwd = mkdtempSync(join(tmpdir(), "loci-eval-judge-"));
  const promptFile = join(cwd, "prompt.md");
  writeFileSync(promptFile, prompt);
  try {
    const [command, args] = judgeCommand(provider, model, promptFile, prompt);
    const started = Date.now();
    const result = await exec(command, args, { cwd, timeoutMs });
    const verdict = parseVerdict(result.out, keys);
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
