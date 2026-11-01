import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
// @ts-expect-error plain ESM without types
import { FALLBACK, NUDGE, asksSomething, nextMessage, questionCount, topicsOf, questionsIn } from "./learner.mjs";
// @ts-expect-error plain ESM without types
import { checkCitation, checkLessons, citationsIn, flattenMarkdown, headingsOf, isFirstParty, orderProblems, quoteResolves, scoreRun, summarySignals } from "./score.mjs";
// @ts-expect-error plain ESM without types
import { judgeCommand, judgePrompt, parseVerdict } from "./judge.mjs";
// @ts-expect-error plain ESM without types
import { isOfficial, summaryMarkdown } from "./report.mjs";

const answers = { goal: "Fix SQLITE_BUSY.", level: "Comfortable with Go.", time: "An hour a day.", confirm: "Yes, go ahead.", scope: "WAL only.", depth: "Deep.", language: "English.", background: "Go and Linux." };

describe("the scripted learner", () => {
  it("answers the topics a mentor asks about, briefly, and defers on anything else", () => {
    const state = { used: {}, hasCourse: false, nudged: false };
    const first = nextMessage("Before I start: what is your goal with WAL, and how familiar are you with SQLite's locking?", { answers }, state);
    expect(first.topics).toEqual(["goal", "level"]);
    expect(first.text).toBe("Fix SQLITE_BUSY. Comfortable with Go.");
    expect(nextMessage("Do you prefer tabs or spaces?", { answers }, state).text).toBe(FALLBACK);
  });

  it("reads the Chinese the Mentor template speaks", () => {
    expect(topicsOf(questionsIn("你的真实工程目标是什么？"))).toEqual(["goal"]);
    expect(topicsOf(["方案如上，确认后我就开始收集材料，可以吗？"])).toContain("confirm");
  });

  it("gives an answer at most twice, then defers", () => {
    const state = { used: {}, hasCourse: false, nudged: false };
    for (let i = 0; i < 2; i++) expect(nextMessage("What's your goal?", { answers }, state).text).toBe("Fix SQLITE_BUSY.");
    expect(nextMessage("What's your goal?", { answers }, state).text).toBe(FALLBACK);
  });

  it("stops when the mentor asks nothing and a course exists, and nudges once when none does", () => {
    expect(asksSomething("Here is your course. Start with lesson one.")).toBe(false);
    expect(nextMessage("Saved the course.", { answers }, { used: {}, hasCourse: true, nudged: false }).done).toBe(true);
    const state = { used: {}, hasCourse: false, nudged: false };
    expect(nextMessage("I'll look for material.", { answers }, state)).toMatchObject({ text: NUDGE, nudge: true });
    expect(nextMessage("Still looking.", { answers }, state).done).toBe(true);
  });

  it("reads questions asked as a loci-question card, which is a code fence", () => {
    const card = 'WAL has several paths.\n\n```loci-question\n{"questions":[{"id":"target","header":"Learning target","question":"What is the real target behind properly?","options":[{"label":"Mechanism mastery (Recommended)"}]}]}\n```\n\nMy read: mechanism first.';
    expect(asksSomething(card)).toBe(true);
    expect(questionsIn(card)).toEqual(["Learning target: What is the real target behind properly?"]);
    expect(questionCount(card)).toBe(1);
    expect(nextMessage(card, { answers }, { used: {}, hasCourse: false, nudged: false })).toMatchObject({ text: "Fix SQLITE_BUSY.", topics: ["goal"] });
  });

  it("ignores question marks inside code", () => {
    expect(asksSomething("Run this:\n```sql\nSELECT ?;\n```\nDone.")).toBe(false);
  });
});

const sqliteDoc = "# Write-Ahead Logging\n\n## Checkpointing\n\nA checkpoint moves **frames** from the WAL file back into the [database](https://sqlite.org).\n\n## Concurrency\n\nReaders do not block writers.\n";

describe("automatic checks", () => {
  it("flattens Markdown to the text a quote is found in, and lists headings outside code", () => {
    expect(flattenMarkdown("A **bold** [link](x) and `code`.")).toBe("A bold link and code.");
    expect(headingsOf("# One\n```\n# not a heading\n```\n## Two ##\n")).toEqual(["One", "Two"]);
    expect(headingsOf("# 1. Overview\n## 2.1. **Check**pointing\n")).toEqual(["1. Overview", "2.1. Checkpointing"]);
    expect(quoteResolves(sqliteDoc, "moves frames from the WAL file back into the database")).toBe(true);
    expect(quoteResolves(sqliteDoc, "MOVES   frames from the wal file")).toBe(true);
    expect(quoteResolves(sqliteDoc, "copies pages to the journal")).toBe(false);
  });

  it("knows first-party addresses by host suffix or host and path", () => {
    const domains = ["sqlite.org", "github.com/kubernetes"];
    expect(isFirstParty("https://www.sqlite.org/wal.html", domains)).toBe(true);
    expect(isFirstParty("https://github.com/kubernetes/kubernetes/blob/master/README.md", domains)).toBe(true);
    expect(isFirstParty("https://raw.githubusercontent.com/kubernetes/website/main/x.md", ["github.com"])).toBe(true);
    expect(isFirstParty("https://github.com/someone/k8s-notes", domains)).toBe(false);
    expect(isFirstParty("https://medium.com/sqlite-wal", domains)).toBe(false);
    expect(isFirstParty("not a url", domains)).toBe(false);
  });

  it("flags sources that read like the mentor's own summary", () => {
    expect(summarySignals({ body: "In this guide, we will explore WAL. Key takeaways: ...", sourceUrl: "https://sqlite.org/wal.html" }).length).toBeGreaterThan(0);
    expect(summarySignals({ body: "word ".repeat(400), sourceUrl: "https://sqlite.org/wal.html" })).toEqual([]);
  });

  it("checks that lessons point at documents, sections, files and lines that exist, in reading order", () => {
    const sources = new Map([["wal", { body: sqliteDoc, kind: "source" }]]);
    const files: Record<string, string> = { "/w/repos/x/lib.rs": "a\nb\nc\n" };
    const library = { sources, readFile: (path: string) => files[path] ?? null };
    const course = { chapters: [{ title: "WAL", lessons: [
      { id: "concurrency", title: "C", document: "wal", section: "Concurrency" },
      { id: "checkpoint", title: "K", document: "wal", section: "Checkpointing" },
      { id: "missing", title: "M", document: "wal", section: "Recovery" },
      { id: "code", title: "Code", file: "/w/repos/x/lib.rs", lines: [1, 3] },
      { id: "far", title: "Far", file: "/w/repos/x/lib.rs", lines: [2, 90] },
      { id: "gone", title: "Gone", document: "nope" },
    ] }] };
    const results = checkLessons(course, library);
    expect(results.filter((lesson: { ok: boolean }) => lesson.ok).map((lesson: { id: string }) => lesson.id)).toEqual(["concurrency", "checkpoint", "code"]);
    expect(results.find((lesson: { id: string }) => lesson.id === "far").problems[0]).toMatch(/outside/);
    expect(orderProblems(course, sources)).toEqual(['checkpoint ("Checkpointing") comes before concurrency in wal']);
  });

  it("finds citations in a reply and resolves their sections, quotes and lines", () => {
    const sources = new Map([["wal", { body: sqliteDoc }]]);
    const library = { sources, readFile: (path: string) => (path === "/w/a.rs" ? "1\n2\n3" : path === "/w/rel/b.rs" ? "x\ny" : null), roots: ["/w"] };
    const reply = [
      "[ok](loci://source/wal#section=Checkpointing&quote=moves%20frames%20from%20the%20WAL%20file)",
      "[bad quote](loci://source/wal#quote=never%20written)",
      "[no doc](loci://source/other)",
      "[code](/w/a.rs#L2-3)",
      `[rel](loci://file/${Buffer.from("rel/b.rs").toString("base64url")}#L1-2)`,
      "[web](https://sqlite.org)",
    ].join(" ");
    const links = citationsIn(reply);
    expect(links).toHaveLength(5);
    const checked = links.map((link: unknown) => checkCitation(link, library));
    expect(checked.map((entry: { ok: boolean }) => entry.ok)).toEqual([true, false, false, true, true]);
    expect(checked[0].quoted).toBe(true);
  });

  it("scores a whole run", () => {
    const scenario = { id: "sqlite-wal", template: "learning-guide", opening: "Teach me WAL", firstPartyDomains: ["sqlite.org"], expect: { minLessons: 1, maxLessons: 5 } };
    const score = scoreRun({
      scenario,
      sources: [
        { id: "wal", title: "WAL", kind: "source", sourceUrl: "https://sqlite.org/wal.html", body: sqliteDoc + "word ".repeat(300) },
        { id: "blog", title: "Blog", kind: "source", sourceUrl: "https://example.com/wal", body: "word ".repeat(300) },
        { id: "guide", title: "Guide", kind: "guide", body: "Read wal first." },
      ],
      courses: [{ id: "c", title: "C", chapters: [{ title: "A", lessons: [{ id: "l", title: "L", document: "wal", section: "Checkpointing" }, { id: "g", title: "G", document: "guide" }] }] }],
      turns: [
        { role: "learner", text: "Teach me WAL" },
        { role: "mentor", text: "What is your goal? And your level?" },
        { role: "learner", text: "probe", probe: true },
        { role: "mentor", probe: true, text: "See [here](loci://source/wal#quote=Readers%20do%20not%20block%20writers)." },
      ],
      timings: { firstReply: 20, firstSource: 200, course: 300, turnsBeforeFirstSource: 2 },
      failures: [], nudges: 0,
    }, { readFile: () => null, roots: [] });
    expect(score.sources).toMatchObject({ firstHand: 2, guides: 1, firstParty: 1, firstPartyShare: 50 });
    expect(score.course).toMatchObject({ lessons: 2, lessonsResolved: 2, lessonsOnGuides: 1, chapters: 1, withinExpected: true });
    expect(score.citations).toMatchObject({ total: 1, resolved: 1, quoted: 1, probeCited: true });
    expect(score.firstTenMinutes).toMatchObject({ maxQuestionsInOneReply: 2, firstSourceSeconds: 200 });
  });
});

describe("the judge and the summary", () => {
  const verdict = { scores: { firstHand: { score: 4, reason: "docs" }, courseStructure: { score: 3, reason: "ok" }, grounding: { score: 2, reason: "few links" }, firstTenMinutes: { score: 5, reason: "fast" } }, worst: "Cite more." };

  it("reads a verdict out of plain text, a fenced block or a CLI's JSON envelope, and rejects incomplete ones", () => {
    expect(parseVerdict(`Here you go:\n\`\`\`json\n${JSON.stringify(verdict)}\n\`\`\``)).toEqual(verdict);
    expect(parseVerdict(JSON.stringify({ result: JSON.stringify(verdict) }))).toEqual(verdict);
    expect(parseVerdict(JSON.stringify({ scores: { firstHand: { score: 9 } } }))).toBeNull();
    expect(parseVerdict("no json")).toBeNull();
  });

  it("fills the judge prompt kept in the repo with the evidence", () => {
    const prompt = judgePrompt({
      scenario: { opening: "Teach me WAL", template: "learning-guide", learner: { background: "Go engineer" } },
      checks: { sources: { firstHand: 1 } }, sources: [{ id: "wal", title: "WAL", sourceUrl: "https://sqlite.org/wal.html", body: "text" }],
      courses: [], turns: [{ role: "learner", text: "Teach me WAL" }, { role: "mentor", text: "Goal?" }],
    });
    expect(prompt).toContain("Go engineer");
    expect(prompt).toContain("https://sqlite.org/wal.html");
    expect(prompt).toContain("#### Mentor\nGoal?");
    expect(prompt).not.toMatch(/\{\{\w+\}\}/);
  });

  it("runs the pinned agy model by default and other judges only when named", () => {
    expect(judgeCommand("agy", "claude-opus-4-6-thinking", "/p", "prompt")).toEqual(["agy", ["-p", "prompt", "--print-timeout", "600s", "--model", "claude-opus-4-6-thinking"]]);
    expect(judgeCommand("grok", undefined, "/p", "prompt")[1]).toContain("--prompt-file");
    expect(() => judgeCommand("pi", undefined, "/p", "x")).toThrow(/No judge/);
  });

  it("labels a run that is not on Antigravity as provisional", () => {
    const meta = { startedAt: "2026-11-01T10:00:00.000Z", app: "com.loci.desktop.qa-eval", provider: "grok", mode: "full-access", judge: { provider: "grok" }, templates: { "learning-guide": "abc" } };
    expect(isOfficial(meta)).toBe(false);
    expect(isOfficial({ ...meta, provider: "agy", judge: { provider: "agy" } })).toBe(true);
    const text = summaryMarkdown(meta, [{ scenario: { id: "sqlite-wal", template: "learning-guide" }, error: "boom" }]);
    expect(text).toContain("Provisional, non-agy");
    expect(text).toContain("sqlite-wal");
  });
});

describe("scenarios", () => {
  const dir = join(__dirname, "scenarios");
  const scenarios = readdirSync(dir).filter((name) => name.endsWith(".json")).map((name) => ({ name, data: JSON.parse(readFileSync(join(dir, name), "utf8")) }));

  it("are 3 to 5, each complete and named after its file", () => {
    expect(scenarios.length).toBeGreaterThanOrEqual(3);
    expect(scenarios.length).toBeLessThanOrEqual(5);
    for (const { name, data } of scenarios) {
      expect(`${data.id}.json`).toBe(name);
      expect(["learning-guide", "repo-lens"]).toContain(data.template);
      expect(data.opening && data.probe && data.firstPartyDomains.length).toBeTruthy();
      for (const topic of ["goal", "level", "time", "confirm"]) expect(data.learner.answers[topic], `${name} ${topic}`).toBeTruthy();
      expect(data.maxMinutes).toBeLessThanOrEqual(20);
    }
  });
});

it("keeps results out of git", () => {
  expect(readFileSync(join(__dirname, "../../.gitignore"), "utf8")).toMatch(/^eval\/results\/$/m);
});
