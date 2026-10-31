// summary.md for one evaluation run: a table across scenarios, then what each
// scenario got wrong, so a template change can be judged against the last run.
import { RUBRIC } from "./judge.mjs";

const RUBRIC_LABEL = { firstHand: "First-hand", courseStructure: "Course", grounding: "Grounding", firstTenMinutes: "First 10 min" };
const dash = (value) => (value === null || value === undefined ? "—" : String(value));
const seconds = (value) => (value === null || value === undefined ? "—" : value < 120 ? `${value}s` : `${Math.round(value / 6) / 10}m`);
const ratio = (part, whole) => (whole ? `${part}/${whole}` : "—");

/** Whether a run counts as the official baseline: mentors and judge on Antigravity. */
export function isOfficial(meta) {
  const agy = (id) => id === "agy" || id === "antigravity";
  return agy(meta.provider) && agy(meta.judge?.provider);
}

/** Markdown summary of a run. `results` are { scenario, score, judge, error } per scenario. */
export function summaryMarkdown(meta, results) {
  const lines = [];
  const official = isOfficial(meta);
  lines.push(`# Mentor evaluation — ${meta.startedAt.slice(0, 16).replace("T", " ")}`);
  lines.push("");
  if (!official) lines.push(`> **Provisional, non-agy.** Mentors ran on \`${meta.provider}\`${meta.judge?.provider && meta.judge.provider !== "none" ? `, judged by \`${meta.judge.provider}\`` : ", no rubric judge"}. Not the baseline: the baseline runs mentors and judge on Antigravity.`, "");
  lines.push(`- App: \`${meta.app}\` ${dash(meta.appVersion)} · commit \`${dash(meta.commit)}\``);
  lines.push(`- Mentors: \`${meta.provider}\`${meta.model ? ` / \`${meta.model}\`` : ""}, mode \`${meta.mode}\``);
  lines.push(`- Judge: ${meta.judge?.provider && meta.judge.provider !== "none" ? `\`${meta.judge.provider}\`${meta.judge.model ? ` / \`${meta.judge.model}\`` : ""}` : "none"}`);
  lines.push(`- Templates: ${Object.entries(meta.templates ?? {}).map(([id, hash]) => `\`${id}\` ${hash}`).join(", ") || "—"}`);
  lines.push(`- Limits: ${meta.maxTurns ?? "per scenario"} learner turns, ${meta.maxMinutes ?? "per scenario"} min per scenario`);
  lines.push("");
  lines.push(`| Scenario | Sources (first-party) | Guides | Lessons ok | Citations ok (quotes) | First source | Course | Max ?/reply | ${RUBRIC.map((key) => RUBRIC_LABEL[key]).join(" | ")} |`);
  lines.push(`| --- | --- | --- | --- | --- | --- | --- | --- | ${RUBRIC.map(() => "---").join(" | ")} |`);
  for (const { scenario, score, judge, error } of results) {
    if (!score) { lines.push(`| ${scenario.id} | failed: ${String(error ?? "").replace(/\|/g, "/").slice(0, 80)} |${" |".repeat(7 + RUBRIC.length)}`); continue; }
    const s = score;
    const rubric = RUBRIC.map((key) => dash(judge?.verdict?.scores?.[key]?.score));
    lines.push(`| ${scenario.id} | ${s.sources.firstHand} (${s.sources.firstPartyShare === null ? "—" : `${s.sources.firstPartyShare}%`}) | ${s.sources.guides} | ${ratio(s.course.lessonsResolved, s.course.lessons)} | ${ratio(s.citations.resolved, s.citations.total)} (${ratio(s.citations.quotesResolved, s.citations.quoted)}) | ${seconds(s.firstTenMinutes.firstSourceSeconds)} | ${seconds(s.firstTenMinutes.courseSeconds)} | ${s.firstTenMinutes.maxQuestionsInOneReply} | ${rubric.join(" | ")} |`);
  }
  const judged = results.filter((result) => result.judge?.verdict);
  if (judged.length) {
    const mean = (key) => Math.round((judged.reduce((sum, result) => sum + result.judge.verdict.scores[key].score, 0) / judged.length) * 10) / 10;
    lines.push(`| **mean** | | | | | | | | ${RUBRIC.map((key) => `**${mean(key)}**`).join(" | ")} |`);
  }
  lines.push("");
  for (const { scenario, score, judge, error, run } of results) {
    lines.push(`## ${scenario.id} (${scenario.template})`, "");
    if (error) lines.push(`- **Run error:** ${error}`);
    if (!score) { lines.push(""); continue; }
    const s = score;
    lines.push(`- Turns: ${s.citations.replies} mentor replies; nudges ${s.firstTenMinutes.nudges}; questions per reply ${s.firstTenMinutes.questionsPerReply.join(", ") || "—"}; first reply ${seconds(s.firstTenMinutes.firstReplySeconds)}${run?.stoppedBy ? `; stopped by ${run.stoppedBy}` : ""}`);
    lines.push(`- Sources: ${s.sources.firstHand} first-hand, ${s.sources.firstParty} first-party, ${s.sources.guides} guides${s.sources.offDomain.length ? `; off-domain: ${s.sources.offDomain.map((entry) => `${entry.id} (${entry.url})`).join(", ")}` : ""}`);
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
