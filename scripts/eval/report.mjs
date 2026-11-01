// summary.md for one evaluation run: a table across scenarios, then what each
// scenario got wrong, so a template change can be judged against the last run.
import { RUBRIC } from "./judge.mjs";

const RUBRIC_LABEL = { firstHand: "First-hand", courseStructure: "Course", grounding: "Grounding", firstTenMinutes: "First 10 min" };
const dash = (value) => (value === null || value === undefined ? "—" : String(value));
const seconds = (value) => (value === null || value === undefined ? "—" : value < 120 ? `${value}s` : `${Math.round(value / 6) / 10}m`);
const ratio = (part, whole) => (whole ? `${part}/${whole}` : "—");

/**
 * The setup a run used. Two runs are comparable only when all of it matches:
 * a different provider, model or judge measures something else.
 */
export function runSetup(meta) {
  return {
    provider: meta.provider,
    model: meta.model ?? null,
    judge: meta.judge?.provider && meta.judge.provider !== "none" ? meta.judge.provider : null,
    judgeModel: meta.judge?.model ?? null,
  };
}

/** The judge, with the model it ran on; an unpinned judge uses the CLI's configured default. */
function judgeLabel(meta) {
  const { judge, judgeModel } = runSetup(meta);
  if (!judge) return "no rubric judge";
  return judgeModel ? `\`${judge}\` / \`${judgeModel}\`` : `\`${judge}\` (its configured default model)`;
}

/** Markdown summary of a run. `results` are { scenario, score, judge, error } per scenario. */
export function summaryMarkdown(meta, results) {
  const lines = [];
  lines.push(`# Mentor evaluation — ${meta.startedAt.slice(0, 16).replace("T", " ")}`);
  lines.push("");
  // The official run is grok mentors on grok:deepseek-flash, judged by grok; a run
  // with another setup is still a real measurement, but only comparable to its own.
  lines.push(`> Mentors on \`${meta.provider}\`${meta.model ? ` / \`${meta.model}\`` : ""}, judged by ${judgeLabel(meta)}. Compare this run only with runs whose provider, model and judge match.`, "");
  lines.push(`- App: \`${meta.app}\` ${dash(meta.appVersion)} · commit \`${dash(meta.commit)}\``);
  lines.push(`- Mentors: \`${meta.provider}\`${meta.model ? ` / \`${meta.model}\`` : ""}, mode \`${meta.mode}\``);
  lines.push(`- Judge: ${meta.judge?.provider && meta.judge.provider !== "none" ? `\`${meta.judge.provider}\`${meta.judge.model ? ` / \`${meta.judge.model}\`` : ""}` : "none"}`);
  lines.push(`- Templates: ${Object.entries(meta.templates ?? {}).map(([id, hash]) => `\`${id}\` ${hash}`).join(", ") || "—"}`);
  lines.push(`- Limits: ${meta.maxTurns ? `${meta.maxTurns} turns` : "turns"} and ${meta.maxMinutes ? `${meta.maxMinutes} min` : "minutes"} ${meta.maxTurns || meta.maxMinutes ? "per scenario" : "as each scenario sets"}`);
  lines.push("");
  lines.push(`| Scenario | Sources (first-party) | Files in place | Guides | Lessons ok | Citations ok (quotes) | First source | Course | Max ?/reply | ${RUBRIC.map((key) => RUBRIC_LABEL[key]).join(" | ")} |`);
  lines.push(`| --- | --- | --- | --- | --- | --- | --- | --- | --- | ${RUBRIC.map(() => "---").join(" | ")} |`);
  for (const { scenario, score, judge, error } of results) {
    if (!score) { lines.push(`| ${scenario.id} | failed: ${String(error ?? "").replace(/\|/g, "/").slice(0, 80)} |${" |".repeat(8 + RUBRIC.length)}`); continue; }
    const s = score;
    const rubric = RUBRIC.map((key) => dash(judge?.verdict?.scores?.[key]?.score));
    lines.push(`| ${scenario.id} | ${s.sources.firstHand} (${s.sources.firstPartyShare === null ? "—" : `${s.sources.firstPartyShare}%`}) | ${s.sources.filesReadInPlace ?? 0} | ${s.sources.guides} | ${ratio(s.course.lessonsResolved, s.course.lessons)} | ${ratio(s.citations.resolved, s.citations.total)} (${ratio(s.citations.quotesResolved, s.citations.quoted)}) | ${seconds(s.firstTenMinutes.firstSourceSeconds)} | ${seconds(s.firstTenMinutes.courseSeconds)} | ${s.firstTenMinutes.maxQuestionsInOneReply} | ${rubric.join(" | ")} |`);
  }
  const judged = results.filter((result) => result.judge?.verdict);
  if (judged.length) {
    const mean = (key) => Math.round((judged.reduce((sum, result) => sum + result.judge.verdict.scores[key].score, 0) / judged.length) * 10) / 10;
    lines.push(`| **mean** | | | | | | | | | ${RUBRIC.map((key) => `**${mean(key)}**`).join(" | ")} |`);
  }
  lines.push("");
  for (const { scenario, score, judge, error, run } of results) {
    lines.push(`## ${scenario.id} (${scenario.template})`, "");
    if (error) lines.push(`- **Run error:** ${error}`);
    if (!score) { lines.push(""); continue; }
    const s = score;
    lines.push(`- Turns: ${s.citations.replies} mentor replies; nudges ${s.firstTenMinutes.nudges}; questions per reply ${s.firstTenMinutes.questionsPerReply.join(", ") || "—"}; first reply ${seconds(s.firstTenMinutes.firstReplySeconds)}${run?.stoppedBy ? `; stopped by ${run.stoppedBy}` : ""}`);
    lines.push(`- Sources: ${s.sources.firstHand} first-hand, ${s.sources.firstParty} first-party, ${s.sources.guides} guides; files read in place ${s.sources.filesReadInPlace ?? 0} (${s.sources.repoFiles ?? 0} in a cloned repo, ${s.sources.downloadedDocuments ?? 0} downloaded documents)${s.sources.offDomain.length ? `; off-domain: ${s.sources.offDomain.map((entry) => `${entry.id} (${entry.url})`).join(", ")}` : ""}`);
    if (s.sources.suspectedSummaries.length) lines.push(`- Possibly not verbatim: ${s.sources.suspectedSummaries.map((entry) => `${entry.id} (${entry.reasons.join("; ")})`).join(", ")}`);
    lines.push(`- Course: ${s.course.courses} course(s), ${s.course.chapters} chapters, ${s.course.lessons} lessons${s.course.withinExpected ? "" : " (outside the expected range)"}; ${s.course.lessonsOnFiles} on files, ${s.course.lessonsOnGuides} on guides`);
    for (const problem of [...s.course.lessonProblems, ...s.course.orderProblems].slice(0, 8)) lines.push(`  - ${problem}`);
    lines.push(`- Citations: ${s.citations.total} in ${s.citations.repliesWithCitations}/${s.citations.replies} replies; probe ${s.citations.probeCited === null ? "not asked" : s.citations.probeCited ? `cited (${s.citations.probeResolved} resolve)` : "**not cited**"}`);
    for (const problem of s.citations.problems.slice(0, 6)) lines.push(`  - ${problem}`);
    for (const failure of s.failures) lines.push(`- Failure: ${failure}`);
    if (judge?.verdict) {
      for (const key of RUBRIC) lines.push(`- ${RUBRIC_LABEL[key]} ${judge.verdict.scores[key].score}/5 — ${judge.verdict.scores[key].reason}`);
      if (judge.verdict.worst) lines.push(`- **Biggest fix:** ${judge.verdict.worst}`);
    } else if (judge) lines.push(`- Judge failed: ${String(judge.error ?? "").split("\n")[0].slice(0, 200)}`);
    lines.push("");
  }
  return `${lines.join("\n").trimEnd()}\n`;
}
