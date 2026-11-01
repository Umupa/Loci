#!/usr/bin/env node
// Mentor evaluation: drives real mentors through the `loci` command line of a
// QA build, plays a scripted learner, collects what the mentor made, scores it
// and writes eval/results/<timestamp>/. See docs/evaluation.md.
//
//   npm run eval -- --app com.loci.desktop.qa-eval --bin "/path/Loci Eval QA.app/Contents/MacOS/loci"
//   npm run eval -- --scenario sqlite-wal --provider grok --judge grok
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { lociCli, LociCliError } from "../e2e/loci.mjs";
import { DEFAULT_JUDGE_MODEL, judge, probeProvider } from "./judge.mjs";
import { nextMessage } from "./learner.mjs";
import { summaryMarkdown } from "./report.mjs";
import { scoreRun } from "./score.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../..");
/** QA apps other workers use; never driven unless named with --app. */
const OTHERS = new Set(["com.loci.desktop.qa-v03"]);

const [major, minor] = process.versions.node.split(".").map(Number);
if (major < 22 || (major === 22 && minor < 18)) {
  console.error("The evaluation needs Node 22.18 or later (it imports the reader's TypeScript resolver directly).");
  process.exit(2);
}

const { values: opts } = parseArgs({
  options: {
    scenario: { type: "string", multiple: true },
    app: { type: "string" },
    bin: { type: "string" },
    provider: { type: "string", default: "agy" },
    model: { type: "string" },
    mode: { type: "string", default: "full-access" },
    judge: { type: "string" },
    "judge-model": { type: "string" },
    "max-turns": { type: "string" },
    "max-minutes": { type: "string" },
    out: { type: "string" },
    keep: { type: "boolean", default: false },
    "skip-probe": { type: "boolean", default: false },
    rescore: { type: "string" },
    help: { type: "boolean", short: "h", default: false },
  },
});

if (opts.help) {
  console.log(`npm run eval -- [--scenario id]... [--app id] [--bin path] [--provider agy] [--model id]
  [--judge agy|grok|claude|codex|none] [--judge-model id] [--max-turns n] [--max-minutes n] [--out dir] [--keep]
npm run eval -- --rescore eval/results/<timestamp>   # recompute checks and summary from saved artifacts, no app

--app/LOCI_APP_ID names the Loci to drive (a QA build; never com.loci.desktop).
--bin/LOCI_BIN is its loci executable. --provider is the mentors' agent CLI
(default agy); --judge defaults to the same provider. Results go to
eval/results/<timestamp>/ unless --out. See docs/evaluation.md.`);
  process.exit(0);
}

if (opts.rescore) {
  rescore(resolve(opts.rescore));
  process.exit(0);
}

/** Recomputes score.json and summary.md of a saved run; the saved judge verdicts are kept. */
function rescore(runDir) {
  const meta = JSON.parse(readFileSync(join(runDir, "run.json"), "utf8"));
  const json = (path, fallback) => { try { return JSON.parse(readFileSync(path, "utf8")); } catch { return fallback; } };
  const results = [];
  for (const id of meta.scenarios) {
    const dir = join(runDir, id);
    const scenario = json(join(HERE, "scenarios", `${id}.json`), null);
    if (!scenario || !existsSync(join(dir, "turns.json"))) { results.push({ scenario: scenario ?? { id, template: "?" }, error: "no saved run" }); continue; }
    const sources = json(join(dir, "sources.json"), []).map((source) => ({ ...source, body: readText(join(dir, "sources", `${source.id}.md`)) ?? "" }));
    const courses = existsSync(join(dir, "courses")) ? readdirSync(join(dir, "courses")).map((name) => json(join(dir, "courses", name), null)).filter(Boolean) : [];
    const turns = json(join(dir, "turns.json"), []);
    const decisions = json(join(dir, "learner.json"), []);
    const previous = json(join(dir, "score.json"), {});
    const workdir = join(tmpdir(), "loci-eval", meta.stamp, id);
    const run = { scenario, sources, courses, turns, timings: json(join(dir, "timings.json"), {}), failures: previous.failures ?? [], nudges: decisions.filter((entry) => entry.nudge).length };
    const score = scoreRun(run, { readFile: readText, roots: [workdir] });
    writeFileSync(join(dir, "score.json"), `${JSON.stringify(score, null, 2)}\n`);
    results.push({ scenario, score, judge: json(join(dir, "judge.json"), null), run: { stoppedBy: json(join(dir, "stop.json"), {}).stoppedBy } });
  }
  writeFileSync(join(runDir, "summary.md"), summaryMarkdown(meta, results));
  console.error(`rescored ${join(runDir, "summary.md")}`);
}

const app = opts.app ?? process.env.LOCI_APP_ID;
if (!app) { console.error("Name the Loci to drive with --app (or LOCI_APP_ID): a QA build such as com.loci.desktop.qa-eval."); process.exit(2); }
if (OTHERS.has(app) && !opts.app) { console.error(`${app} belongs to another QA run; pass --app ${app} explicitly if you mean it.`); process.exit(2); }
const providerId = (id) => (id === "agy" ? "antigravity" : id);
const judgeProvider = opts.judge ?? opts.provider;
const judgeModel = opts["judge-model"] ?? DEFAULT_JUDGE_MODEL[judgeProvider === "antigravity" ? "agy" : judgeProvider];
const loci = lociCli({ app, bin: opts.bin ?? process.env.LOCI_BIN });

const log = (...parts) => console.error(`[${new Date().toISOString().slice(11, 19)}]`, ...parts);
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

function loadScenarios() {
  const dir = join(HERE, "scenarios");
  const all = readdirSync(dir).filter((name) => name.endsWith(".json")).sort().map((name) => JSON.parse(readFileSync(join(dir, name), "utf8")));
  if (!opts.scenario?.length) return all;
  const unknown = opts.scenario.filter((id) => !all.some((scenario) => scenario.id === id));
  if (unknown.length) throw new Error(`Unknown scenario ${unknown.join(", ")}; have ${all.map((scenario) => scenario.id).join(", ")}`);
  return all.filter((scenario) => opts.scenario.includes(scenario.id));
}

function templateHashes() {
  const dir = join(ROOT, "src/features/agents/templates");
  return Object.fromEntries(["learning-guide", "repo-lens"].map((id) => {
    const file = join(dir, `${id}.md`);
    return [id, existsSync(file) ? createHash("sha256").update(readFileSync(file)).digest("hex").slice(0, 10) : "missing"];
  }));
}

function gitCommit() {
  try { return execFileSync("git", ["rev-parse", "--short", "HEAD"], { cwd: ROOT, encoding: "utf8" }).trim(); } catch { return null; }
}

/** Every file under a folder (relative paths), skipping .git and big trees' internals. */
function walk(root, limit = 4000) {
  const found = [];
  const visit = (dir, depth) => {
    if (found.length >= limit || depth > 8) return;
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (entry.name === ".git" || entry.name === "node_modules" || entry.name === "target") continue;
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path, depth + 1);
      else found.push(relative(root, path));
      if (found.length >= limit) return;
    }
  };
  visit(root, 0);
  return found;
}

function readText(path) {
  try {
    if (!path.startsWith("/") || statSync(path).size > 8 * 1024 * 1024) return null;
    return readFileSync(path, "utf8");
  } catch { return null; }
}

/** One mentor turn: send and wait, retrying a timeout once with the same request id. */
async function turn(mentor, text, timeoutSeconds, failures) {
  const requestId = `eval-${createHash("sha1").update(`${mentor}:${text}:${Date.now()}`).digest("hex").slice(0, 12)}`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      return await loci.call("mentors", "send", mentor, "--text-file", "-", "--wait", "--timeout", String(timeoutSeconds), "--request-id", requestId, { stdin: text });
    } catch (error) {
      if (error instanceof LociCliError && error.code === "busy") {
        failures.push("mentor busy when a message was sent; waited");
        await sleep(15_000);
        continue;
      }
      // The turn ran and the provider failed: a result, not a crash of the run.
      if (error instanceof LociCliError && error.result?.status === "failed") return error.result;
      if (error instanceof LociCliError && error.code === "needs_you") { failures.push("needs-you: the mentor asked for permission in full access"); return { status: "needs-you", text: "" }; }
      if (error instanceof LociCliError && error.code === "timeout" && attempt === 0) { failures.push(`turn timed out after ${timeoutSeconds}s; retried`); continue; }
      throw error;
    }
  }
  return { status: "failed", text: "" };
}

async function libraryState(mentor) {
  const [sources, courses] = await Promise.all([
    loci.call("sources", "list", "--mentor", mentor).catch(() => ({ documents: [] })),
    loci.call("courses", "list", "--mentor", mentor).catch(() => ({ courses: [] })),
  ]);
  const list = Array.isArray(courses) ? courses : courses.courses ?? [];
  return { sources: sources.documents ?? [], courses: list };
}

/** Everything a scenario produced, through the CLI, written under `dir`. */
async function collect(mentor, workdir, dir) {
  const write = (name, value) => { const path = join(dir, name); mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`); };
  const { sources: listed, courses: courseList } = await libraryState(mentor);
  const sources = [];
  for (const entry of listed) {
    const full = await loci.call("sources", "read", entry.id, "--mentor", mentor).catch((error) => ({ ...entry, text: "", error: String(error.message) }));
    const source = { id: entry.id, title: entry.title, kind: full.kind ?? entry.kind ?? (entry.sourceUrl ? "source" : "guide"), sourceUrl: full.sourceUrl ?? entry.sourceUrl ?? null, version: full.version ?? null, body: full.text ?? "" };
    sources.push(source);
    write(`sources/${entry.id}.md`, source.body);
  }
  write("sources.json", sources.map(({ body, ...rest }) => ({ ...rest, chars: body.length })));
  const courses = [];
  for (const entry of courseList) {
    const course = await loci.call("courses", "read", entry.id, "--mentor", mentor).catch(() => null);
    if (!course) continue;
    courses.push(course);
    write(`courses/${entry.id}.json`, course);
  }
  const notes = await loci.call("notes", "list", "--mentor", mentor).catch(() => null);
  if (notes) write("notes.json", notes);
  // The conversation as Loci keeps it (pages of three exchanges).
  const pages = [];
  let before;
  for (let page = 0; page < 20; page++) {
    const read = await loci.call("mentors", "read", mentor, "--max-chars", "6000", "--limit", "3", ...(before ? ["--before", before] : [])).catch(() => null);
    if (!read) break;
    pages.unshift(...(read.turns ?? []));
    if (!read.nextBefore) break;
    before = read.nextBefore;
  }
  write("conversation.json", pages);
  const files = workdir ? walk(workdir) : [];
  write("workdir.txt", `${files.join("\n")}\n`);
  return { sources, courses, files };
}

async function runScenario(scenario, runDir, meta) {
  const dir = join(runDir, scenario.id);
  mkdirSync(dir, { recursive: true });
  const workdir = join(tmpdir(), "loci-eval", meta.stamp, scenario.id);
  const maxTurns = Number(opts["max-turns"] ?? scenario.maxTurns ?? 8);
  const maxMs = Number(opts["max-minutes"] ?? scenario.maxMinutes ?? 18) * 60_000;
  const timeoutSeconds = scenario.turnTimeoutSeconds ?? 600;
  const failures = [];
  const turns = [];
  const decisions = [];
  const timings = {};
  const started = Date.now();
  const elapsed = () => Math.round((Date.now() - started) / 1000);
  let stoppedBy = "learner done";
  let nudges = 0;

  const created = await loci.call("mentors", "create", "--template", scenario.template, "--provider", opts.provider, "--mode", opts.mode,
    "--name", `Eval ${scenario.id}`.slice(0, 40), "--workdir", workdir, ...(opts.model ? ["--model", opts.model] : []));
  const mentor = created.id;
  log(`${scenario.id}: mentor ${mentor} (${created.provider}${created.model ? `/${created.model}` : ""}, ${created.mode})`);
  meta.model ??= created.model ?? null;

  const stamp = async (mentorTurns) => {
    const state = await libraryState(mentor);
    if (timings.firstSource === undefined && state.sources.some((source) => (source.kind ?? (source.sourceUrl ? "source" : "guide")) === "source")) { timings.firstSource = elapsed(); timings.turnsBeforeFirstSource = mentorTurns; }
    if (timings.course === undefined && state.courses.length) timings.course = elapsed();
    return state;
  };

  try {
    let message = scenario.opening;
    const learner = { used: {}, hasCourse: false, nudged: false };
    for (let index = 0; ; index++) {
      turns.push({ role: "learner", text: message, at: elapsed() });
      log(`${scenario.id}: learner → ${message.slice(0, 90)}`);
      const reply = await turn(mentor, message, timeoutSeconds, failures);
      if (reply.status === "failed") failures.push(`turn failed: ${reply.error ?? "no reply"}`);
      turns.push({ role: "mentor", text: reply.text ?? "", status: reply.status, at: elapsed() });
      if (timings.firstReply === undefined) timings.firstReply = elapsed();
      log(`${scenario.id}: mentor (${reply.status}, ${elapsed()}s) ← ${String(reply.text ?? "").replace(/\s+/g, " ").slice(0, 120)}`);
      const state = await stamp(turns.filter((entry) => entry.role === "mentor").length);
      learner.hasCourse = state.courses.length > 0;
      if (reply.status === "needs-you" || reply.status === "failed") { stoppedBy = reply.status; break; }
      if (index + 1 >= maxTurns) { stoppedBy = "turn cap"; break; }
      if (Date.now() - started > maxMs) { stoppedBy = "time cap"; break; }
      const next = nextMessage(reply.text ?? "", scenario.learner, learner);
      decisions.push({ afterTurn: index, ...next });
      if (next.nudge) nudges++;
      if (next.done) break;
      message = next.text;
    }
    // The grounding probe, also asked when a cap stopped the run, unless the mentor is stuck.
    if (scenario.probe && stoppedBy !== "needs-you" && stoppedBy !== "failed") {
      turns.push({ role: "learner", text: scenario.probe, probe: true, at: elapsed() });
      log(`${scenario.id}: probe → ${scenario.probe.slice(0, 90)}`);
      const reply = await turn(mentor, scenario.probe, timeoutSeconds, failures);
      turns.push({ role: "mentor", text: reply.text ?? "", status: reply.status, probe: true, at: elapsed() });
      await stamp(turns.filter((entry) => entry.role === "mentor").length);
    }
  } catch (error) {
    failures.push(`run error: ${error.message}`);
    stoppedBy = "error";
  }

  const shown = await loci.call("mentors", "show", mentor).catch(() => null);
  const collected = await collect(mentor, shown?.workdir ?? workdir, dir);
  const roots = [shown?.workdir ?? workdir, ...(shown?.folders ?? []).map((folder) => folder.path ?? folder).filter((path) => typeof path === "string")];
  timings.total = elapsed();
  const write = (name, value) => writeFileSync(join(dir, name), typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`);
  write("turns.json", turns);
  write("learner.json", decisions);
  write("timings.json", timings);
  write("stop.json", { stoppedBy });
  write("conversation.md", turns.map((entry) => `## ${entry.role === "mentor" ? "Mentor" : entry.probe ? "Learner (probe)" : "Learner"} · ${entry.at}s${entry.status && entry.status !== "done" ? ` · ${entry.status}` : ""}\n\n${entry.text}\n`).join("\n"));

  const runData = { scenario, sources: collected.sources, courses: collected.courses, turns, timings, failures, nudges };
  const score = scoreRun(runData, { readFile: readText, roots });
  write("score.json", score);
  let verdict = null;
  const replied = turns.some((entry) => entry.role === "mentor" && String(entry.text ?? "").trim());
  if (judgeProvider !== "none" && !replied) log(`${scenario.id}: no mentor reply to judge`);
  if (judgeProvider !== "none" && replied) {
    log(`${scenario.id}: judging with ${judgeProvider}${judgeModel ? `/${judgeModel}` : ""}`);
    verdict = await judge({ scenario, checks: score, sources: collected.sources, courses: collected.courses, turns }, { provider: judgeProvider, model: judgeModel });
    write("judge.json", verdict);
    if (!verdict.verdict) log(`${scenario.id}: judge gave no verdict: ${String(verdict.error).split("\n")[0]}`);
  }
  if (!opts.keep) await loci.call("mentors", "delete", mentor, "--yes").catch((error) => log(`${scenario.id}: could not delete mentor: ${error.message}`));
  log(`${scenario.id}: done in ${timings.total}s (${stoppedBy})`);
  return { scenario, score, judge: verdict, run: { stoppedBy, mentor, workdir } };
}

async function main() {
  const scenarios = loadScenarios();
  const status = await loci.call("status");
  if (!status.running) throw new Error(`${app} is not running; start the QA build first (scripts/eval/qa-app.sh up)`);
  const models = await loci.call("models", "list");
  const harness = (models.harnesses ?? []).find((entry) => entry.id === providerId(opts.provider));
  if (!harness?.available) throw new Error(`${opts.provider} is not available in ${app}: ${JSON.stringify(harness ?? "unknown provider")}`);
  if (!opts["skip-probe"]) {
    for (const provider of new Set([opts.provider, ...(judgeProvider === "none" ? [] : [judgeProvider])])) {
      const probe = await probeProvider(provider === "antigravity" ? "agy" : provider);
      if (probe.state !== "ok") {
        const hint = probe.state === "region"
          ? "Antigravity refuses this account's region. Use a proxy exit in a supported region (system-wide, so Loci's adapter inherits it; restart the QA app), or sign in with an eligible account, then rerun."
          : probe.state === "not-signed-in" ? `Sign in first (run \`${provider}\` once interactively), then rerun.`
          : probe.state === "missing" ? `Install the ${provider} CLI.` : "Run it by hand to see why.";
        throw new Error(`${provider} cannot run a turn (${probe.state}): ${probe.said.split("\n").slice(-2).join(" ")}\n${hint}`);
      }
      log(`${provider}: ok`);
    }
  }
  const startedAt = new Date().toISOString();
  const stamp = startedAt.slice(0, 16).replace(/[-:]/g, "").replace("T", "-");
  const runDir = resolve(opts.out ?? join(ROOT, "eval/results", stamp));
  mkdirSync(runDir, { recursive: true });
  const meta = {
    startedAt, stamp, app, appVersion: status.version ?? null, commit: gitCommit(), provider: opts.provider, model: opts.model ?? null, mode: opts.mode,
    judge: { provider: judgeProvider, model: judgeProvider === "none" ? null : judgeModel ?? null }, templates: templateHashes(),
    maxTurns: opts["max-turns"] ? Number(opts["max-turns"]) : undefined, maxMinutes: opts["max-minutes"] ? Number(opts["max-minutes"]) : undefined,
    scenarios: scenarios.map((scenario) => scenario.id),
  };
  log(`results in ${runDir}`);
  const results = [];
  for (const scenario of scenarios) {
    try { results.push(await runScenario(scenario, runDir, meta)); }
    catch (error) { log(`${scenario.id}: ${error.message}`); results.push({ scenario, error: error.message }); }
    writeFileSync(join(runDir, "run.json"), `${JSON.stringify(meta, null, 2)}\n`);
    writeFileSync(join(runDir, "summary.md"), summaryMarkdown(meta, results));
  }
  log(`summary: ${join(runDir, "summary.md")}`);
}

main().catch((error) => { console.error(error.message); process.exit(1); });
